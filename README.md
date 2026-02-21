<p align="center">
  <h1 align="center">Muharrir</h1>
  <p align="center">
    <em>Türkçe teknik makale yazım denetleyicisi — yerel LLM + RAG ile.</em>
  </p>
  <p align="center">
    <a href="https://github.com/alpozcan/muharrir/releases"><img src="https://img.shields.io/github/v/release/alpozcan/muharrir?style=flat-square&label=version" alt="Release"></a>
    <a href="https://github.com/apple/swift-package-manager"><img src="https://img.shields.io/badge/SPM-compatible-orange?style=flat-square" alt="Swift Package Manager"></a>
    <a href="https://github.com/yonaskolb/Mint"><img src="https://img.shields.io/badge/Mint-compatible-brightgreen?style=flat-square" alt="Mint"></a>
    <a href="https://github.com/alpozcan/homebrew-muharrir"><img src="https://img.shields.io/badge/Homebrew-tap-yellow?style=flat-square&logo=homebrew" alt="Homebrew"></a>
    <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+"></a>
    <a href="https://github.com/alpozcan/muharrir/blob/main/LICENSE"><img src="https://img.shields.io/github/license/alpozcan/muharrir?style=flat-square" alt="License"></a>
  </p>
</p>

---

Muharrir, Türkçe teknik makalelerin dilini ve ifade biçimini yerel LLM (Ollama) ve RAG (Retrieval-Augmented Generation) kullanarak denetler ve iyileştirme önerileri sunar. Verileriniz makinenizden çıkmaz.

## Kurulum

### Homebrew

```bash
brew tap alpozcan/muharrir
brew install muharrir
```

### Mint

```bash
mint install alpozcan/muharrir
```

### Swift Package Manager (kaynak koddan derleme)

```bash
git clone https://github.com/alpozcan/muharrir.git
cd muharrir
swift build -c release
cp .build/release/muharrir /usr/local/bin/
```

### Gereksinimler

Muharrir, [Ollama](https://ollama.ai)'nın yerel olarak çalışmasını gerektirir:

```bash
brew install ollama
brew services start ollama
ollama pull gemma3:4b            # Metin üretimi
ollama pull nomic-embed-text     # Embedding'ler
```

## Kullanim

### Corpus oluşturma

Makaleleri corpus'a ekleyerek RAG bağlamı oluşturun:

```bash
# Yerel markdown dosyaları ekle
muharrir add makale.md diger-makale.md

# Web'den Türkçe teknik makaleleri tara
muharrir scrape https://example.com/swift-makale

# Seed URL'lerden otomatik keşif
muharrir scrape --discover
```

### Dil denetimi

```bash
# Paragraf paragraf dil kontrolü (RAG destekli)
muharrir check makale.md

# RAG olmadan kontrol
muharrir check makale.md --no-rag

# Bütünsel makale incelemesi
muharrir review makale.md

# Somut kelime/ifade iyileştirme önerileri
muharrir improve makale.md
```

### Arama ve istatistik

```bash
# Corpus'ta anlamsal arama
muharrir search "Swift macro kullanımı"

# Sonuç sayısını belirle
muharrir search "async defer" -n 10

# Corpus ve model istatistikleri
muharrir stats
```

## Nasil Calisiyor?

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

1. **Corpus**: Türkçe teknik makaleler chunk'lara bölünür ve `nomic-embed-text` ile embedding'leri oluşturulur
2. **RAG**: Kontrol edilen makaleye en benzer chunk'lar cosine similarity ile bulunur
3. **LLM**: Referans metinlerle birlikte `gemma3:4b` modeline gönderilir ve Türkçe yazım önerileri üretilir

Tüm işlem yerel makinenizde gerçekleşir — veri dışarı çıkmaz.

## OllamaSwift

Muharrir, Ollama REST API ile iletişim için [OllamaSwift](https://github.com/alpozcan/OllamaSwift) kütüphanesini kullanır. OllamaSwift bağımsız bir SPM paketi olarak da kullanılabilir:

```swift
// Package.swift
.package(url: "https://github.com/alpozcan/OllamaSwift.git", from: "1.0.0")
```

```swift
import OllamaSwift

let client = OllamaClient()

// Basit metin üretimi
let response = try await client.generate(model: "gemma3:4b", prompt: "Merhaba!")

// Streaming
for try await chunk in try await client.generateStream(model: "gemma3:4b", prompt: "Merhaba!") {
    print(chunk.response, terminator: "")
}

// Chat
let reply = try await client.chat(model: "gemma3:4b", messages: [
    .system("Sen yardımcı bir asistansın."),
    .user("Swift'te defer ne işe yarar?"),
])

// Embedding
let embedding = try await client.embed(model: "nomic-embed-text", input: "Swift concurrency")
```

## Komutlar

| Komut | Açıklama |
|-------|----------|
| `muharrir add <dosyalar...>` | Yerel dosyaları corpus'a ekle |
| `muharrir scrape [url'ler...]` | Web'den makale tara ve indeksle |
| `muharrir check <makale>` | Paragraf paragraf dil denetimi |
| `muharrir review <makale>` | Bütünsel makale incelemesi |
| `muharrir improve <makale>` | RAG tabanlı iyileştirme önerileri |
| `muharrir search <sorgu>` | Corpus'ta anlamsal arama |
| `muharrir stats` | Corpus ve model istatistikleri |

## Lisans

MIT

## Katkida Bulunma

Pull request'ler memnuniyetle karşılanır. Lütfen önce bir issue açarak değişikliği tartışın.
