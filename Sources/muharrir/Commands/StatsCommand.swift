import ArgumentParser
import Ollama
import OSLog

struct Stats: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Corpus ve model istatistiklerini göster."
    )

    func run() async throws {
        Logger.general.info("stats command started")

        let client = await MainActor.run { Config.ollamaClient }
        let store = VectorStore(client: client)
        try await store.load()

        let isReachable = await client.isReachable()
        let chunkCount = await store.count

        Terminal.header("Muharrir İstatistikleri")
        print("  Veri dizini:     \(Config.dataDir.path)")
        print("  Corpus dizini:   \(Config.corpusDir.path)")
        print("  Embedding dosya: \(Config.embeddingsFile.path)")
        print("  Toplam chunk:    \(chunkCount)")
        print("  Model:           \(Config.defaultModel)")

        if isReachable {
            Terminal.success("  Ollama durumu:   çalışıyor")

            if let hasModel = try? await client.hasModel(Config.defaultModel) {
                if hasModel {
                    Terminal.success("  Model durumu:    mevcut")
                } else {
                    Terminal.warning("  Model durumu:    bulunamadı — ollama pull \(Config.defaultModel)")
                }
            }
        } else {
            Terminal.error("  Ollama durumu:   çalışmıyor")
        }

        Logger.general.info("stats command completed")
    }
}
