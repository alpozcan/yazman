import Accelerate
import Foundation
import Ollama
import OSLog

/// Simple file-backed vector store using Ollama embeddings and cosine similarity.
actor VectorStore {
    struct Entry: Codable {
        let id: String
        let text: String
        let title: String
        let url: String
        let embedding: [Float]
    }

    private var entries: [Entry] = []
    private var entryIndex: [String: Int] = [:]
    private let client: Ollama.Client
    private let model: Model.ID
    private let storePath: URL

    init(client: Ollama.Client, model: Model.ID = Config.embeddingModel) {
        self.client = client
        self.model = model
        self.storePath = Config.embeddingsFile
    }

    /// Load entries from disk.
    func load() throws {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            guard FileManager.default.fileExists(atPath: storePath.path) else { return }
            do {
                let data = try Data(contentsOf: storePath)
                entries = try JSONDecoder().decode([Entry].self, from: data)
                rebuildIndex()
            } catch {
                Logger.vectorStore.error("Failed to load vector store: \(error.localizedDescription)")
            }
        }
        Logger.vectorStore.info("Loaded \(self.entries.count) entries in \(elapsed)")
    }

    private func rebuildIndex() {
        entryIndex.removeAll(keepingCapacity: true)
        for (i, entry) in entries.enumerated() {
            entryIndex[entry.id] = i
        }
    }

    /// Save entries to disk.
    func save() throws {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            do {
                let data = try JSONEncoder().encode(entries)
                try data.write(to: storePath)
            } catch {
                Logger.vectorStore.error("Failed to save vector store: \(error.localizedDescription)")
            }
        }
        Logger.vectorStore.info("Saved \(self.entries.count) entries in \(elapsed)")
    }

    /// Index a batch of articles. Returns number of chunks indexed.
    func indexArticles(_ articles: [Article]) async throws -> Int {
        let clock = ContinuousClock()
        var totalChunks = 0

        let start = clock.now

        for article in articles {
            let chunks = chunkText(article.text)
            guard !chunks.isEmpty else { continue }

            Logger.vectorStore.debug("Indexing \(chunks.count) chunks for \(article.url)")

            // Embed in batches of 10
            for batchStart in stride(from: 0, to: chunks.count, by: 10) {
                let batchEnd = min(batchStart + 10, chunks.count)
                let batch = Array(chunks[batchStart..<batchEnd])

                let response = try await client.embed(model: model, inputs: batch)
                let embeddings = response.embeddings.rawValue.map { $0.map(Float.init) }

                for (j, embedding) in embeddings.enumerated() {
                    let idx = batchStart + j
                    let id = "\(article.url)::\(idx)"

                    let newEntry = Entry(
                        id: id,
                        text: chunks[idx],
                        title: article.title,
                        url: article.url,
                        embedding: embedding
                    )

                    if let existingIdx = entryIndex[id] {
                        entries[existingIdx] = newEntry
                    } else {
                        entryIndex[id] = entries.count
                        entries.append(newEntry)
                    }
                }
            }

            totalChunks += chunks.count
        }

        try save()

        let elapsed = clock.now - start
        Logger.vectorStore.info("Indexed \(articles.count) articles (\(totalChunks) chunks) in \(elapsed)")
        return totalChunks
    }

    /// Find the most similar entries to a query using partial sort (O(n + k log k)).
    func query(_ text: String, nResults: Int = 5) async throws -> [SearchResult] {
        guard !entries.isEmpty else { return [] }

        let clock = ContinuousClock()
        let start = clock.now

        let response = try await client.embed(model: model, input: text)
        guard let firstEmbedding = response.embeddings.rawValue.first else { return [] }
        let queryEmbedding = firstEmbedding.map(Float.init)

        let k = min(nResults, entries.count)

        // Maintain a fixed-size min-heap of top-k (index, similarity) pairs
        var topIndices = [Int](repeating: 0, count: k)
        var topScores = [Float](repeating: -.greatestFiniteMagnitude, count: k)
        var minIdx = 0 // index into topScores of current minimum

        for (i, entry) in entries.enumerated() {
            let sim = cosineSimilarity(queryEmbedding, entry.embedding)
            if sim > topScores[minIdx] {
                topIndices[minIdx] = i
                topScores[minIdx] = sim
                // Find new minimum
                minIdx = 0
                for j in 1..<k where topScores[j] < topScores[minIdx] {
                    minIdx = j
                }
            }
        }

        // Sort the k winners by descending similarity
        let ranked = (0..<k)
            .sorted { topScores[$0] > topScores[$1] }
            .filter { topScores[$0] > -.greatestFiniteMagnitude }

        let results = ranked.map { j in
            let entry = entries[topIndices[j]]
            return SearchResult(
                text: entry.text,
                title: entry.title,
                url: entry.url,
                similarity: topScores[j]
            )
        }

        let elapsed = clock.now - start
        let topSim = results.first?.similarity ?? 0
        Logger.vectorStore.info("Query returned \(results.count) results (top similarity: \(topSim)) in \(elapsed)")

        return results
    }

    /// Total number of indexed chunks.
    var count: Int { entries.count }

    // MARK: - Private

    /// SIMD-accelerated cosine similarity using Accelerate/vDSP.
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = vDSP.dot(a, b)
        let normA = sqrt(vDSP.sumOfSquares(a))
        let normB = sqrt(vDSP.sumOfSquares(b))
        let denom = normA * normB
        return denom > 0 ? dot / denom : 0
    }

    private func chunkText(_ text: String, chunkSize: Int = 500, overlap: Int = 100) -> [String] {
        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let endOffset = text.distance(from: start, to: text.endIndex)
            let chunkEnd: String.Index

            if endOffset <= chunkSize {
                chunkEnd = text.endIndex
            } else {
                let tentativeEnd = text.index(start, offsetBy: chunkSize)
                // Try to break at sentence boundary
                let searchStart = text.index(start, offsetBy: chunkSize / 2)
                let searchEndIndex = text.index(
                    tentativeEnd, offsetBy: 100, limitedBy: text.endIndex
                ) ?? text.endIndex
                let searchRange = searchStart..<min(searchEndIndex, text.endIndex)

                if let dotPos = text.range(of: ". ", options: .backwards, range: searchRange) {
                    chunkEnd = dotPos.upperBound
                } else if let nlPos = text.range(of: "\n", options: .backwards, range: searchRange) {
                    chunkEnd = nlPos.upperBound
                } else {
                    chunkEnd = tentativeEnd
                }
            }

            let chunk = String(text[start..<chunkEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            if chunk.count > 50 {
                chunks.append(chunk)
            }

            if chunkEnd >= text.endIndex { break }
            start = text.index(chunkEnd, offsetBy: -overlap, limitedBy: text.startIndex) ?? text.startIndex
        }

        return chunks
    }
}

struct SearchResult {
    let text: String
    let title: String
    let url: String
    let similarity: Float
}

struct Article: Codable {
    let url: String
    let title: String
    let author: String
    let text: String
    let language: String
}
