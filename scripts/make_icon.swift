import AppKit

// Houra simgesini 1024×1024 PNG olarak çizer: siyah karo, iç içe dört yuvarlak kare (dıştaki en parlak),
// ortada beyaz nokta. Dikkatin derine inmesi.
// Kullanım: swift scripts/make_icon.swift <çıktı.png>

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Kullanım: swift scripts/make_icon.swift <çıktı.png>\n".data(using: .utf8)!)
    exit(1)
}

let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: rep) else {
    FileHandle.standardError.write("Görüntü tamponu oluşturulamadı\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
NSColor.black.setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(white: 0.09, alpha: 1), ending: NSColor(white: 0, alpha: 1))?.draw(in: tile, angle: -90)

// Merkezde hafif ışık
NSGraphicsContext.saveGraphicsState()
tile.addClip()
let center = NSPoint(x: 512, y: 512)
NSGradient(starting: NSColor(white: 1, alpha: 0.16), ending: NSColor(white: 1, alpha: 0))?
    .draw(fromCenter: center, radius: 0, toCenter: center, radius: 300, options: [])
NSGraphicsContext.restoreGraphicsState()

for (i, size) in [520, 400, 290, 190].map({ CGFloat($0) }).enumerated() {
    let r = NSRect(x: 512 - size / 2, y: 512 - size / 2, width: size, height: size)
    let p = NSBezierPath(roundedRect: r, xRadius: size * 0.26, yRadius: size * 0.26)
    p.lineWidth = 16 - CGFloat(i) * 2
    NSColor.white.withAlphaComponent(0.96 - CGFloat(i) * 0.2).setStroke()
    p.stroke()
}
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 48, y: 512 - 48, width: 96, height: 96)).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG üretilemedi\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    FileHandle.standardError.write("Yazılamadı: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
