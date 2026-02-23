import Foundation
import Rainbow

final class Spinner: @unchecked Sendable {
    private static let isTTY = isatty(fileno(stderr)) != 0

    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    private static let allMessages = [
        // Genel işlem
        "Model düşünüyor...",
        "Metin analiz ediliyor...",
        "Yapay zeka işliyor...",
        "Tokenler üretiliyor...",
        "Yanıt hazırlanıyor...",
        // Dil analizi
        "Dilbilgisi kuralları kontrol ediliyor...",
        "Cümle yapıları inceleniyor...",
        "Noktalama işaretleri denetleniyor...",
        "Kelime seçimleri değerlendiriliyor...",
        "Türkçe yazım kuralları uygulanıyor...",
        // Teknik içerik
        "Teknik terimler doğrulanıyor...",
        "Kod örnekleri analiz ediliyor...",
        "API referansları kontrol ediliyor...",
        "Framework isimleri denetleniyor...",
        "Teknik tutarlılık sağlanıyor...",
        // Stil & ton
        "Yazım tonu değerlendiriliyor...",
        "Paragraf akışı inceleniyor...",
        "Anlatım bütünlüğü kontrol ediliyor...",
        "Okuyucu deneyimi analiz ediliyor...",
        "Metin sadeliği ölçülüyor...",
        // Derin analiz
        "Bağlam ilişkileri çözümleniyor...",
        "Anlam tutarlılığı denetleniyor...",
        "Terminoloji birliği sağlanıyor...",
        "İfade zenginliği değerlendiriliyor...",
        "Konu bütünlüğü kontrol ediliyor...",
        // RAG & referans
        "Referans metinlerle karşılaştırılıyor...",
        "Corpus verileri taranıyor...",
        "Benzer yazım kalıpları aranıyor...",
        "Örnek metinler eşleştiriliyor...",
        "Yazım standartları uygulanıyor...",
        // Detay analiz
        "Fiil çekimleri kontrol ediliyor...",
        "Ek kullanımları denetleniyor...",
        "Bağlaç tercihleri inceleniyor...",
        "Devrik cümleler tespit ediliyor...",
        "Edilgen yapılar analiz ediliyor...",
        // Kalite
        "Açıklık ve anlaşılırlık ölçülüyor...",
        "Tekrar eden ifadeler tespit ediliyor...",
        "Gereksiz sözcükler ayıklanıyor...",
        "Özne-yüklem uyumu kontrol ediliyor...",
        "Paragraflar arası geçişler inceleniyor...",
        // İleri analiz
        "Hedef kitle uygunluğu değerlendiriliyor...",
        "Teknik derinlik analiz ediliyor...",
        "Örneklerin yeterliliği kontrol ediliyor...",
        "Başlık-içerik uyumu denetleniyor...",
        "Sonuç ve özet bölümleri inceleniyor...",
        // Son aşama
        "Öneriler derleniyor...",
        "Düzeltme listesi oluşturuluyor...",
        "Sonuçlar biçimlendiriliyor...",
        "Değerlendirme tamamlanıyor...",
        "Son kontroller yapılıyor...",
    ]

    private let label: String
    private let snippets: [String]
    private let messages: [String]
    private let lock = NSLock()
    private var frameIndex = 0
    private var messageIndex = 0
    private var snippetIndex = 0
    private var scrollOffset = 0
    private var tickCount = 0
    private var timer: DispatchSourceTimer?
    private var running = false

    init(label: String = "", contexts: [String] = []) {
        self.label = label

        self.snippets = contexts.compactMap { ctx in
            let clean = ctx
                .components(separatedBy: .newlines).joined(separator: " ")
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            guard !clean.isEmpty else { return nil }
            return clean
        }

        // Shuffle messages so each spinner instance feels different
        var msgs = Self.allMessages
        for i in stride(from: msgs.count - 1, through: 1, by: -1) {
            let j = Int.random(in: 0...i)
            msgs.swapAt(i, j)
        }
        messages = msgs
    }

    convenience init(label: String = "", context: String) {
        self.init(label: label, contexts: context.isEmpty ? [] : [context])
    }

    func start() {
        guard Self.isTTY else { return }

        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()

        FileHandle.standardError.write(Data("\u{1B}[?25l".utf8))

        let queue = DispatchQueue(label: "dev.muharrir.spinner")
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.tick() }
        lock.lock()
        timer = t
        lock.unlock()
        t.resume()
    }

    func stop() {
        guard Self.isTTY else { return }

        lock.lock()
        guard running else { lock.unlock(); return }
        running = false
        timer?.cancel()
        timer = nil
        lock.unlock()

        FileHandle.standardError.write(Data("\r\u{1B}[2K\u{1B}[?25h".utf8))
    }

    private static let terminalWidth: Int = {
        var ws = winsize()
        if ioctl(fileno(stderr), TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 {
            return Int(ws.ws_col)
        }
        return 80
    }()

    /// Reveal words progressively, fitting within maxWidth.
    /// Returns the visible portion and whether the snippet is fully revealed.
    private func wordReveal(_ text: String, wordCount: Int, maxWidth: Int) -> (text: String, done: Bool) {
        guard maxWidth > 0 else { return ("", true) }
        let words = text.split(separator: " ")
        guard !words.isEmpty else { return ("", true) }

        let visibleCount = min(wordCount, words.count)
        var result = ""
        for word in words.prefix(visibleCount) {
            let candidate = result.isEmpty ? String(word) : "\(result) \(word)"
            if candidate.count > maxWidth {
                // Truncate last word to fit
                let remaining = maxWidth - result.count - 1
                if remaining > 2, result.isEmpty {
                    return (String(word.prefix(remaining - 1)) + "…", false)
                }
                break
            }
            result = candidate
        }

        let fullyRevealed = visibleCount >= words.count && result.count <= maxWidth
        return (result, fullyRevealed)
    }

    /// Apply fade edges: dim the first and last few characters.
    private func fadeEdges(_ text: String, edgeWidth: Int = 3) -> String {
        guard text.count > edgeWidth * 2 else { return "\u{1B}[2m\(text)\u{1B}[22m" }
        let chars = Array(text)
        let head = String(chars.prefix(edgeWidth))
        let middle = String(chars[edgeWidth..<chars.count - edgeWidth])
        let tail = String(chars.suffix(edgeWidth))
        return "\u{1B}[2m\(head)\u{1B}[22m\(middle)\u{1B}[2m\(tail)\u{1B}[22m"
    }

    private func tick() {
        lock.lock()
        let frame = frames[frameIndex % frames.count]
        let msg = messages[messageIndex % messages.count]
        let fullSnip = snippets.isEmpty ? "" : snippets[snippetIndex % snippets.count]
        let wordCount = scrollOffset
        frameIndex += 1
        tickCount += 1
        // Reveal one word every 3 ticks (~300ms per word)
        if tickCount % 3 == 0 { scrollOffset += 1 }
        if tickCount % 100 == 0 { // rotate message every ~10s
            messageIndex += 1
        }
        lock.unlock()

        let maxWidth = Self.terminalWidth - 1
        var prefix = " \(frame) "
        if !label.isEmpty { prefix += "\(label) · " }
        prefix += msg

        // Word-by-word reveal with auto-advance on completion
        var snipText = ""
        if !fullSnip.isEmpty {
            let available = maxWidth - prefix.count - 3 // 3 = " · "
            let (revealed, done) = wordReveal(fullSnip, wordCount: wordCount, maxWidth: available)
            snipText = revealed

            if done {
                // All words revealed — advance to next snippet after a pause
                lock.lock()
                if tickCount % 3 == 0 {
                    if !snippets.isEmpty { snippetIndex += 1 }
                    scrollOffset = 1
                }
                lock.unlock()
            }
        }

        var line = prefix
        if !snipText.isEmpty { line += " · \(snipText)" }
        if line.count > maxWidth {
            line = String(line.prefix(maxWidth - 1)) + "…"
        }

        // Style: bold label, fade-edged snippet
        let styled = applyStyle(line, label: label, snippet: snipText)

        let output = "\r\u{1B}[2K\(styled)"
        FileHandle.standardError.write(Data(output.utf8))
    }

    private func applyStyle(_ plain: String, label: String, snippet: String) -> String {
        var styled = plain
        if !label.isEmpty, let range = styled.range(of: label) {
            styled = styled.replacingCharacters(
                in: range, with: "\u{1B}[1m\(label)\u{1B}[22m"
            )
        }
        if !snippet.isEmpty, let range = styled.range(of: snippet, options: .backwards) {
            let faded = fadeEdges(String(styled[range]))
            styled = styled.replacingCharacters(in: range, with: faded)
        }
        return styled
    }
}

/// Buffers streamed tokens and flushes in readable chunks
/// instead of printing character-by-character.
final class StreamPrinter {
    private var buffer = ""

    /// Accumulate a token. Flushes automatically on newlines
    /// or when buffer reaches a readable length.
    func write(_ token: String) {
        buffer += token
        if shouldFlush() { flush() }
    }

    /// Flush any remaining buffered text.
    func finish() {
        if !buffer.isEmpty { flush() }
    }

    private func shouldFlush() -> Bool {
        if buffer.contains("\n") { return true }
        if buffer.count >= 80 {
            // Try to break at last space for cleaner output
            return true
        }
        // Flush on sentence-ending punctuation followed by space
        let trimmed = buffer.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("。")
            || trimmed.hasSuffix(":") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return buffer.count >= 20
        }
        return false
    }

    private func flush() {
        print(buffer, terminator: "")
        buffer = ""
    }
}

enum Terminal {
    static func success(_ text: String) {
        print(text.green)
    }

    static func error(_ text: String) {
        print(text.red)
    }

    static func warning(_ text: String) {
        print(text.yellow)
    }

    static func info(_ text: String) {
        print(text.cyan)
    }

    static func dim(_ text: String) {
        print(text.lightBlack)
    }

    /// Show a progress indicator: "▸ İşleniyor [3/10] Paragraflar 11-15"
    static func progress(current: Int, total: Int, label: String) {
        let bar = progressBar(current: current, total: total, width: 20)
        print("\(bar) [\(current)/\(total)] \(label)".lightBlack)
    }

    /// Warn user if text is large and will take a while.
    static func sizeWarning(charCount: Int, paragraphCount: Int) {
        if charCount > 15000 || paragraphCount > 20 {
            let estimate = paragraphCount / 5 * 2 // ~2 min per batch of 5
            print("⚠ Büyük makale: \(charCount) karakter, \(paragraphCount) paragraf".yellow)
            if estimate > 2 {
                print("  Tahmini süre: ~\(estimate) dakika".yellow)
            }
            print()
        }
    }

    private static func progressBar(current: Int, total: Int, width: Int) -> String {
        guard total > 0 else { return "" }
        let filled = max(1, current * width / total)
        let empty = max(0, width - filled)
        let filledBar = String(repeating: "█", count: filled).cyan
        let emptyBar = String(repeating: "░", count: empty).lightBlack
        return "[\(filledBar)\(emptyBar)]"
    }

    static func header(_ text: String) {
        let border = String(repeating: "─", count: min(text.count + 4, 70))
        print("┌\(border)┐".cyan)
        print("│  \(text.bold)  │".cyan)
        print("└\(border)┘".cyan)
    }

    static func panel(_ title: String, content: String) {
        let border = String(repeating: "─", count: 70)
        print("┌─ \(title.bold) \(String(repeating: "─", count: max(0, 66 - title.count)))┐".cyan)
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            print("│ \(line)".cyan)
        }
        print("└\(border)┘".cyan)
    }
}
