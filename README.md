<p align="center">
  <h1 align="center">Muharrir</h1>
  <p align="center">
    <em>Türkçe teknik makale yazım denetleyicisi — yerel LLM + RAG ile.</em>
  </p>
  <p align="center">
    <a href="https://github.com/alpozcan/muharrir/releases"><img src="https://img.shields.io/github/v/release/alpozcan/muharrir?style=flat-square&label=s%C3%BCr%C3%BCm" alt="Sürüm"></a>
    <a href="https://github.com/alpozcan/muharrir/blob/main/Package.swift"><img src="https://img.shields.io/badge/SPM-uyumlu-orange?style=flat-square" alt="Swift Package Manager"></a>
    <a href="https://github.com/yonaskolb/Mint"><img src="https://img.shields.io/badge/Mint-uyumlu-brightgreen?style=flat-square" alt="Mint"></a>
    <a href="https://github.com/alpozcan/homebrew-muharrir/blob/main/Formula/muharrir.rb"><img src="https://img.shields.io/badge/Homebrew-tap-FBB040?style=flat-square&logo=homebrew&logoColor=white" alt="Homebrew"></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0+"></a>
    <a href="https://github.com/alpozcan/muharrir/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/alpozcan/muharrir/ci.yml?style=flat-square&label=CI" alt="CI"></a>
    <a href="https://github.com/alpozcan/muharrir/blob/main/LICENSE"><img src="https://img.shields.io/badge/lisans-MIT-97ca00?style=flat-square" alt="Lisans"></a>
  </p>
</p>

---

Muharrir, Türkçe teknik makalelerin dilini ve ifade biçimini yerel bir LLM ([Ollama](https://ollama.ai)) ve RAG (Retrieval-Augmented Generation) kullanarak denetler, iyileştirme önerileri sunar. Tüm verileriniz makinenizde kalır; dışarıya hiçbir veri çıkmaz.

## Kurulum

### Homebrew

```bash
brew install alpozcan/muharrir/muharrir
```

### Mint

```bash
mint install alpozcan/muharrir
```

### Kaynaktan Derleme (Swift Package Manager)

```bash
git clone https://github.com/alpozcan/muharrir.git
cd muharrir
swift build -c release
cp .build/release/muharrir /usr/local/bin/
```

### Gereksinimler

Muharrir'in çalışması için [Ollama](https://ollama.ai)'nın yerel olarak kurulu ve çalışır durumda olması gerekir:

```bash
brew install ollama
brew services start ollama
ollama pull gemma3:4b            # Metin üretimi modeli
ollama pull nomic-embed-text     # Embedding modeli
```

## Kullanım

### Corpus Oluşturma

Makaleleri corpus'a ekleyerek RAG bağlamını oluşturun:

```bash
# Yerel markdown dosyalarını ekle
muharrir add makale.md diger-makale.md

# Web'den Türkçe teknik makaleleri tara
muharrir scrape https://example.com/swift-makale

# Seed URL'lerden otomatik keşfet
muharrir scrape --discover
```

### Dil Denetimi

```bash
# Paragraf paragraf dil kontrolü (RAG destekli)
muharrir check makale.md

# RAG olmadan kontrol
muharrir check makale.md --no-rag

# Bütünsel makale incelemesi
muharrir review makale.md

# Somut kelime ve ifade iyileştirme önerileri
muharrir improve makale.md
```

### Arama ve İstatistikler

```bash
# Corpus'ta anlamsal arama
muharrir search "Swift macro kullanımı"

# Sonuç sayısını belirle
muharrir search "async defer" -n 10

# Corpus ve model istatistikleri
muharrir stats
```

## Nasıl Çalışıyor?

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│  Makaleler  │────▶│  Embedding Model │────▶│ Vector Store│
│  (.md)      │     │ (nomic-embed)    │     │ (JSON disk) │
└─────────────┘     └──────────────────┘     └──────┬──────┘
                                                    │
┌─────────────┐     ┌──────────────────┐            │ RAG
│   Analiz    │ ◀───│    LLM Model     │◀───────────┘
│   Çıktısı   │     │  (gemma3:4b)     │
└─────────────┘     └──────────────────┘
```

1. **Corpus**: Türkçe teknik makaleler parçalara (chunk) bölünür ve `nomic-embed-text` ile embedding vektörleri oluşturulur
2. **RAG**: Denetlenen makaleye en benzer parçalar cosine similarity ile bulunur
3. **LLM**: Referans metinlerle birlikte `gemma3:4b` modeline gönderilir ve Türkçe yazım önerileri üretilir

Tüm işlem yerel makinenizde gerçekleşir — veri dışarıya çıkmaz.

## Komutlar

| Komut | Açıklama |
|-------|----------|
| `muharrir add <dosyalar...>` | Yerel dosyaları corpus'a ekler |
| `muharrir scrape [url'ler...]` | Web'den makale tarar ve indeksler |
| `muharrir check <makale>` | Paragraf paragraf dil denetimi yapar |
| `muharrir review <makale>` | Bütünsel makale incelemesi yapar |
| `muharrir improve <makale>` | RAG tabanlı iyileştirme önerileri sunar |
| `muharrir search <sorgu>` | Corpus'ta anlamsal arama yapar |
| `muharrir stats` | Corpus ve model istatistiklerini gösterir |

## Teknik Ayrıntılar

| Bileşen | Teknoloji |
|---------|-----------|
| Dil | Swift 6.0, macOS 13+ |
| CLI Çatısı | [swift-argument-parser](https://github.com/apple/swift-argument-parser) |
| LLM İstemcisi | [ollama-swift](https://github.com/mattt/ollama-swift) |
| HTML Ayrıştırma | [SwiftSoup](https://github.com/scinfu/SwiftSoup) |
| Terminal Renklendirme | [Rainbow](https://github.com/onevcat/Rainbow) |
| Metin Modeli | `gemma3:4b` |
| Embedding Modeli | `nomic-embed-text` |
| Vektör Deposu | Actor tabanlı, cosine similarity, JSON disk |
| Parçalama | 500 karakter, 100 karakter örtüşme |
| Sürekli Entegrasyon | GitHub Actions (derleme + test + SwiftLint) |
| Testler | 70 birim testi |

## Geliştirme

```bash
# Derleme
swift build

# Testleri çalıştır
swift test

# Lint kontrolü
swiftlint --strict
```

## Katkıda Bulunma

Katkılarınızı bekliyoruz! Ayrıntılar için [CONTRIBUTING.md](CONTRIBUTING.md) rehberine göz atın.

Kısaca: bir issue açın, fork'layın, değişikliklerinizi yapın, `swift test` ve `swiftlint --strict` ile doğrulayın, PR gönderin.

## Lisans

[MIT](LICENSE)
