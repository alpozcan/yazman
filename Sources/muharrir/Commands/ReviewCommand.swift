import ArgumentParser
import Foundation
import Ollama
import OSLog

struct Review: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Makaleyi bütünsel olarak değerlendir."
    )

    @Argument(help: "İncelenecek makale dosyası", transform: { URL(fileURLWithPath: $0) })
    var article: URL

    @Flag(name: .long, help: "RAG bağlamını kullanma")
    var noRag = false

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("review command started: \(article.lastPathComponent), noRag=\(noRag)")

        let client = await MainActor.run { Config.ollamaClient }

        guard await Lifecycle.waitUntilReady(client) else {
            Terminal.error("Ollama başlatılamadı. Kontrol et: brew services info ollama")
            throw ExitCode.failure
        }

        let store = VectorStore(client: client)
        try await store.load()

        Terminal.header("İnceleme: \(article.lastPathComponent)")
        try await Checker.reviewArticle(
            articlePath: article,
            useRAG: !noRag,
            client: client,
            store: store
        )

        let elapsed = clock.now - start
        Logger.general.info("review command completed in \(elapsed)")
    }
}
