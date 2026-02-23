import ArgumentParser
import Ollama
import OSLog

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Corpus'ta benzer metin ara."
    )

    @Argument(help: "Arama sorgusu")
    var query: String

    @Option(name: .shortAndLong, help: "Sonuç sayısı")
    var count: Int = 5

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("search command started: query=\"\(query)\", count=\(count)")

        let client = await MainActor.run { Config.ollamaClient }

        guard await Lifecycle.waitUntilReady(client) else {
            Terminal.error("Ollama başlatılamadı. Kontrol et: brew services info ollama")
            throw ExitCode.failure
        }

        let store = VectorStore(client: client)
        try await store.load()

        let storeCount = await store.count
        guard storeCount > 0 else {
            Terminal.warning("Corpus boş. Önce 'muharrir scrape' veya 'muharrir add' çalıştırın.")
            return
        }

        Terminal.info("Aranıyor: \"\(query)\"...\n")

        let matches = try await store.query(query, nResults: count)

        if matches.isEmpty {
            Terminal.warning("Sonuç bulunamadı.")
            return
        }

        for (i, m) in matches.enumerated() {
            Terminal.panel(
                "Sonuç \(i + 1)",
                content: """
                \(m.title)
                \(String(m.text.prefix(300)))...

                Benzerlik: \(String(format: "%.4f", m.similarity))
                """
            )
            print()
        }

        let elapsed = clock.now - start
        Logger.general.info("search command completed in \(elapsed)")
    }
}
