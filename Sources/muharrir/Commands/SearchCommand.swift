import ArgumentParser
import Ollama

struct Search: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Corpus'ta benzer metin ara."
    )

    @Argument(help: "Arama sorgusu")
    var query: String

    @Option(name: .shortAndLong, help: "Sonuç sayısı")
    var count: Int = 5

    func run() async throws {
        let client = await MainActor.run { Ollama.Client.default }
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
    }
}
