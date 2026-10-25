import AppKit

// DMG penceresinin arka planını çizer: başlık, uygulamadan Applications klasörüne ok
// ve ilk açılış için kısa bir not. 1x ve 2x (Retina) PNG olarak yazar.
// Kullanım: swift scripts/make_dmg_background.swift <çıktı-öneki>
//   → <önek>.png (600×400) ve <önek>@2x.png (1200×800)
// Konumlar scripts/dmg_settings.py içindeki icon_locations ile eşleşmelidir.

private enum Layout {
    static let size = NSSize(width: 600, height: 400)
    static let iconCenterY: CGFloat = 400 - 190          // Finder'da üstten 190
    static let arrowStartX: CGFloat = 238
    static let arrowEndX: CGFloat = 362
    static let top = NSColor(white: 0.97, alpha: 1)
    static let bottom = NSColor(white: 0.90, alpha: 1)
    static let ink = NSColor(white: 0.08, alpha: 1)
    static let accent = NSColor(white: 0.08, alpha: 1)
    static let muted = NSColor(white: 0.42, alpha: 1)
}

private func drawCentered(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let width = attributed.size().width
    attributed.draw(at: NSPoint(x: (Layout.size.width - width) / 2, y: y))
}

private func drawArrow() {
    let y = Layout.iconCenterY
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: Layout.arrowStartX, y: y))
    shaft.line(to: NSPoint(x: Layout.arrowEndX - 6, y: y))
    shaft.lineWidth = 7
    shaft.lineCapStyle = .round
    Layout.ink.setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: NSPoint(x: Layout.arrowEndX - 24, y: y + 20))
    head.line(to: NSPoint(x: Layout.arrowEndX, y: y))
    head.line(to: NSPoint(x: Layout.arrowEndX - 24, y: y - 20))
    head.lineWidth = 7
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    Layout.accent.setStroke()
    head.stroke()
}

private func render(scale: CGFloat, to path: String) throws {
    let pixelsWide = Int(Layout.size.width * scale)
    let pixelsHigh = Int(Layout.size.height * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        throw CocoaError(.fileWriteUnknown)
    }
    // Çizim nokta cinsinden; bağlam oluşturulmadan önce ayarlanmalı ki ölçek uygulansın.
    rep.size = Layout.size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSGradient(starting: Layout.top, ending: Layout.bottom)?
        .draw(in: NSRect(origin: .zero, size: Layout.size), angle: -90)
    drawCentered("Drag Houra to Applications", y: 332,
                 font: .systemFont(ofSize: 20, weight: .semibold), color: Layout.ink)
    drawCentered("Houra'yı Uygulamalar klasörüne sürükleyin", y: 310,
                 font: .systemFont(ofSize: 13), color: Layout.muted)
    drawArrow()
    drawCentered("First launch blocked?  System Settings › Privacy & Security › Open Anyway", y: 26,
                 font: .systemFont(ofSize: 11), color: Layout.muted)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: URL(fileURLWithPath: path))
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Kullanım: swift scripts/make_dmg_background.swift <çıktı-öneki>\n".data(using: .utf8)!)
    exit(1)
}

let prefix = CommandLine.arguments[1]
do {
    try render(scale: 1, to: "\(prefix).png")
    try render(scale: 2, to: "\(prefix)@2x.png")
} catch {
    FileHandle.standardError.write("Arka plan yazılamadı: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
