import ArgumentParser
import Foundation
import Ollama
import OSLog

struct Improve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "RAG corpus'unu kullanarak somut iyileştirme önerileri sun."
    )

    @Argument(help: "İyileştirilecek makale dosyası", transform: { URL(fileURLWithPath: $0) })
    var article: URL

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("improve command started: \(article.lastPathComponent)")

        let client = await MainActor.run { Config.ollamaClient }

        guard await Lifecycle.waitUntilReady(client) else {
            Terminal.error("Ollama başlatılamadı. Kontrol et: brew services info ollama")
            throw ExitCode.failure
        }

        let store = VectorStore(client: client)
        try await store.load()

        Terminal.header("İyileştirme Önerileri: \(article.lastPathComponent)")
        try await Checker.suggestImprovements(
            articlePath: article,
            client: client,
            store: store
        )

        let elapsed = clock.now - start
        Logger.general.info("improve command completed in \(elapsed)")
    }
}
