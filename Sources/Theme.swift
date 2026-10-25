import AppKit
import SwiftUI

// Dil, renkler ve biçimlendirme. Arayüz siyah-beyazdır; renk yalnız İstatistik'te ve kategori işaretlerinde kullanılır.

// MARK: - Dil

enum Language: String, CaseIterable {
    case system, tr, en

    static var current: Language {
        // HOURA_LANG=en|tr ayarı zorlar (README görüntüleri için)
        get { Language(rawValue: ProcessInfo.processInfo.environment["HOURA_LANG"] ?? UserDefaults.standard.string(forKey: "language") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }

    /// Ayardaki dil; "sistem" ise Mac'in diline göre Türkçe ya da İngilizce.
    static var isTurkish: Bool {
        switch current {
        case .tr: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
        }
    }

    static var locale: Locale { Locale(identifier: isTurkish ? "tr_TR" : "en_US") }
}

/// Metnin Türkçesi ve İngilizcesi yan yana yazılır; seçili dile göre biri döner.
func T(_ tr: String, _ en: String) -> String { Language.isTurkish ? tr : en }

// MARK: - Renkler

enum Ink {
    static let text = Color(white: 0.96)
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let line = Color.white.opacity(0.09)
    static let card = Color.white.opacity(0.04)
    static let glass = Color(red: 0.063, green: 0.063, blue: 0.07).opacity(0.86)
    static let glassStrong = Color(red: 0.047, green: 0.047, blue: 0.05).opacity(0.95)
    static let background = LinearGradient(colors: [Color(white: 0.067), Color(white: 0.024)], startPoint: .top, endPoint: .bottom)
    /// İstatistikte filtre yokken kullanılan vurgu.
    static let statsAccent = Color(red: 0.24, green: 0.55, blue: 1)
}

extension Color {
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xffffff
        self.init(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

/// Algılanan açıklık (CIE L*, 0 siyah – 100 beyaz).
func lightness(_ hex: String) -> Double {
    let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
    func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let r = lin(Double((v >> 16) & 255) / 255), g = lin(Double((v >> 8) & 255) / 255), b = lin(Double(v & 255) / 255)
    let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return y > 0.008856 ? 116 * cbrt(y) - 16 : 903.3 * y
}

/// Kategori karesinin üstündeki simgenin rengi: açık zeminde siyah, koyu zeminde beyaz.
func inkOn(_ hex: String) -> Color { lightness(hex) > 66 ? .black : .white }

let palette = ["#e5675c", "#e8894a", "#e6b450", "#dccf6e", "#93c46c", "#4fbf95", "#4bb3c9", "#4c8df0",
               "#6f7cf2", "#9a7bea", "#de7ab2", "#c98f73", "#a0a3ad", "#e9e9ee", "#3a3f4d"]

// MARK: - Biçimlendirme

/// Günün saati, ondalıklı (14:30 → 14.5). Yaz saati geçişinde de duvar saatini verir.
func hourOfDay(_ date: Date) -> Double {
    let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
    return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
}

/// 22 → "%22" / "22%"
func percent(_ v: Int) -> String { T("%\(v)", "\(v)%") }

/// 95 → "1 sa 35 dk" / "1 h 35 min"
func formatMinutes(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return T("\(m) dk", "\(m) min") }
    return T("\(h) sa \(String(format: "%02d", m)) dk", "\(h) h \(String(format: "%02d", m)) min")
}

/// 95 → "1s 35d" / "1h 35m"
func formatMinutesShort(_ minutes: Int) -> String {
    let h = minutes / 60, m = minutes % 60
    if h == 0 { return T("\(m)d", "\(m)m") }
    return T("\(h)s \(String(format: "%02d", m))d", "\(h)h \(String(format: "%02d", m))m")
}

/// 2052 sn → "34:12"
func formatClock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}

func formatTime(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Language.locale; f.dateFormat = "HH:mm"
    return f.string(from: date)
}

func formatDate(_ date: Date, _ template: String) -> String {
    let f = DateFormatter(); f.locale = Language.locale
    f.setLocalizedDateFormatFromTemplate(template)
    return f.string(from: date)
}

// MARK: - Ortak görünüm parçaları

struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased(with: Language.locale))
            .font(.system(size: 10, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(Ink.muted)
    }
}

/// Kategorinin renkli karesi; içinde emoji ya da ikon olabilir.
struct CategorySwatch: View {
    let category: Topic
    var size: CGFloat = 18

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(Color(hex: category.color))
            .frame(width: size, height: size)
            .overlay {
                if let emoji = category.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: size * 0.6))
                } else if let icon = category.icon, let shape = IconShape(name: icon) {
                    shape.fill(category.iconColor.map { Color(hex: $0) } ?? inkOn(category.color)).frame(width: size * 0.6, height: size * 0.6)
                }
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(white: 0.96)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryBody(configuration: configuration)
    }
    private struct SecondaryBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Ink.text)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Alt çizgili, çerçevesiz metin alanı.
struct UnderlineField: View {
    let placeholder: String
    @Binding var text: String
    var size: CGFloat = 14
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: size, weight: size > 20 ? .light : .regular))
                .foregroundStyle(Ink.text)
                .focused($focused)
                .onSubmit(onSubmit)
                .padding(.vertical, size > 20 ? 8 : 7)
            Rectangle().fill(focused ? Color.white.opacity(0.8) : Color.white.opacity(0.16)).frame(height: 1)
        }
        .onAppear { if autofocus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true } } }
    }
}
