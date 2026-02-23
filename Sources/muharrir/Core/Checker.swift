import Foundation
import Ollama
import OSLog

enum Checker {
    /// Stream a generate response with spinner, returning elapsed time.
    private static func streamWithSpinner(
        client: Ollama.Client,
        prompt: String,
        system: String,
        maxTokens: Int = 1024,
        spinner: Spinner
    ) async throws -> Duration {
        let clock = ContinuousClock()
        spinner.start()

        let start = clock.now
        let stream = await client.generateStream(
            model: Config.defaultModel,
            prompt: prompt,
            options: ["temperature": 0.3, "top_p": 0.9, "num_predict": .init(integerLiteral: maxTokens)],
            system: system,
            keepAlive: .minutes(30)
        )

        let printer = StreamPrinter()
        var firstChunk = true
        for try await chunk in stream {
            if firstChunk { spinner.stop(); firstChunk = false }
            printer.write(chunk.response)
        }
        if firstChunk { spinner.stop() }
        printer.finish()

        return clock.now - start
    }
    /// Extract non-code paragraphs from markdown text.
    static func extractParagraphs(from text: String) -> [String] {
        var paragraphs: [String] = []
        var inCodeBlock = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }
            if trimmed.hasPrefix("#") { continue }
            if trimmed.hasPrefix("- [") { continue }
            if trimmed.hasPrefix("**Platform:") || trimmed.hasPrefix("**Etki:") { continue }
            if trimmed.hasPrefix("#Swift") { continue }
            if trimmed == "---" { continue }
            if trimmed.count > 30 {
                paragraphs.append(trimmed)
            }
        }

        Logger.checker.debug("Extracted \(paragraphs.count) paragraphs")
        return paragraphs
    }

    /// Build RAG context string from similar matches.
    private static func buildRAGContext(
        paragraphs: [String], store: VectorStore
    ) async throws -> String {
        let sample = paragraphs.prefix(3).joined(separator: " ")
        let matches = try await store.query(sample, nResults: 3)
        guard !matches.isEmpty else { return "" }
        var context = "\n\nReferans Türkçe teknik yazım örnekleri (bu tarz ve tonu referans al):\n"
        for m in matches {
            context += "\n---\nKaynak: \(m.title)\n\(String(m.text.prefix(500)))\n"
        }
        return context
    }

    /// Check article wording paragraph by paragraph.
    static func checkWording(
        articlePath: URL,
        useRAG: Bool,
        client: Ollama.Client,
        store: VectorStore
    ) async throws {
        let clock = ContinuousClock()
        let commandStart = clock.now

        let text = try String(contentsOf: articlePath, encoding: .utf8)
        let mainText = text.components(separatedBy: "=========== FINAL SHARED TEXT").first ?? text
        let paragraphs = extractParagraphs(from: mainText)

        guard !paragraphs.isEmpty else {
            Terminal.error("Kontrol edilecek paragraf bulunamadı.")
            return
        }

        Terminal.info("\(paragraphs.count) paragraf kontrol edilecek\n")
        Terminal.sizeWarning(charCount: mainText.count, paragraphCount: paragraphs.count)

        let ragContext = useRAG ? try await buildRAGContext(paragraphs: paragraphs, store: store) : ""

        // Process in batches of 5
        let batchSize = 5
        let totalBatches = (paragraphs.count + batchSize - 1) / batchSize

        for i in stride(from: 0, to: paragraphs.count, by: batchSize) {
            let batch = Array(paragraphs[i..<min(i + batchSize, paragraphs.count)])
            let batchIndex = i / batchSize + 1
            let batchText = batch.enumerated()
                .map { "[\(i + $0.offset + 1)] \($0.element)" }
                .joined(separator: "\n\n")

            let prompt = """
            Aşağıdaki Türkçe teknik makale paragraflarını incele ve dil/ifade önerilerinde bulun:

            \(batchText)
            \(ragContext)

            Her paragraf için önerini ver. Paragraf zaten iyiyse "OK" yaz.
            """

            Logger.checker.debug("Batch \(batchIndex): \(batch.count) paragraphs, prompt size \(prompt.count) chars")

            Terminal.progress(
                current: batchIndex, total: totalBatches,
                label: "Paragraflar \(i + 1)-\(i + batch.count)"
            )

            let spinner = Spinner(
                label: "Paragraflar \(i + 1)-\(i + batch.count)",
                contexts: batch
            )
            let streamElapsed = try await streamWithSpinner(
                client: client, prompt: prompt,
                system: Prompts.wordingExpert, spinner: spinner
            )
            print("\n")

            Logger.checker.info("Batch \(batchIndex) streamed in \(streamElapsed)")
        }

        let totalElapsed = clock.now - commandStart
        Logger.checker.info("checkWording completed in \(totalElapsed)")
    }

    /// Holistic review of an entire article.
    static func reviewArticle(
        articlePath: URL,
        useRAG: Bool,
        client: Ollama.Client,
        store: VectorStore
    ) async throws {
        let clock = ContinuousClock()
        let commandStart = clock.now

        let text = try String(contentsOf: articlePath, encoding: .utf8)
        var mainText = text.components(separatedBy: "=========== FINAL SHARED TEXT").first ?? text
        let paragraphs = extractParagraphs(from: mainText)

        if mainText.count > 5000 {
            Terminal.sizeWarning(charCount: mainText.count, paragraphCount: paragraphs.count)
        }

        if mainText.count > 8000 {
            mainText = String(mainText.prefix(8000)) + "\n\n[... makale kısaltıldı ...]"
        }

        var ragContext = ""
        if useRAG {
            let matches = try await store.query(String(mainText.prefix(1000)), nResults: 3)
            if !matches.isEmpty {
                ragContext = "\n\nReferans yazım örnekleri:\n"
                for m in matches {
                    ragContext += "\n---\n\(String(m.text.prefix(400)))\n"
                }
            }
        }

        let prompt = """
        Aşağıdaki Türkçe teknik makaleyi bütünsel olarak değerlendir:

        \(mainText)
        \(ragContext)
        """

        Logger.checker.debug("Review prompt size: \(prompt.count) chars")

        Terminal.progress(current: 1, total: 1, label: "Makale inceleniyor")

        let spinner = Spinner(
            label: "Makale İncelemesi",
            contexts: paragraphs
        )
        let streamElapsed = try await streamWithSpinner(
            client: client, prompt: prompt,
            system: Prompts.reviewer, spinner: spinner
        )
        print()

        Logger.checker.info("reviewArticle stream completed in \(streamElapsed)")

        let totalElapsed = clock.now - commandStart
        Logger.checker.info("reviewArticle completed in \(totalElapsed)")
    }

    /// Suggest specific wording improvements using RAG context.
    static func suggestImprovements(
        articlePath: URL,
        client: Ollama.Client,
        store: VectorStore
    ) async throws {
        let clock = ContinuousClock()
        let commandStart = clock.now

        let text = try String(contentsOf: articlePath, encoding: .utf8)
        let mainText = text.components(separatedBy: "=========== FINAL SHARED TEXT").first ?? text
        let paragraphs = extractParagraphs(from: mainText)
        let toProcess = Array(paragraphs.prefix(10))
        let total = toProcess.count

        Terminal.sizeWarning(charCount: mainText.count, paragraphCount: paragraphs.count)

        for (i, para) in toProcess.enumerated() {
            let matches = try await store.query(para, nResults: 2)
            guard !matches.isEmpty else { continue }

            let refTexts = matches.map { String($0.text.prefix(300)) }.joined(separator: "\n")

            let prompt = """
            Aşağıdaki paragrafı, verilen referans metinlerin Türkçe kullanım tarzına göre iyileştir.

            Paragraf:
            \(para)

            Referans metinler (bu tarz ve terminolojiyi referans al):
            \(refTexts)

            Yalnızca somut kelime/ifade değişikliği öner. Genel yorum yapma.
            """

            Terminal.progress(current: i + 1, total: total, label: "Paragraf \(i + 1)")

            let spinner = Spinner(
                label: "Paragraf \(i + 1)/\(total)",
                context: para
            )
            let streamElapsed = try await streamWithSpinner(
                client: client, prompt: prompt,
                system: Prompts.wordingExpert, maxTokens: 512, spinner: spinner
            )
            print()

            Logger.checker.info("Paragraph \(i + 1) improvement streamed in \(streamElapsed)")
        }

        let totalElapsed = clock.now - commandStart
        Logger.checker.info("suggestImprovements completed in \(totalElapsed)")
    }
}
