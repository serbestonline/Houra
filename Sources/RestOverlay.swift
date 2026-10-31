import AppKit
import ImageIO
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
    @State private var stretching = false

    var body: some View {
        ZStack {
            DriftingLights()
            if showsContent {
                // Esneme açılınca hareket solda belirir, zamanlayıcı sağa kayar.
                HStack(spacing: 0) {
                    if stretching {
                        StretchGuide().frame(maxWidth: .infinity)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    timer.frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 60)
                .animation(.spring(response: 0.8, dampingFraction: 0.86), value: stretching)
                VStack { Spacer(); emergency.padding(.bottom, 48) }
            }
        }
        .ignoresSafeArea()
        .onAppear { shown = true }
        .onReceive(NotificationCenter.default.publisher(for: .stretchCommand)) { n in if n.userInfo?["toggle"] != nil { stretching.toggle() } }
    }

    private var timer: some View {
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
            Button { stretching.toggle() } label: {
                Label(stretching ? T("Hareketleri kapat", "Hide stretches") : T("Esneme hareketleri", "Stretches"), systemImage: "figure.arms.open")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Color.white.opacity(stretching ? 0.14 : 0.06)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(stretching ? 0.4 : 0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 30).reveal(shown, 0.5)
        }
        .foregroundStyle(Ink.text)
        .fixedSize()   // yarım ekranda başlık kırılmasın; küçültme scaleEffect ile
        .scaleEffect(stretching ? 0.74 : 1)
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

// MARK: - Esneme hareketleri

/// Çöp adamın duruşu. Açılar radyan; kol ve bacakta 0 aşağı sarkmak, artı değer gövdeden dışarı açılmak demek.
/// Gövde açısı artıyken sağa eğilir, baş açısı artıyken baş sağa yatar.
struct Pose {
    var torso = 0.0, head = 0.0, shrug = 0.0
    var armL = 0.12, elbowL = 0.0, armR = 0.12, elbowR = 0.0
    var legL = 0.12, kneeL = 0.0, legR = 0.12, kneeR = 0.0
}

struct Stretch {
    let name: String
    let hint: String
    var sets = 2
    var dose = T("10 tekrar", "10 reps")             // bir setin ölçüsü: tekrar ya da tutma süresi
    var clip: StretchClip? = nil
    var pose: (Double) -> Pose = { _ in Pose() }   // hareketin başından beri geçen saniye

    /// 0 ile 1 arasında yumuşakça gidip gelen değer.
    private static func swing(_ t: Double, _ period: Double) -> Double { (1 - cos(t * 2 * .pi / period)) / 2 }

    /// Mola ekranında seçilen kategori ve hareketleri. Yerelde GIF yoksa tek grup: çizgi figür.
    static let groups: [(name: String, moves: [Stretch])] = {
        let withClips = clipGroups.map { (name: $0.name, moves: $0.moves.filter { $0.clip != nil }) }.filter { !$0.moves.isEmpty }
        return withClips.isEmpty ? [(name: T("Genel", "General"), moves: figures)] : withClips
    }()

    /// Hareketlerin animasyonları Studio/esneme.py ile Blender'da üretildi (360 px) ve uygulamanın içinde, Stretches klasöründe gelir.
    /// Bel grubu uzun oturmaktan gelen bel ağrısı için; her hareket ayrı bir iş görür, birbirini tekrar edenler çıkarıldı.
    private static let clipGroups: [(name: String, moves: [Stretch])] = {
        func m(_ id: String, _ name: String, _ hint: String, _ dose: String, sets: Int = 2) -> Stretch {
            Stretch(name: name, hint: hint, sets: sets, dose: dose, clip: .load(id))
        }
        func again(_ s: Stretch, _ hint: String, _ dose: String? = nil) -> Stretch {
            Stretch(name: s.name, hint: hint, sets: s.sets, dose: dose ?? s.dose, clip: s.clip)
        }
        let reps = { (n: Int) in T("\(n) tekrar", "\(n) reps") }
        let hold = { (n: Int) in T("\(n) sn tut", "hold \(n) s") }
        let eachSide = { (n: Int) in T("her yanda \(n) sn tut", "hold \(n) s each side") }

        let deadBug = m("deadbug", T("Dead bug", "Dead bug"), T("Sırtüstü, belin yerde kalsın; karşı kol ve bacağı yavaşça uzatıp geri getir. Son sette iki bacağın havada, dizler bükük 20 sn dur.", "On your back, lower back down; slowly extend the opposite arm and leg, then return. On the last set hold both legs up, knees bent, for 20 s."), T("her yana 8 tekrar", "8 reps each side"))
        let kneeHug = m("kneehug", T("Dizleri göğse çek", "Knees to chest"), T("Sırtüstü, iki dizini kollarınla göğsüne doğru çek, belini yere bırak.", "On your back, hug both knees toward your chest and let your lower back sink into the floor."), hold(30))
        let twist = m("twist", T("Bacakları yana devir", "Lying knee twist"), T("Sırtüstü, dizler bükük ve havada; bacaklarını yavaşça bir yana indir, omuzların yerde kalsın, sonra öbür yana.", "On your back, knees bent and up; lower them slowly to one side with shoulders down, then the other."), T("her yana 8 tekrar", "8 reps each side"))
        let tiltBridge = m("bridge", T("Pelvik tiltten köprüye", "Pelvic tilt into bridge"), T("Önce belini yere bastır, sonra kalçanı omurga omurga kaldır ve aynı yoldan indir.", "Press your lower back down first, then peel your hips up one vertebra at a time and roll back down."), reps(10))
        let curlUp = m("curlup", T("Curl-up", "Curl-up"), T("Bir dizin bükük, ellerin belinin altında; başını ve omuzlarını birkaç santim kaldır, belini bükme.", "One knee bent, hands under your lower back; lift head and shoulders a few centimetres without bending your lower back."), T("6 tekrar, her biri 8 sn", "6 reps, 8 s each"))
        let sidePlank = m("sideplank", T("Yan köprü", "Side plank"), T("Yan yat, dirseğin omzunun altında; kalçanı kaldırıp vücudunu düz tut, sonra diğer yan.", "Lie on your side, elbow under shoulder; lift your hips and hold a straight line, then the other side."), eachSide(20))
        let quad = m("quad", T("Kalça önünü esnet", "Hip flexor and quad"), T("Yan yat, üstteki ayağını arkadan tutup topuğunu kalçana çek; dizin geride kalsın. Oturmaktan kısalan kalça önünü açar.", "Lie on your side, hold your top foot behind you and draw the heel to your glute, knee back. Opens the front of the hip that sitting shortens."), eachSide(30))
        let proneLift = m("prone", T("Yüzüstü gövde kaldırma", "Prone back lift"), T("Yüzüstü, kollar yanda; göğsünü yerden birkaç santim kaldır, boynunu düz tut.", "Face down, arms at your sides; lift your chest a few centimetres, neck long."), reps(10))
        let upDog = m("updog", T("Yukarı bakan köpek", "Upward dog"), T("Yüzüstü, eller kaburgaların yanında; kollarını yavaşça açarak göğsünü kaldır, kalçan yerde kalsın. Zor gelirse dirseklerini yerde bırak.", "Face down, hands by your ribs; straighten your arms slowly to lift your chest, hips stay down. If it's too much, stay on your elbows."), T("8 tekrar, her biri 2 sn", "8 reps, 2 s each"))
        let chairGlute = m("chairglute", T("Sandalyede kalça esnet", "Seated glute stretch"), T("Sandalyede bir ayak bileğini öbür dizinin üstüne koy, sırtın düz öne eğil.", "On a chair, cross one ankle over the other knee and lean forward with a straight back."), eachSide(30))
        let pelvicStand = m("pelvicstand", T("Ayakta pelvik tilt", "Standing pelvic tilt"), T("Dizler hafif bükük, karnını içeri çek ve leğenini yavaşça öne arkaya devir.", "Knees soft, draw your belly in and slowly rock your pelvis forward and back."), reps(10))

        let neck = m("neck", T("Boynunu esnet", "Neck stretch"), T("Başını yana yatır, eliyle hafifçe bastır; omzun aşağıda kalsın. Sonra diğer yana.", "Tilt your head to the side and press lightly with your hand, shoulder down. Then the other side."), eachSide(20))
        let neckForward = m("neckforward", T("Boynunu öne esnet", "Neck stretch forward"), T("Ellerini başının arkasında kenetle, başını yavaşça öne ve yana indir.", "Clasp your hands behind your head and ease it slowly forward and to the side."), eachSide(20))
        let sideBend = m("sidebend", T("Yana esne", "Side bend"), T("Bir kolunu başının üstünden aşır, gövdeni yavaşça yana eğ.", "Take one arm over your head and bend slowly to the side."), eachSide(20))
        let triceps = m("triceps", T("Arka kolu esnet", "Overhead triceps"), T("Elini sırtına indir, diğer elinle dirseği hafifçe aşağı çek.", "Drop your hand down your back and ease the elbow down with the other hand."), T("her kolda 20 sn tut", "hold 20 s each arm"))
        let crossBody = m("crossbody", T("Omzu çapraz çek", "Cross-body shoulder"), T("Kolunu göğsünün önünden geçir, diğer kolunla kendine doğru çek.", "Bring your arm across your chest and pull it in with the other arm."), T("her kolda 20 sn tut", "hold 20 s each arm"))
        let upperArm = m("upperarm", T("Üst kolu çek", "Upper arm stretch"), T("Kolunu omuz hizasında karşıya uzat, diğer elinle dirseğinden kendine çek.", "Reach your arm across at shoulder height and pull it in at the elbow with the other hand."), T("her kolda 20 sn tut", "hold 20 s each arm"))
        let wristPull = m("wristpull", T("Bileği yana çek", "Side wrist pull"), T("Bir elinle diğer bileğini tut, kolunu göğsünün önünden yana doğru çek.", "Hold one wrist with the other hand and pull the arm across in front of your chest."), T("her kolda 20 sn tut", "hold 20 s each arm"))
        let chest = m("chest", T("Göğsünü aç", "Open the chest"), T("Kollarını önde birleştir, sonra yana açıp göğsünü genişlet.", "Bring your arms together in front, then swing them open and widen the chest."), reps(10))
        let upperBack = m("upperback", T("Sırtını yuvarla", "Round the upper back"), T("Ellerini önde kenetle, öne uzanırken sırtını yuvarla.", "Clasp your hands in front and round your upper back as you reach forward."), hold(20))
        let wrists = m("wrists", T("Bileklerini çevir", "Wrist circles"), T("Klavyeden kalkan bileklerini iki yöne de yavaşça çevir.", "Slowly circle your keyboard-tired wrists both ways."), T("her yöne 10 tur", "10 circles each way"))
        let squatReach = m("squatreach", T("Çömel ve uzan", "Squat to reach"), T("Çömel, kalkarken kollarını başının üstüne uzat.", "Squat down, then reach your arms overhead as you stand."), reps(8))
        let scapPush = m("scappush", T("Masada kürek itişi", "Desk scapula push"), T("Ellerini masaya koy, kolların düz kalsın; göğsünü kollarının arasına indir, sonra kürek kemiklerini açarak it.", "Hands on the desk, arms straight; let your chest sink between them, then push your shoulder blades apart."), reps(10))

        return [
            (T("Genel", "General"), [neck, sideBend, chest, upperBack, crossBody, pelvicStand, wrists, squatReach, triceps]),
            (T("Bel", "Lower back"), [deadBug, kneeHug, twist, tiltBridge, curlUp, sidePlank, quad, proneLift, upDog, chairGlute, pelvicStand]),
            (T("Boyun ve sırt", "Neck and back"), [neck, neckForward, upperBack, chest, sideBend]),
            (T("Kol ve bilek", "Arms and wrists"), [triceps, crossBody, upperArm, wristPull, wrists]),
            // Serbest'in sol omzu: masa başı duruşundan, arkada ve boyundan omza yayılan ağrı; baş üstü hareketler yok.
            (T("Sol omuz", "Left shoulder"), [
                again(neck, T("Başını sağa yatır, sağ elinle hafifçe bastır; sol omzun aşağıda kalsın.", "Tilt your head right and press lightly with your right hand; keep your left shoulder down."), hold(30)),
                again(neckForward, T("Başını sağ koltuk altına bakar gibi öne ve sağa indir; sol omzun aşağıda kalsın.", "Lower your head forward and right as if looking at your right armpit; keep your left shoulder down."), hold(30)),
                again(scapPush, T("Ellerini masaya koy; göğsünü indir, sonra kürek kemiklerini açarak it. Sol tarafın da aynı ölçüde çalışsın.", "Hands on the desk; let your chest sink, then push your shoulder blades apart. Let the left side work as much as the right.")),
                again(chest, T("Kollarını yana açıp göğsünü genişlet; omuzlarını kulaklarından uzak tut.", "Open your arms wide and broaden your chest; keep your shoulders away from your ears.")),
                again(upperBack, T("Ellerini önde kenetle, kürek kemiklerinin arasını açarak öne uzan.", "Clasp your hands in front and reach forward, spreading your shoulder blades.")),
                again(crossBody, T("Sol kolunu göğsünün önünden geçir, sağ kolunla nazikçe çek. Batan bir ağrı olursa bırak.", "Bring your left arm across your chest and ease it in with the right. Stop if you feel a sharp pain."), hold(30)),
            ]),
        ].map { (name: $0.0, moves: $0.1) }
    }()

    private static let figures: [Stretch] = [
        Stretch(name: T("Yukarı uzan", "Reach up"),
                hint: T("Kollarını başının üstüne kaldır, parmak uçlarına doğru uzan.", "Raise your arms overhead and reach through your fingertips.")) { t in
            let p = swing(t, 5)
            return Pose(armL: 0.12 + p * 2.8, armR: 0.12 + p * 2.8)
        },
        Stretch(name: T("Yana esne", "Side bend"),
                hint: T("Kollar yukarıda, gövdeni yavaşça bir yana, sonra öbür yana eğ.", "Arms overhead, bend slowly to one side, then the other.")) { t in
            Pose(torso: 0.32 * sin(t * 2 * .pi / 7), armL: 3.0, armR: 3.0)
        },
        Stretch(name: T("Boynunu esnet", "Neck stretch"),
                hint: T("Kulağını omzuna yaklaştır, omzunu aşağıda tut; sonra diğer yana.", "Bring your ear toward your shoulder, keep the shoulder down; then the other side.")) { t in
            Pose(head: 0.6 * sin(t * 2 * .pi / 8))
        },
        Stretch(name: T("Omuz silk", "Shoulder shrugs"),
                hint: T("Omuzlarını kulaklarına doğru kaldır, bir an tut, bırak.", "Lift your shoulders toward your ears, hold a moment, let go.")) { t in
            let p = swing(t, 2.6)
            return Pose(shrug: 0.24 * p, armL: 0.12 - p * 0.04, armR: 0.12 - p * 0.04)
        },
        Stretch(name: T("Göğsünü aç", "Open the chest"),
                hint: T("Dirseklerini omuz hizasına kaldır, kürek kemiklerini birbirine yaklaştır.", "Lift your elbows to shoulder height and squeeze your shoulder blades together.")) { t in
            let p = swing(t, 4.5)
            return Pose(armL: 0.35 + p * 1.22, elbowL: p * 1.57, armR: 0.35 + p * 1.22, elbowR: p * 1.57)
        },
        Stretch(name: T("Derin nefes", "Deep breath"),
                hint: T("Kollarını yanlardan yukarı açarken nefes al, indirirken yavaşça ver.", "Breathe in as your arms rise out to the sides, breathe out slowly as they come down.")) { t in
            let p = swing(t, 8)
            return Pose(shrug: 0.03 * p, armL: 0.12 + p * 1.9, armR: 0.12 + p * 1.9)
        },
        Stretch(name: T("Çömel ve kalk", "Squat"),
                hint: T("Ayakların omuz genişliğinde; kalçanı geriye itip yavaşça çömel, sonra kalk.", "Feet shoulder-width apart; push your hips back, lower slowly, then stand.")) { t in
            let p = swing(t, 4.5), thigh = 0.12 + p * 0.73
            let shin = asin(2 * sin(0.12) - sin(thigh))   // ayaklar yerinden kaymasın
            return Pose(armL: 0.12 + p * 1.35, armR: 0.12 + p * 1.35,
                        legL: thigh, kneeL: shin - thigh, legR: thigh, kneeR: shin - thigh)
        },
    ]
}

/// GIF kareleri ve her karenin süresi; SwiftUI zaman çizelgesiyle oynatılır.
struct StretchClip {
    let frames: [CGImage]
    let delays: [Double]

    static func load(_ name: String) -> StretchClip? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif", subdirectory: "Stretches"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var frames: [CGImage] = [], delays: [Double] = []
        for i in 0..<CGImageSourceGetCount(src) {
            guard let img = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let gif = (CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let d = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            frames.append(img); delays.append(max(0.02, d))
        }
        return frames.isEmpty ? nil : StretchClip(frames: frames, delays: delays)
    }

    func frame(at t: Double) -> CGImage {
        var rest = t.truncatingRemainder(dividingBy: delays.reduce(0, +))
        for (img, d) in zip(frames, delays) { if rest < d { return img }; rest -= d }
        return frames[frames.count - 1]
    }
}

/// Moladan bağımsız esneme penceresi: panelin kenar çubuğundan ve menü çubuğundan açılır.
final class StretchWindow {
    static let shared = StretchWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 820),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = .black
            w.center()
            window = w
        }
        // Her açılışta Genel'in ilk hareketinden başlasın.
        window?.contentView = NSHostingView(rootView: StretchScreen())
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct StretchScreen: View {
    var body: some View {
        StretchGuide()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DriftingLights())
            .environment(\.colorScheme, .dark)
    }
}

/// Mola ekranının sol yarısı ve esneme penceresi. Sayaç ve set takibi yok: her hareketin önerilen set ve
/// tekrar sayısı yazar, oklarla hareketler arasında geçilir.
struct StretchGuide: View {
    @State private var group = 0
    @State private var index = 0
    @State private var since = Date()    // animasyon hareketin başından oynasın

    var body: some View {
        TimelineView(.animation) { tl in
            let moves = Stretch.groups[group].moves
            let count = moves.count
            let i = index % count
            let move = moves[i]
            let t = max(0, tl.date.timeIntervalSince(since))
            VStack(spacing: 0) {
                if Stretch.groups.count > 1 {
                    Segmented(options: Stretch.groups.map(\.name), selection: group) { group = $0; go(0) }
                        .padding(.bottom, 26)
                }
                if let clip = move.clip {
                    Image(decorative: clip.frame(at: t), scale: 1).resizable().interpolation(.high)
                        .frame(width: 310, height: 310)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                } else {
                    StickFigure(pose: move.pose(t)).frame(width: 320, height: 400)
                }
                Eyebrow("\(i + 1) / \(count)").padding(.top, 28)
                Text(move.name).font(.system(size: 38, weight: .light)).tracking(-0.5).padding(.top, 12)
                Text(T("Önerilen: \(move.sets) set × \(move.dose)", "Suggested: \(move.sets) sets × \(move.dose)"))
                    .font(.system(size: 15, weight: .medium)).monospacedDigit().padding(.top, 8)
                Text(move.hint).font(.system(size: 16)).foregroundStyle(Ink.muted)
                    .multilineTextAlignment(.center).frame(width: 380).padding(.top, 10)
                HStack(spacing: 18) {
                    step("chevron.left") { go((i + count - 1) % count) }
                    step("chevron.right") { go((i + 1) % count) }
                }
                .padding(.top, 26)
            }
            .foregroundStyle(Ink.text)
        }
        .onReceive(NotificationCenter.default.publisher(for: .stretchCommand)) { n in
            if n.userInfo?["next"] != nil { go(index + 1) }
            if let g = n.userInfo?["group"] as? Int { group = g; go(0) }
        }
    }

    private func go(_ n: Int) { index = n; since = Date() }

    private func step(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.06))).overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(Ink.muted)
    }
}

/// İnce beyaz çizgili çöp adam. Birimler: kalça (0, 0), yukarısı artı; ayaklar her zaman yere basar.
struct StickFigure: View {
    let pose: Pose

    var body: some View {
        Canvas { ctx, size in
            let p = pose
            func limb(_ from: CGPoint, _ angle: Double, _ side: Double, _ length: Double) -> CGPoint {
                CGPoint(x: from.x + side * sin(angle) * length, y: from.y - cos(angle) * length)
            }
            func lean(_ q: CGPoint) -> CGPoint {   // üst gövde kalçanın çevresinde döner
                let c = CGFloat(cos(p.torso)), s = CGFloat(sin(p.torso))
                return CGPoint(x: q.x * c + q.y * s, y: -q.x * s + q.y * c)
            }
            let neck = CGPoint(x: 0, y: 1.0)
            let head = CGPoint(x: 0.36 * sin(p.head), y: 1.0 + 0.36 * cos(p.head))
            let sL = CGPoint(x: -0.34, y: 0.9 + p.shrug), sR = CGPoint(x: 0.34, y: 0.9 + p.shrug)
            let eL = limb(sL, p.armL, -1, 0.6), eR = limb(sR, p.armR, 1, 0.6)
            let wL = limb(eL, p.armL + p.elbowL, -1, 0.55), wR = limb(eR, p.armR + p.elbowR, 1, 0.55)
            let hL = CGPoint.zero, hR = CGPoint.zero
            let kL = limb(hL, p.legL, -1, 0.85), kR = limb(hR, p.legR, 1, 0.85)
            let fL = limb(kL, p.legL + p.kneeL, -1, 0.85), fR = limb(kR, p.legR + p.kneeR, 1, 0.85)

            let scale = size.height / 4.0, ground = min(fL.y, fR.y)
            func at(_ q: CGPoint) -> CGPoint { CGPoint(x: size.width / 2 + q.x * scale, y: size.height - 0.1 * scale - (q.y - ground) * scale) }
            func up(_ q: CGPoint) -> CGPoint { at(lean(q)) }

            var figure = Path()
            figure.move(to: at(.zero)); figure.addLine(to: up(neck))
            figure.move(to: up(sL)); figure.addLine(to: up(sR))
            figure.move(to: up(wL)); figure.addLine(to: up(eL)); figure.addLine(to: up(sL))
            figure.move(to: up(wR)); figure.addLine(to: up(eR)); figure.addLine(to: up(sR))
            figure.move(to: at(fL)); figure.addLine(to: at(kL)); figure.addLine(to: at(hL))
            figure.move(to: at(fR)); figure.addLine(to: at(kR)); figure.addLine(to: at(hR))
            figure.move(to: up(neck)); figure.addLine(to: up(CGPoint(x: 0.2 * sin(p.head), y: 1.0 + 0.2 * cos(p.head))))
            let r = 0.22 * scale, c = up(head)
            figure.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

            var floor = Path()
            floor.move(to: at(CGPoint(x: -0.9, y: ground))); floor.addLine(to: at(CGPoint(x: 0.9, y: ground)))
            ctx.stroke(floor, with: .color(.white.opacity(0.14)), lineWidth: 1)
            ctx.stroke(figure, with: .color(.white.opacity(0.07)), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
            ctx.stroke(figure, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
        }
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
