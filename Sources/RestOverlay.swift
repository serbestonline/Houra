import AppKit
import SwiftUI

// Mola ekranı: bütün ekranları kaplayan, siyah-beyaz ışıkların aktığı sahne. Yalnız 1,5 sn basılı tutulan
// "Acil durum" ile erken dönülür; süre bitince kendiliğinden kapanır ve yeni oturum sorulur.

final class RestOverlay {
    static let shared = RestOverlay()
    private var windows: [NSWindow] = []
    private var previousOptions: NSApplication.PresentationOptions = []

    func show() {
        guard windows.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        let active = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens[0]
        for screen in NSScreen.screens {
            let w = KeyWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.setFrame(screen.frame, display: false)
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.alphaValue = 0
            w.contentView = NSHostingView(rootView: RestView(showsContent: screen == active))
            w.orderFrontRegardless()
            if screen == active { w.makeKey() }
            windows.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        previousOptions = NSApp.presentationOptions
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.9; windows.forEach { $0.animator().alphaValue = 1 } }
    }

    /// Acil durum: mola sürüyor ama ekran bırakılır; menüden geri dönülebilir.
    func hide() {
        let closing = windows
        windows = []
        guard !closing.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.6; closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [previousOptions] in
            closing.forEach { $0.orderOut(nil) }
            NSApp.presentationOptions = previousOptions
        })
    }
}

final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private struct RestView: View {
    let showsContent: Bool
    @ObservedObject private var focus = Focus.shared
    @State private var shown = false
    @State private var holding = false
    @State private var holdStart: Date?

    var body: some View {
        ZStack {
            DriftingLights()
            if showsContent {
                VStack(spacing: 0) {
                    Eyebrow(T("Mola", "Break")).reveal(shown, 0.1)
                    Text(T("Kalk, biraz uzaklaş.", "Stand up, step away."))
                        .font(.system(size: 92, weight: .ultraLight)).tracking(-2)
                        .padding(.top, 20).reveal(shown, 0.2)
                    Text(T("Su iç, pencereden dışarı bak, birkaç adım at. Ekran seni bekler.",
                           "Drink some water, look out the window, take a few steps. The screen will wait."))
                        .font(.system(size: 19)).foregroundStyle(Ink.muted)
                        .padding(.top, 16).reveal(shown, 0.3)
                    Text(formatClock(focus.restRemaining))
                        .font(.system(size: 128, weight: .thin)).monospacedDigit().tracking(-4)
                        .padding(.top, 46).reveal(shown, 0.4)
                }
                .foregroundStyle(Ink.text)
                VStack { Spacer(); emergency.padding(.bottom, 48) }
            }
        }
        .ignoresSafeArea()
        .onAppear { shown = true }
    }

    /// 1,5 saniye basılı tutulunca ekran bırakılır.
    private var emergency: some View {
        Text(T("Acil durum", "Emergency"))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(holding ? 0.9 : 0.45))
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(alignment: .leading) {
                GeometryReader { g in
                    Rectangle().fill(Color.white.opacity(0.22))
                        .frame(width: holding ? g.size.width : 0)
                        .animation(holding ? .linear(duration: 1.5) : .easeOut(duration: 0.2), value: holding)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(holding ? 0.4 : 0.14)))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !holding else { return }
                    holding = true; holdStart = Date()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if holding, let s = holdStart, Date().timeIntervalSince(s) >= 1.45 {
                            holding = false
                            Focus.shared.emergencyExit()
                        }
                    }
                }
                .onEnded { _ in holding = false; holdStart = nil })
    }
}

private extension View {
    func reveal(_ shown: Bool, _ delay: Double) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : 26).blur(radius: shown ? 0 : 8)
            .animation(.spring(response: 1.1, dampingFraction: 0.85).delay(delay), value: shown)
    }
}

/// Siyah zeminde yavaşça akan üç gri-beyaz ışık.
struct DriftingLights: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height, span = max(w, h)
                ctx.blendMode = .screen
                let lights: [(Double, Double, Double, Double, Double)] = [   // açıklık, saydamlık, yarıçap, hız, faz
                    (1.0, 0.16, 0.42, 0.071, 0.0), (0.6, 0.22, 0.52, 0.055, 2.1), (0.85, 0.12, 0.34, 0.09, 4.0),
                ]
                for (v, a, r0, sp, ph) in lights {
                    let x = w * (0.5 + 0.42 * sin(t * sp * 2 * .pi + ph)), y = h * (0.5 + 0.38 * cos(t * sp * 1.7 * .pi + ph * 1.3))
                    let r = span * r0 * (1 + 0.15 * sin(t * sp * 3 + ph))
                    let c = Color(white: v)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .radialGradient(Gradient(colors: [c.opacity(a), c.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
                }
                ctx.blendMode = .normal
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.7)]), center: CGPoint(x: w / 2, y: h * 0.45), startRadius: span * 0.25, endRadius: span * 0.8))
            }
        }
        .background(Color.black)
    }
}
