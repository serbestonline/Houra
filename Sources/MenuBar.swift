import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement

// Menü çubuğundaki Derinlik simgesi, kalan süre ve menü. Her yerden ⌥⌘N yeni oturum açar.

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var hotKey: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshButton()

        let focus = Focus.shared
        focus.$now.combineLatest(focus.$phase).sink { [weak self] _ in self?.refreshButton() }.store(in: &cancellables)
        focus.onRestStart = { RestOverlay.shared.show() }
        focus.onRestEnd = { _ in
            RestOverlay.shared.hide()
            NewSessionController.shared.show()
        }
        Widgets.shared.start()
        registerHotKey()

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { Snapshot.start(dir: args[i + 1]) }
        if let i = args.firstIndex(of: "--record"), i + 2 < args.count { Snapshot.record(args[i + 1], dir: args[i + 2]) }
        if CommandLine.arguments.contains("--panel") { PanelController.shared.show() }
        if CommandLine.arguments.contains("--new") { NewSessionController.shared.show() }
    }

    // MARK: Simge ve süre

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let f = Focus.shared
        button.image = Glyph.image(phase: f.phase, progress: f.progress)
        button.imagePosition = .imageLeading
        let text: String
        switch f.phase {
        case .idle: text = ""
        case .focus, .paused: text = " " + formatClock(f.remaining)
        case .rest: text = " " + formatClock(f.restRemaining)
        }
        button.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)])
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let f = Focus.shared
        switch f.phase {
        case .idle:
            let today = Store.shared.sessions(from: Calendar.current.startOfDay(for: Date()), to: .distantFuture)
            let todos = Store.shared.todos(day: dayKey(Date()))
            menu.addItem(header(T("Bugün \(formatMinutes(today.reduce(0) { $0 + $1.minutes })) odak", "Today \(formatMinutes(today.reduce(0) { $0 + $1.minutes })) focused"),
                                T("\(today.count) oturum · \(todos.filter { $0.state == .done }.count) / \(todos.count) görev 🥳",
                                  "\(today.count) sessions · \(todos.filter { $0.state == .done }.count) / \(todos.count) tasks 🥳")))
            menu.addItem(.separator())
            let start = item(T("Oturum başlat…", "Start session…"), key: "n") { NewSessionController.shared.show() }
            start.attributedTitle = NSAttributedString(string: start.title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            menu.addItem(start)
            menu.addItem(submenu(T("Son oturumu tekrarla", "Repeat a recent session"), recentMenu()))
        case .focus, .paused:
            let name = f.topic?.name ?? ""
            menu.addItem(header("● \(name) · \(f.session?.goal ?? "")",
                                T("\(formatClock(f.remaining)) kaldı", "\(formatClock(f.remaining)) left") + (f.activeTodo.map { T(" · şu an: ", " · now: ") + $0.title } ?? "")))
            menu.addItem(.separator())
            if f.phase == .focus {
                menu.addItem(item(T("Duraklat", "Pause"), key: ".") { Focus.shared.pause() })
            } else {
                menu.addItem(item(T("Devam et", "Resume"), key: ".") { Focus.shared.resume() })
            }
            menu.addItem(item(T("Oturumu bitir", "Finish session")) { Focus.shared.finish() })
        case .rest:
            menu.addItem(header(T("Mola · \(formatClock(f.restRemaining))", "Break · \(formatClock(f.restRemaining))"),
                                T("Mola ekranından acil durumla döndün.", "You left the break screen early.")))
            menu.addItem(.separator())
            menu.addItem(item(T("Molaya geri dön", "Back to break")) { RestOverlay.shared.show() })
            menu.addItem(item(T("Molayı bitir, yeni oturum…", "End break, new session…")) { Focus.shared.endRest(emergency: false) })
        }
        menu.addItem(.separator())
        menu.addItem(submenu(T("Ekranda göster", "Show on screen"), viewsMenu()))
        menu.addItem(item(T("Paneli aç…", "Open panel…"), key: "p") { PanelController.shared.show() })
        menu.addItem(.separator())
        menu.addItem(item(T("Açılışta başlat", "Launch at login"), checked: SMAppService.mainApp.status == .enabled) { [weak self] in self?.toggleLoginItem() })
        menu.addItem(item(T("Ayarlar…", "Settings…"), key: ",") { PanelController.shared.show(page: .settings) })
        menu.addItem(item(T("Houra'dan çık", "Quit Houra"), key: "q") { NSApp.terminate(nil) })
    }

    private func recentMenu() -> NSMenu {
        let m = NSMenu()
        let topics = Dictionary(uniqueKeysWithValues: Store.shared.categories().map { ($0.id, $0) })
        var seen = Set<String>()
        for s in Store.shared.sessions(from: Date().addingTimeInterval(-30 * 86400), to: .distantFuture).reversed() {
            guard let t = topics[s.categoryID], seen.insert("\(s.categoryID)|\(s.goal)|\(s.workMinutes)").inserted else { continue }
            let it = item("\(t.name) · \(s.goal)  (\(s.workMinutes) + \(s.restMinutes))") {
                Focus.shared.start(topic: t, goal: s.goal, todoIDs: [], newTodos: [], work: s.workMinutes, rest: s.restMinutes)
            }
            it.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { r in
                NSColor(hex: t.color).setFill(); NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).fill(); return true
            }
            m.addItem(it)
            if seen.count == 5 { break }
        }
        if m.items.isEmpty { m.addItem(disabled(T("Henüz oturum yok", "No sessions yet"))) }
        return m
    }

    private func viewsMenu() -> NSMenu {
        let m = NSMenu()
        for style in WidgetStyle.allCases {
            m.addItem(item(style.title, checked: Widgets.shared.style == style) { Widgets.shared.style = style })
        }
        return m
    }

    private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch { NSLog("Houra açılış ayarı: %@", error.localizedDescription) }
    }

    private func header(_ title: String, _ subtitle: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let s = NSMutableAttributedString(string: title + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        s.append(NSAttributedString(string: subtitle, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        it.attributedTitle = s
        it.isEnabled = false
        return it
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: ""); it.isEnabled = false; return it
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: ""); it.submenu = menu; return it
    }

    private func item(_ title: String, key: String = "", checked: Bool = false, _ handler: @escaping () -> Void) -> NSMenuItem {
        let it = ClosureMenuItem(title: title, keyEquivalent: key, handler: handler)
        it.state = checked ? .on : .off
        return it
    }

    // MARK: ⌥⌘N

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { NewSessionController.shared.show() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x484f5552), id: 1)   // "HOUR"
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: keyEquivalent)
        target = self
    }
    required init(coder: NSCoder) { fatalError("kullanılmıyor") }
    @objc private func fire() { handler() }
}

extension NSColor {
    convenience init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xffffff
        self.init(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }
}

/// Derinlik simgesinin menü çubuğu hali: boşta iki kare ve nokta; oturumda dış kare ilerledikçe çizilir; molada yalnız dış kare.
enum Glyph {
    static func image(phase: Focus.Phase, progress: Double) -> NSImage {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let outer = framePath()
            outer.lineWidth = 1.3
            outer.lineCapStyle = .round
            switch phase {
            case .idle:
                NSColor.black.setStroke(); outer.stroke()
                let inner = NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.5, width: 7, height: 7), xRadius: 2, yRadius: 2)
                inner.lineWidth = 1.1; NSColor.black.withAlphaComponent(0.7).setStroke(); inner.stroke()
                NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 6.8, y: 6.8, width: 2.4, height: 2.4)).fill()
            case .focus, .paused:
                NSColor.black.withAlphaComponent(0.3).setStroke(); outer.stroke()
                let perimeter = 4 * (13 - 2 * 3.6) + 2 * .pi * 3.6
                var dash: [CGFloat] = [CGFloat(progress) * perimeter, perimeter]
                outer.setLineDash(&dash, count: 2, phase: 0)
                NSColor.black.setStroke(); outer.stroke()
            case .rest:
                NSColor.black.setStroke(); outer.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    /// Üst ortadan başlayıp saat yönünde dönen yuvarlak kare (çizgi buradan dolmaya başlar).
    private static func framePath() -> NSBezierPath {
        let r: CGFloat = 3.6, x0: CGFloat = 1.5, y0: CGFloat = 1.5, x1: CGFloat = 14.5, y1: CGFloat = 14.5
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 8, y: y0))
        p.line(to: NSPoint(x: x1 - r, y: y0))
        p.appendArc(withCenter: NSPoint(x: x1 - r, y: y0 + r), radius: r, startAngle: 270, endAngle: 360)
        p.line(to: NSPoint(x: x1, y: y1 - r))
        p.appendArc(withCenter: NSPoint(x: x1 - r, y: y1 - r), radius: r, startAngle: 0, endAngle: 90)
        p.line(to: NSPoint(x: x0 + r, y: y1))
        p.appendArc(withCenter: NSPoint(x: x0 + r, y: y1 - r), radius: r, startAngle: 90, endAngle: 180)
        p.line(to: NSPoint(x: x0, y: y0 + r))
        p.appendArc(withCenter: NSPoint(x: x0 + r, y: y0 + r), radius: r, startAngle: 180, endAngle: 270)
        p.close()
        return p
    }
}
