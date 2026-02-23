import ArgumentParser
import Foundation
import Ollama
import OSLog

struct Check: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Makaleyi paragraf paragraf dil kontrolünden geçir."
    )

    @Argument(help: "Kontrol edilecek makale dosyası", transform: { URL(fileURLWithPath: $0) })
    var article: URL

    @Flag(name: .long, help: "RAG bağlamını kullanma")
    var noRag = false

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("check command started: \(article.lastPathComponent), noRag=\(noRag)")

        let client = await MainActor.run { Config.ollamaClient }

        guard await Lifecycle.waitUntilReady(client) else {
            Terminal.error("Ollama başlatılamadı. Kontrol et: brew services info ollama")
            throw ExitCode.failure
        }

        guard try await client.hasModel(Config.defaultModel) else {
            Terminal.error("Model bulunamadı: \(Config.defaultModel). Çalıştır: ollama pull \(Config.defaultModel)")
            throw ExitCode.failure
        }

        let store = VectorStore(client: client)
        try await store.load()

        Terminal.header("Kontrol: \(article.lastPathComponent)")
        try await Checker.checkWording(
            articlePath: article,
            useRAG: !noRag,
            client: client,
            store: store
        )

        let elapsed = clock.now - start
        Logger.general.info("check command completed in \(elapsed)")
    }
}
