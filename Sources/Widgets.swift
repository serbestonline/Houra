import AppKit
import Combine
import SwiftUI

// Oturum sürerken ekranda duran küçük görünümler: etiket, ince şerit, kapsül, kart, halka.
// Üzerine gelip bekleyince ayrıntı paneli açılır, fare çekilince kapanır. Basılı tutup çekince taşınır;
// etiket ve şerit bırakılınca en yakın kenara (sol ya da sağ) yapışır.

enum WidgetStyle: String, CaseIterable {
    case tag, strip, capsule, card, ring, none
    var title: String {
        switch self {
        case .tag: return T("Etiket", "Tag")
        case .strip: return T("İnce şerit", "Thin strip")
        case .capsule: return T("Kapsül", "Capsule")
        case .card: return T("Kart", "Card")
        case .ring: return T("Halka", "Ring")
        case .none: return T("Hiçbiri", "None")
        }
    }
    var snapsToEdge: Bool { self == .tag || self == .strip }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }
}

final class Widgets: ObservableObject {
    static let shared = Widgets()

    var style: WidgetStyle {
        get { WidgetStyle(rawValue: UserDefaults.standard.string(forKey: "widgetStyle") ?? "") ?? .tag }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "widgetStyle"); objectWillChange.send(); rebuild() }
    }
    /// Kenara yapışan görünümün tarafı.
    @Published var onLeft = UserDefaults.standard.bool(forKey: "widgetLeft") { didSet { UserDefaults.standard.set(onLeft, forKey: "widgetLeft") } }
    @Published var detailOpen = false
    @Published private(set) var nudging = false

    private var compact: FloatingPanel?
    private var detail: FloatingPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var openTimer: Timer?
    private var watchTimer: Timer?
    private var outsideSince: Date?
    private var dragOrigin: (mouse: NSPoint, frame: NSRect)?

    func start() {
        Focus.shared.$phase.removeDuplicates().sink { [weak self] phase in
            DispatchQueue.main.async { phase == .focus || phase == .paused ? self?.rebuild() : self?.teardown() }
        }.store(in: &cancellables)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.compact != nil { self?.rebuild() }
        }
    }

    // MARK: Kurulum

    private func rebuild() {
        teardown()
        guard style != .none, Focus.shared.phase == .focus || Focus.shared.phase == .paused else { return }
        let size = compactSize
        let p = FloatingPanel(size: size)
        p.contentView = NSHostingView(rootView: CompactView(style: style).environmentObject(self))
        p.setFrame(restoredFrame(size: size), display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.4; p.animator().alphaValue = 1 }
        compact = p
    }

    private func teardown() {
        closeDetail()
        nudging = false
        compact?.orderOut(nil)
        compact = nil
    }

    private var compactSize: NSSize {
        switch style {
        case .tag: return NSSize(width: 300, height: 92)
        case .strip: return NSSize(width: 260, height: (screen?.visibleFrame.height ?? 800))
        case .capsule: return NSSize(width: 372, height: 96)
        case .card: return NSSize(width: 250, height: 290)
        case .ring: return NSSize(width: 116, height: 116)
        case .none: return .zero
        }
    }

    private var screen: NSScreen? { compact?.screen ?? NSScreen.screens.first }   // ana ekran: menü çubuğunun olduğu

    private func restoredFrame(size: NSSize) -> NSRect {
        let vf = NSScreen.screens[0].visibleFrame
        switch style {
        case .strip:
            return NSRect(x: onLeft ? vf.minX : vf.maxX - size.width, y: vf.minY, width: size.width, height: vf.height)
        case .tag:
            let y = UserDefaults.standard.object(forKey: "tagY") as? Double ?? Double(vf.maxY - 300)
            return NSRect(x: onLeft ? vf.minX : vf.maxX - size.width, y: min(max(vf.minY, y), vf.maxY - size.height), width: size.width, height: size.height)
        default:
            let key = "pos.\(style.rawValue)"
            if let s = UserDefaults.standard.string(forKey: key) {
                let o = NSPointFromString(s)
                if NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: o.x + 20, y: o.y + 20)) }) { return NSRect(origin: o, size: size) }
            }
            return NSRect(x: vf.maxX - size.width - 30, y: vf.maxY - size.height - 30, width: size.width, height: size.height)
        }
    }

    // MARK: Üzerine gelme

    func hover(_ inside: Bool) {
        openTimer?.invalidate()
        guard inside, !detailOpen, !nudging, dragOrigin == nil else { return }
        openTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.openDetail() }
    }

    private func openDetail() {
        guard let compact, let vf = compact.screen?.visibleFrame, detail == nil else { return }
        let vertical = style == .strip
        let p = FloatingPanel(size: NSSize(width: vertical ? 380 : 360, height: 400))
        let host = NSHostingView(rootView: DetailCard(vertical: vertical, edgeLeft: style.snapsToEdge ? onLeft : nil))
        p.contentView = host
        let fit = NSHostingView(rootView: DetailCard(vertical: vertical, edgeLeft: nil, scrolls: false)).fittingSize
        let height = vertical ? vf.height : min(fit.height, vf.height - 24)
        var frame = NSRect(x: 0, y: 0, width: vertical ? 380 : 360, height: height)
        let c = compact.frame
        switch style {
        case .strip:
            frame.origin = NSPoint(x: onLeft ? vf.minX : vf.maxX - frame.width, y: vf.minY)
        case .tag:
            frame.origin = NSPoint(x: onLeft ? vf.minX : vf.maxX - frame.width, y: c.maxY + 40 - frame.height)
        default:
            let right = c.midX < vf.midX
            frame.origin = NSPoint(x: right ? c.maxX + 12 : c.minX - frame.width - 12, y: c.maxY + 40 - frame.height)
        }
        frame.origin.y = min(max(vf.minY + 8, frame.origin.y), vf.maxY - frame.height - 8)
        frame.origin.x = min(max(vf.minX, frame.origin.x), vf.maxX - frame.width)
        p.setFrame(frame, display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        detail = p
        detailOpen = true
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.35; p.animator().alphaValue = 1 }
        // Fare iki pencerenin de dışında kalınca kapat
        outsideSince = nil
        watchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.watchMouse() }
    }

    private func watchMouse() {
        guard let detail else { return }
        let m = NSEvent.mouseLocation
        let inside = detail.frame.insetBy(dx: -8, dy: -8).contains(m) || (compact?.frame.insetBy(dx: -4, dy: -4).contains(m) ?? false)
        let typing = detail.isKeyWindow && (detail.firstResponder is NSTextView)
        if inside || typing || NSEvent.pressedMouseButtons != 0 { outsideSince = nil; return }
        if outsideSince == nil { outsideSince = Date() }
        if Date().timeIntervalSince(outsideSince!) > 0.28 { closeDetail() }
    }

    /// Geliştirici kancası: kayıt betiği ayrıntı panelini fare olmadan açar.
    func debugOpenDetail() { openDetail(); watchTimer?.invalidate(); watchTimer = nil }   // fare yok; kendiliğinden kapanmasın
    var debugWindows: [NSWindow] { [compact, detail].compactMap { $0 } }
    /// Geliştirici kancası: kenara yapışan görünümü sürüklemeden öbür tarafa taşır.
    func debugMove(to frame: NSRect) { compact?.setFrame(frame, display: true) }
    func debugDragEnd() { dragOrigin = (NSEvent.mouseLocation, compact?.frame ?? .zero); dragEnded() }

    func closeDetail() {
        watchTimer?.invalidate(); watchTimer = nil
        guard let d = detail else { return }
        detail = nil
        detailOpen = false
        NSAnimationContext.runAnimationGroup({ c in c.duration = 0.25; d.animator().alphaValue = 0 }, completionHandler: { d.orderOut(nil) })
    }

    // MARK: Mola hatırlatması

    /// Serbest oturumda 50 dakika dolunca görünümün kendisi mola sorusuna döner; Devam et ile eski haline gelir.
    func showNudge() {
        closeDetail()
        nudging = true
        resizeCompact(to: nudgeSize)
    }

    func endNudge() {
        nudging = false
        resizeCompact(to: compactSize)
    }

    private var nudgeSize: NSSize {
        style == .strip || style == .card ? compactSize : NSSize(width: max(compactSize.width, 270), height: 186)
    }

    /// Üst kenarı ve yapıştığı yanı yerinde tutarak boyutu değiştirir.
    private func resizeCompact(to size: NSSize) {
        guard let c = compact, c.frame.size != size else { return }
        let f = c.frame, vf = c.screen?.visibleFrame ?? f
        let right = style.snapsToEdge ? !onLeft : f.midX > vf.midX
        c.setFrame(NSRect(x: right ? f.maxX - size.width : f.minX, y: f.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    // MARK: Sürükleme

    func dragChanged() {
        guard let compact, !nudging else { return }
        openTimer?.invalidate()
        if detailOpen { closeDetail() }
        let m = NSEvent.mouseLocation
        if dragOrigin == nil { dragOrigin = (m, compact.frame) }
        guard let o = dragOrigin else { return }
        var f = o.frame
        f.origin.x += m.x - o.mouse.x
        if style != .strip { f.origin.y += m.y - o.mouse.y }
        compact.setFrame(f, display: true)
    }

    func dragEnded() {
        guard let compact, dragOrigin != nil else { return }
        dragOrigin = nil
        let f = compact.frame
        guard let vf = (NSScreen.screens.first { $0.frame.contains(NSPoint(x: f.midX, y: f.midY)) } ?? NSScreen.main)?.visibleFrame else { return }
        if style.snapsToEdge {
            onLeft = f.midX < vf.midX
            var target = f
            target.origin.x = onLeft ? vf.minX : vf.maxX - f.width
            target.origin.y = style == .strip ? vf.minY : min(max(vf.minY, f.origin.y), vf.maxY - f.height)
            if style == .tag { UserDefaults.standard.set(Double(target.origin.y), forKey: "tagY") }
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.45
                c.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                compact.animator().setFrame(target, display: true)
            }
        } else {
            UserDefaults.standard.set(NSStringFromPoint(f.origin), forKey: "pos.\(style.rawValue)")
        }
    }
}

// MARK: - Görünümler

/// Bütün ekranlar üç kez beyaz yanıp söner; tıklamaları engellemez.
enum ScreenPulse {
    static func flash() {
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.wantsLayer = true
            v.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            v.layer?.borderWidth = 8
            v.layer?.opacity = 0
            w.contentView = v
            w.orderFrontRegardless()
            let a = CABasicAnimation(keyPath: "opacity")
            a.fromValue = 0; a.toValue = 1; a.duration = 0.3; a.autoreverses = true; a.repeatCount = 3
            v.layer?.add(a, forKey: "pulse")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { w.orderOut(nil) }
        }
    }
}

/// Ayrıntı panelinin kabı: cam zemin, kenara yapışıksa o tarafta köşesiz.
private struct DetailCard: View {
    let vertical: Bool
    let edgeLeft: Bool?
    var scrolls = true
    var body: some View {
        DetailView(vertical: vertical, scrolls: scrolls)
            .frame(width: vertical ? 380 : 360)
            .background(shape.fill(Ink.glassStrong))
            .overlay(shape.strokeBorder(Ink.line))
            .environment(\.colorScheme, .dark)
    }
    private var shape: SideRoundedRect {
        SideRoundedRect(radius: vertical ? 0 : 24, flatLeft: edgeLeft == true, flatRight: edgeLeft == false)
    }
}

private struct CompactView: View {
    let style: WidgetStyle
    @EnvironmentObject private var widgets: Widgets
    @ObservedObject private var focus = Focus.shared

    var body: some View {
        content
            .opacity(widgets.detailOpen && style != .strip ? 0 : 1)
            .scaleEffect(widgets.detailOpen && style != .strip ? 0.9 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: widgets.detailOpen)
            .onHover { widgets.hover($0) }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in widgets.dragChanged() }
                .onEnded { _ in widgets.dragEnded() })
            .environment(\.colorScheme, .dark)
            .foregroundStyle(Ink.text)
    }

    @ViewBuilder private var content: some View {
        if widgets.nudging { nudge } else { styled }
    }

    @ViewBuilder private var styled: some View {
        switch style {
        case .tag: tag
        case .strip: strip
        case .capsule: capsule
        case .card: card
        case .ring: ring
        case .none: EmptyView()
        }
    }

    private var groupName: some View {
        HStack(spacing: 6) {
            if let t = focus.topic { CategorySwatch(category: t, size: 9) }
            Text(focus.topic?.name.uppercased(with: Language.locale) ?? "").font(.system(size: 9.5, weight: .semibold)).tracking(1.6).foregroundStyle(Ink.muted)
        }
    }

    // Etiket: kenara yapışık, grup adı, görev ve süre; altta ince ilerleme
    private var tag: some View {
        let left = widgets.onLeft
        return HStack(spacing: 14) {
            if !left { grip }
            VStack(alignment: .leading, spacing: 4) {
                groupName
                Text(focus.headline).font(.system(size: 14, weight: .medium)).lineLimit(1).frame(maxWidth: 170, alignment: .leading)
            }
            Text(formatClock(focus.clock)).font(.system(size: 24, weight: .light)).monospacedDigit()
            if left { grip }
        }
        .padding(.leading, left ? 18 : 14).padding(.trailing, left ? 14 : 18).frame(height: 66)
        .background(alignment: .bottom) {
            GeometryReader { g in
                Rectangle().fill(Color.white.opacity(0.85)).frame(width: g.size.width * focus.progress, height: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left ? .bottomLeading : .bottomLeading)
            }
        }
        .background(SideRoundedRect(radius: 18, flatLeft: left, flatRight: !left).fill(Ink.glass))
        .overlay(SideRoundedRect(radius: 18, flatLeft: left, flatRight: !left).strokeBorder(Ink.line))
        .clipShape(SideRoundedRect(radius: 18, flatLeft: left, flatRight: !left))
        .shadow(color: .black.opacity(0.35), radius: 16, x: left ? 8 : -8, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: left ? .leading : .trailing)
    }

    // Mola sorusu: serbest oturumda 50 dakika dolunca her görünüm buna döner
    private var nudge: some View {
        let left = widgets.onLeft, edge = style.snapsToEdge
        let shape = SideRoundedRect(radius: 20, flatLeft: edge && left, flatRight: edge && !left)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                groupName
                Spacer()
                Text(formatClock(focus.clock)).font(.system(size: 14, weight: .light)).monospacedDigit().foregroundStyle(Ink.muted)
            }
            Text(T("\(Int(focus.elapsed) / 60) dakikadır çalışıyorsun", "\(Int(focus.elapsed) / 60) minutes in")).font(.system(size: 15, weight: .medium)).padding(.top, 10)
            Text(T("Mola isteğe bağlı.", "The break is optional.")).font(.system(size: 11.5)).foregroundStyle(Ink.muted).padding(.top, 3)
            HStack(spacing: 6) {
                Button(T("Devam et", "Keep going")) { widgets.endNudge() }.buttonStyle(SecondaryButtonStyle())
                Button(T("Mola ver", "Take a break")) { focus.finish() }.buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(width: 240)
        .background(shape.fill(Ink.glass))
        .overlay(shape.strokeBorder(Ink.line))
        .shadow(color: .black.opacity(0.4), radius: 16, x: edge ? (left ? 8 : -8) : 0, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge ? (left ? .leading : .trailing) : .center)
    }

    private var grip: some View { Capsule().fill(Color.white.opacity(0.18)).frame(width: 3, height: 26) }

    // İnce şerit: ekran kenarında, aşağıdan dolar; etiketi dolumun tepesinde
    private var strip: some View {
        let left = widgets.onLeft
        return GeometryReader { g in
            ZStack(alignment: left ? .bottomLeading : .bottomTrailing) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 5)
                Rectangle().fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: g.size.height * focus.progress)
                    .shadow(color: .white.opacity(0.35), radius: 8)
                VStack(alignment: left ? .leading : .trailing, spacing: 1) {
                    Text(formatClock(focus.clock)).font(.system(size: 15)).monospacedDigit()
                    Text(focus.headline).font(.system(size: 10.5)).foregroundStyle(Ink.muted).lineLimit(1).frame(maxWidth: 200, alignment: left ? .leading : .trailing)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.glass))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line))
                .padding(left ? .leading : .trailing, 14)
                .offset(y: -(g.size.height * focus.progress) + 20)
                .opacity(widgets.detailOpen ? 0 : 1)
            }
            .frame(width: g.size.width, height: g.size.height, alignment: left ? .bottomLeading : .bottomTrailing)
        }
    }

    // Kapsül: başlık ve kategori, süre, halkalı duraklat düğmesi
    private var capsule: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(focus.headline).font(.system(size: 13, weight: .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let t = focus.topic { CategorySwatch(category: t, size: 9) }
                    Text("\(focus.topic?.name ?? "") · \(focus.session?.goal ?? "")").font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(1)
                }
            }
            .padding(.leading, 10)
            Spacer(minLength: 0)
            Text(formatClock(focus.clock)).font(.system(size: 22, weight: .light)).monospacedDigit()
            Button { focus.phase == .paused ? focus.resume() : focus.pause() } label: {
                ZStack {
                    RingShape(progress: 1).stroke(Color.white.opacity(0.1), lineWidth: 2.5)
                    RingShape(progress: focus.progress).stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    Circle().fill(Color.white.opacity(0.08)).padding(5)
                    Image(systemName: focus.phase == .paused ? "play.fill" : "pause.fill").font(.system(size: 12))
                }
                .frame(width: 46, height: 46)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(width: 340, height: 62)
        .background(Capsule().fill(Ink.glass))
        .overlay(Capsule().strokeBorder(Ink.line))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Kart: büyük halka ve süre, altında görev
    private var card: some View {
        VStack(spacing: 12) {
            ZStack {
                RingShape(progress: 1).stroke(Color.white.opacity(0.08), lineWidth: 5)
                RingShape(progress: focus.progress).stroke(LinearGradient(colors: [.white, Color(white: 0.7)], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Text(formatClock(focus.clock)).font(.system(size: 34, weight: .thin)).monospacedDigit()
            }
            .frame(width: 150, height: 150)
            Text(focus.headline).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(maxWidth: 180)
        }
        .padding(18)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Ink.glass))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Ink.line))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Halka: içinde süre
    private var ring: some View {
        ZStack {
            Circle().fill(Ink.glass)
            Circle().strokeBorder(Ink.line)
            RingShape(progress: 1).stroke(Color.white.opacity(0.08), lineWidth: 3).padding(6)
            RingShape(progress: focus.progress).stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round)).padding(6)
            Text(formatClock(focus.clock)).font(.system(size: 14, weight: .medium)).monospacedDigit()
        }
        .frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Saat 12'den başlayıp saat yönünde ilerleyen halka.
struct RingShape: Shape {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * max(0.001, progress)), clockwise: false)
        return p
    }
}

/// Bir yanı düz (ekran kenarına yaslanan), öbür yanı yuvarlak dikdörtgen. macOS 13 için elle çizilir.
struct SideRoundedRect: InsettableShape {
    var radius: CGFloat
    var flatLeft = false
    var flatRight = false
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let rl = flatLeft ? 0 : min(radius, r.height / 2), rr = flatRight ? 0 : min(radius, r.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rl, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rr, y: r.minY))
        if rr > 0 { p.addArc(center: CGPoint(x: r.maxX - rr, y: r.minY + rr), radius: rr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rr))
        if rr > 0 { p.addArc(center: CGPoint(x: r.maxX - rr, y: r.maxY - rr), radius: rr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        p.addLine(to: CGPoint(x: r.minX + rl, y: r.maxY))
        if rl > 0 { p.addArc(center: CGPoint(x: r.minX + rl, y: r.maxY - rl), radius: rl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + rl))
        if rl > 0 { p.addArc(center: CGPoint(x: r.minX + rl, y: r.minY + rl), radius: rl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> SideRoundedRect { var s = self; s.inset += amount; return s }
}
