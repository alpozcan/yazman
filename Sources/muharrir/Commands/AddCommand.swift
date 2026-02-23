import ArgumentParser
import Foundation
import Ollama
import OSLog

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Yerel markdown/text dosyalarını corpus'a ekle."
    )

    @Argument(help: "Eklenecek dosya yolları", transform: { URL(fileURLWithPath: $0) })
    var paths: [URL]

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("add command started: \(paths.count) files")

        try Config.ensureDirectories()

        var articles: [Article] = []

        for path in paths {
            guard FileManager.default.fileExists(atPath: path.path) else {
                Terminal.error("Dosya bulunamadı: \(path.path)")
                continue
            }

            do {
                let article = try Scraper.loadLocalFile(at: path)
                try Scraper.cacheArticle(article)
                articles.append(article)
                Terminal.success("  Eklendi: \(path.lastPathComponent)")
            } catch {
                Terminal.error("  Hata: \(path.lastPathComponent) - \(error.localizedDescription)")
            }
        }

        if !articles.isEmpty {
            let client = await MainActor.run { Config.ollamaClient }

            guard await Lifecycle.waitUntilReady(client) else {
                Terminal.error("Ollama başlatılamadı. Kontrol et: brew services info ollama")
                throw ExitCode.failure
            }

            Terminal.info("Embedding'ler oluşturuluyor...")
            let store = VectorStore(client: client)
            try await store.load()
            let chunks = try await store.indexArticles(articles)
            Terminal.success("\(articles.count) dosyadan \(chunks) chunk indekslendi")
        }

        let elapsed = clock.now - start
        Logger.general.info("add command completed in \(elapsed)")
    }
}
