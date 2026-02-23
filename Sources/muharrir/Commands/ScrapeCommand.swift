import ArgumentParser
import Ollama
import OSLog

struct Scrape: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Türkçe teknik makaleleri tara ve corpus'a ekle."
    )

    @Flag(name: .long, help: "Seed URL'lerden bağlantı keşfet")
    var discover = false

    @Argument(help: "Taranacak URL'ler")
    var urls: [String] = []

    func run() async throws {
        let clock = ContinuousClock()
        let start = clock.now

        Logger.general.info("scrape command started: \(urls.count) URLs, discover=\(discover)")

        try Config.ensureDirectories()

        let targetURLs: [String]
        if urls.isEmpty {
            targetURLs = Config.seedURLs
        } else {
            targetURLs = urls
        }

        var allURLs = targetURLs

        if discover {
            Terminal.info("Seed URL'lerden bağlantılar keşfediliyor...")
            for seed in Config.seedURLs.prefix(5) {
                let links = await Scraper.discoverLinks(from: seed)
                allURLs.append(contentsOf: links)
            }
        }

        let uniqueURLs = Array(Set(allURLs))
        Terminal.info("\(uniqueURLs.count) URL taranacak...")

        var articles: [Article] = []

        for (i, url) in uniqueURLs.enumerated() {
            print("  [\(i + 1)/\(uniqueURLs.count)] \(String(url.prefix(60)))...", terminator: " ")

            do {
                if let article = try await Scraper.fetchArticle(url: url) {
                    try Scraper.cacheArticle(article)
                    articles.append(article)
                    Terminal.success("OK")
                } else {
                    Terminal.warning("atlandı")
                }
            } catch {
                Terminal.error("hata: \(error.localizedDescription)")
            }
        }

        Terminal.success("\n\(articles.count) makale toplandı")

        if !articles.isEmpty {
            Terminal.info("Embedding'ler oluşturuluyor ve indeksleniyor...")
            let client = await MainActor.run { Config.ollamaClient }
            let store = VectorStore(client: client)
            try await store.load()
            let chunks = try await store.indexArticles(articles)
            Terminal.success("\(articles.count) makaleden \(chunks) chunk indekslendi")
        }

        let elapsed = clock.now - start
        Logger.general.info("scrape command completed in \(elapsed)")
    }
}
