import Foundation
import Ollama

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
        guard FileManager.default.fileExists(atPath: storePath.path) else { return }
        let data = try Data(contentsOf: storePath)
        entries = try JSONDecoder().decode([Entry].self, from: data)
    }

    /// Save entries to disk.
    func save() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storePath)
    }

    /// Index a batch of articles. Returns number of chunks indexed.
    func indexArticles(_ articles: [Article]) async throws -> Int {
        var totalChunks = 0

        for article in articles {
            let chunks = chunkText(article.text)
            guard !chunks.isEmpty else { continue }

            // Embed in batches of 10
            for batchStart in stride(from: 0, to: chunks.count, by: 10) {
                let batchEnd = min(batchStart + 10, chunks.count)
                let batch = Array(chunks[batchStart..<batchEnd])

                let response = try await client.embed(model: model, inputs: batch)
                let embeddings = response.embeddings.rawValue.map { $0.map(Float.init) }

                for (j, embedding) in embeddings.enumerated() {
                    let idx = batchStart + j
                    let id = "\(article.url)::\(idx)"

                    // Remove existing entry with same ID
                    entries.removeAll { $0.id == id }

                    entries.append(Entry(
                        id: id,
                        text: chunks[idx],
                        title: article.title,
                        url: article.url,
                        embedding: embedding
                    ))
                }
            }

            totalChunks += chunks.count
        }

        try save()
        return totalChunks
    }

    /// Find the most similar entries to a query.
    func query(_ text: String, nResults: Int = 5) async throws -> [SearchResult] {
        guard !entries.isEmpty else { return [] }

        let response = try await client.embed(model: model, input: text)
        guard let firstEmbedding = response.embeddings.rawValue.first else { return [] }
        let queryEmbedding = firstEmbedding.map(Float.init)

        var scored: [(entry: Entry, similarity: Float)] = entries.map { entry in
            (entry, cosineSimilarity(queryEmbedding, entry.embedding))
        }

        scored.sort { $0.similarity > $1.similarity }

        return scored.prefix(nResults).map { item in
            SearchResult(
                text: item.entry.text,
                title: item.entry.title,
                url: item.entry.url,
                similarity: item.similarity
            )
        }
    }

    /// Total number of indexed chunks.
    var count: Int { entries.count }

    // MARK: - Private

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
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
