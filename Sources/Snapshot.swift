import AppKit

// Geliştirici aracı: README görselleri ve GIF kareleri. Uygulama kendi pencerelerinin görüntüsünü
// izinsiz alabildiği için ekran kaydı izni gerekmez. Senaryolar sahte bir masaüstü zemininde birleştirilir.
//   HOURA_DB=demo.sqlite Houra --snapshot <klasör>             durağan ekran görüntüleri
//   HOURA_DB=demo.sqlite Houra --record <senaryo> <klasör>      kareler (flow, widgets, stats, rest)

enum Snapshot {
    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    /// Eski pencere görüntüsü API'si Swift'te kapalı; çalışma anında bulunur.
    private static let windowImage: WindowImageFn? = {
        guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    static func image(of window: NSWindow) -> CGImage? {
        windowImage?(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue()
    }

    static func capture(_ window: NSWindow?, to path: String) {
        guard let window, let img = image(of: window) else { return }
        write(img, to: path)
    }

    static func write(_ img: CGImage, to path: String) {
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    /// Adımları sırayla, aralarında bekleyerek çalıştırır.
    static func run(_ steps: [(Double, () -> Void)], done: @escaping () -> Void) {
        var delay = 0.0
        for (wait, step) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: step)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.4, execute: done)
    }

    static func panelWindow() -> NSWindow? { NSApp.windows.first { $0.frameAutosaveName == "HouraPanel" } }
    static func sheetWindow() -> NSWindow? { NSApp.windows.first { $0 is KeyWindow && $0.isVisible && $0.level == .floating } }

    // MARK: Durağan görüntüler

    static func start(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let panel = PanelController.shared
        var steps: [(Double, () -> Void)] = []
        for page in PanelController.Page.allCases {
            steps.append((0.2, { panel.show(page: page) }))
            steps.append((1.0, { capture(panelWindow(), to: "\(dir)/panel-\(page.rawValue).png") }))
        }
        steps.append((0.1, { panel.show(page: .categories) }))
        steps.append((0.6, { NotificationCenter.default.post(name: .pickerCommand, object: nil, userInfo: ["tab": 2]) }))
        steps.append((0.8, {
            let pop = NSApp.windows.filter { $0.isVisible && $0.className.contains("Popover") }
            if let p = pop.first, let w = panelWindow() { composite([w, p], canvas: w.frame.insetBy(dx: -1, dy: -1), desktop: false).map { write($0, to: "\(dir)/categories-picker.png") } }
            NotificationCenter.default.post(name: .pickerCommand, object: nil, userInfo: ["close": true])
        }))
        steps.append((0.4, { NewSessionController.prefillGoal = T("Brief'i incele", "Review the brief"); NewSessionController.shared.show() }))
        steps.append((0.9, { capture(sheetWindow(), to: "\(dir)/new-session.png") }))
        run(steps) { NSApp.terminate(nil) }
    }

    // MARK: Birleştirme

    /// Pencereleri, verilen ekran dikdörtgeninde, isteğe bağlı sahte masaüstü üzerinde birleştirir.
    static func composite(_ windows: [NSWindow], canvas: NSRect, scale: CGFloat = 1, desktop: Bool = true) -> CGImage? {
        let w = Int(canvas.width * scale), h = Int(canvas.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        if desktop { drawDesktop(ctx, size: canvas.size) } else { ctx.setFillColor(NSColor(white: 0.03, alpha: 1).cgColor); ctx.fill(CGRect(origin: .zero, size: canvas.size)) }
        for win in windows where win.isVisible && win.alphaValue > 0.01 {
            guard let img = image(of: win) else { continue }
            let f = win.frame
            ctx.setAlpha(win.alphaValue)
            ctx.draw(img, in: CGRect(x: f.minX - canvas.minX, y: f.minY - canvas.minY, width: f.width, height: f.height))
            ctx.setAlpha(1)
        }
        return ctx.makeImage()
    }

    /// Koyu gradyan masaüstü ve üstünde açık renkli bir belge penceresi; görünümlerin gerçek bir işin üstünde nasıl durduğu görülsün.
    private static func drawDesktop(_ ctx: CGContext, size: CGSize) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space, colors: [NSColor(white: 0.16, alpha: 1).cgColor, NSColor(white: 0.03, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: size.width * 0.25, y: size.height * 0.85), startRadius: 0,
                               endCenter: CGPoint(x: size.width * 0.25, y: size.height * 0.85), endRadius: max(size.width, size.height), options: [.drawsAfterEndLocation])
        let doc = CGRect(x: size.width * 0.07, y: size.height * 0.08, width: size.width * 0.56, height: size.height * 0.78)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 60, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addPath(CGPath(roundedRect: doc, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(NSColor(white: 0.955, alpha: 1).cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.setFillColor(NSColor(white: 0.89, alpha: 1).cgColor)
        ctx.fill(CGRect(x: doc.minX, y: doc.maxY - 38, width: doc.width, height: 38))
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(c.withAlphaComponent(0.85).cgColor)
            ctx.fillEllipse(in: CGRect(x: doc.minX + 14 + CGFloat(i) * 20, y: doc.maxY - 25, width: 12, height: 12))
        }
        ctx.setFillColor(NSColor(white: 0.2, alpha: 1).cgColor)
        ctx.fill(CGRect(x: doc.minX + 56, y: doc.maxY - 100, width: doc.width * 0.5, height: 22))
        for i in 0..<9 {
            ctx.setFillColor(NSColor(white: 0.8, alpha: 1).cgColor)
            let lw = doc.width * (i % 3 == 2 ? 0.45 : 0.78)
            ctx.fill(CGRect(x: doc.minX + 56, y: doc.maxY - 150 - CGFloat(i) * 34, width: lw, height: 12))
        }
    }

    // MARK: Kayıt

    final class Recorder {
        let dir: String, fps: Double, frameSource: () -> CGImage?
        private var timer: Timer?
        private var index = 0
        init(dir: String, fps: Double = 12, frame: @escaping () -> CGImage?) {
            self.dir = dir; self.fps = fps; frameSource = frame
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        func start() {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / fps, repeats: true) { [weak self] _ in
                guard let self, let img = frameSource() else { return }
                Snapshot.write(img, to: String(format: "%@/f%05d.png", dir, index)); index += 1
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        func stop() { timer?.invalidate() }
    }

    static func record(_ scenario: String, dir: String) {
        let screen = NSScreen.screens[0]
        let topics = Store.shared.categories()
        func startDemoSession(_ topicIndex: Int = 0) {
            let today = Store.shared.todos(day: dayKey(Date())).filter { $0.state != .done && $0.sessionID == nil }
            Focus.shared.start(topic: topics[min(topicIndex, topics.count - 1)], goal: T("Brief'i incele", "Review the brief"),
                               todoIDs: today.prefix(3).map(\.id), newTodos: [], work: 50, rest: 10)
            Focus.shared.debugShift(by: -16 * 60)   // 16 dakika önce başlamış gibi
        }
        let stats = { (info: [String: Any]) in NotificationCenter.default.post(name: .statsCommand, object: nil, userInfo: info) }

        switch scenario {
        case "stats":
            let panel = PanelController.shared
            panel.show(page: .stats)
            let rec = Recorder(dir: dir) { panelWindow().flatMap { composite([$0], canvas: $0.frame, scale: 1, desktop: false) } }
            let mostRecent = Calendar.current.startOfDay(for: Date().addingTimeInterval(-86400))
            run([(1.0, { rec.start() }), (1.4, { stats(["period": "month"]) }), (1.6, { stats(["hover": topics[1].id]) }),
                 (0.9, { stats(["hover": topics[2].id]) }), (0.9, { stats(["hover": Int64(-1)]) }), (0.4, { stats(["filter": topics[1].id]) }),
                 (1.8, { stats(["filter": Int64(-1)]) }), (0.8, { stats(["chart": 1]) }), (1.8, { stats(["chart": 2]) }),
                 (1.8, { stats(["chart": 0]) }), (0.8, { stats(["open": mostRecent]) }), (2.2, { stats(["close": true]) }),
                 (0.8, { stats(["period": "year"]) }), (1.8, { stats(["period": "week"]) }), (1.2, { rec.stop() })]) { NSApp.terminate(nil) }

        case "widgets":
            startDemoSession()
            // Ekranın sağ kısmı: görünümler ve açılan paneller okunur boyda kalsın
            let canvas = NSRect(x: screen.frame.maxX - 1040, y: screen.frame.minY, width: 1040, height: screen.frame.height)
            let rec = Recorder(dir: dir) { composite(Widgets.shared.debugWindows, canvas: canvas, scale: 0.7) }
            var steps: [(Double, () -> Void)] = [(0.6, { rec.start() })]
            for style in [WidgetStyle.tag, .strip, .capsule, .card, .ring] {
                steps += [(0.2, { Widgets.shared.style = style }), (1.3, { Widgets.shared.debugOpenDetail() }), (2.6, { Widgets.shared.closeDetail() })]
            }
            steps.append((0.9, { rec.stop() }))
            run(steps) { Focus.shared.stop(); NSApp.terminate(nil) }

        case "snap":
            startDemoSession()
            Widgets.shared.style = .tag
            let canvas = screen.frame
            let rec = Recorder(dir: dir) { composite(Widgets.shared.debugWindows, canvas: canvas, scale: 0.5) }
            let move = { (dx: CGFloat, dy: CGFloat) in
                guard let f = Widgets.shared.debugWindows.first?.frame else { return }
                Widgets.shared.debugMove(to: f.offsetBy(dx: dx, dy: dy))
            }
            var steps: [(Double, () -> Void)] = [(0.6, { rec.start() })]
            // Tutup çekiyormuş gibi adım adım sola, bırakınca kenara yapışır; sonra sağa geri
            for _ in 0..<10 { steps.append((0.06, { move(-canvas.width * 0.045, -14) })) }
            steps += [(0.3, { Widgets.shared.debugDragEnd() }), (1.6, {})]
            for _ in 0..<10 { steps.append((0.06, { move(canvas.width * 0.05, 14) })) }
            steps += [(0.3, { Widgets.shared.debugDragEnd() }), (1.6, { rec.stop() })]
            run(steps) { Focus.shared.stop(); NSApp.terminate(nil) }

        case "flow":
            NewSessionController.prefillGoal = T("Brief'i incele", "Review the brief")
            Widgets.shared.style = .tag
            let canvas = screen.frame
            let rec = Recorder(dir: dir) {
                let windows = [sheetWindow()].compactMap { $0 } + Widgets.shared.debugWindows + NSApp.windows.filter { $0 is KeyWindow && $0.level == .screenSaver }
                return composite(windows, canvas: canvas, scale: 0.5)
            }
            run([(0.3, { NewSessionController.shared.show() }), (0.9, { rec.start() }), (2.4, {
                    NewSessionController.shared.close(); startDemoSession()
                 }),
                 (1.6, { Widgets.shared.debugOpenDetail() }),
                 (1.5, { if let t = Focus.shared.todos.first { Focus.shared.set(t, .done) } }),
                 (1.0, { if let t = Focus.shared.todos.dropFirst().first { Focus.shared.set(t, .doing) } }),
                 (1.6, { Widgets.shared.closeDetail() }), (1.0, { Focus.shared.finish() }),
                 (4.0, { rec.stop() })]) { RestOverlay.shared.hide(); Focus.shared.endRest(emergency: false); NSApp.terminate(nil) }

        case "rest":
            startDemoSession()
            let rec = Recorder(dir: dir) { NSApp.windows.first { $0 is KeyWindow && $0.level == .screenSaver && $0.screen == screen }.flatMap { composite([$0], canvas: $0.frame, scale: 0.5, desktop: false) } }
            run([(0.5, { Focus.shared.finish() }), (0.2, { rec.start() }), (6.0, { rec.stop() })]) {
                RestOverlay.shared.hide(); NSApp.terminate(nil)
            }

        default:
            NSApp.terminate(nil)
        }
    }
}
