import AppKit

// Oturum motoru: odak, duraklatma, mola. Bütün görünümler bu tek kaynağı izler.

final class Focus: ObservableObject {
    static let shared = Focus()

    enum Phase: Equatable { case idle, focus, paused, rest }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var session: Session?
    @Published private(set) var topic: Topic?
    @Published private(set) var todos: [Todo] = []
    @Published var note = "" { didSet { if let id = session?.id { Store.shared.setNote(session: id, note) } } }
    @Published private(set) var now = Date()

    /// Mola başlayınca ve bitince ekranı yöneten taraf (AppDelegate) bunlara bağlanır.
    var onRestStart: () -> Void = {}
    var onRestEnd: (_ early: Bool) -> Void = { _ in }
    /// Serbest oturumda her 50 dakikada bir: mola hatırlatması (molayı vermek isteğe bağlı).
    var onBreakNudge: () -> Void = {}

    /// Serbest oturum: sayaç ileri akar, süre dolmaz; her bu kadar saniyede bir mola hatırlatılır.
    static let freeNudgeSeconds = 50 * 60

    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0
    private(set) var restEnd: Date?
    private var timer: Timer?
    private var nudges = 0

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
        RunLoop.main.add(timer!, forMode: .common)   // mola uyarısı açıkken de sayaç aksın
        closeAbandoned()
    }

    // MARK: Okuma

    /// Ritmi 0 dakika olan oturum serbesttir.
    var isFree: Bool { session?.workMinutes == 0 }
    var workSeconds: Int { isFree ? Focus.freeNudgeSeconds : (session?.workMinutes ?? 50) * 60 }
    var restSeconds: Int { (session?.restMinutes ?? 10) * 60 }

    var elapsed: TimeInterval {
        guard let s = session else { return 0 }
        return max(0, (pausedAt ?? now).timeIntervalSince(s.start) - pausedTotal)
    }
    var remaining: Int { max(0, workSeconds - Int(elapsed)) }
    /// Ekranda yazan süre: serbestte geçen, değilse kalan.
    var clock: Int { isFree ? Int(elapsed) : remaining }
    var progress: Double { min(1, elapsed / Double(workSeconds)) }
    var restRemaining: Int { max(0, Int((restEnd ?? now).timeIntervalSince(now).rounded(.up))) }
    var plannedEnd: Date? { isFree ? nil : session.map { $0.start.addingTimeInterval(Double(workSeconds) + pausedTotal) } }
    var activeTodo: Todo? { todos.first { $0.state == .doing } }

    /// Küçük görünümlerde yazan: o an yapılan görev, yoksa oturumun hedefi.
    var headline: String { activeTodo?.title ?? session?.goal ?? "" }

    // MARK: Yazma

    func start(topic: Topic, goal: String, todoIDs: [Int64], newTodos: [(String, String)], work: Int, rest: Int) {
        if phase != .idle { stop() }
        let id = Store.shared.startSession(category: topic.id, goal: goal.isEmpty ? topic.name : goal, work: work, rest: rest)
        var ids = todoIDs
        for (title, detail) in newTodos { ids.append(Store.shared.addTodo(day: dayKey(Date()), title: title, detail: detail)) }
        for (i, todo) in ids.enumerated() {
            Store.shared.attachTodo(id: todo, session: id)
            Store.shared.setTodoState(id: todo, i == 0 ? .doing : .waiting)
        }
        self.topic = topic
        session = Store.shared.sessions(from: Date().addingTimeInterval(-5), to: .distantFuture).last { $0.id == id }
        pausedAt = nil; pausedTotal = 0; restEnd = nil; nudges = 0
        note = ""
        reloadTodos()
        phase = .focus
        now = Date()
    }

    func pause() {
        guard phase == .focus else { return }
        pausedAt = Date(); phase = .paused
    }

    func resume() {
        guard phase == .paused, let p = pausedAt else { return }
        pausedTotal += Date().timeIntervalSince(p); pausedAt = nil; phase = .focus
    }

    private var focusSeconds: Int { isFree ? Int(elapsed) : min(workSeconds, Int(elapsed)) }

    /// Oturumu bitirir ve molaya geçer (süre dolunca ya da Bitir'e basınca).
    func finish() {
        guard let s = session, phase == .focus || phase == .paused else { return }
        if phase == .paused { resume() }
        Store.shared.finishSession(id: s.id, end: Date(), focusSeconds: focusSeconds)
        restEnd = Date().addingTimeInterval(Double(restSeconds))
        phase = .rest
        onRestStart()
    }

    /// Molayı bitirir. `emergency` acil durumla erken dönüldüğünü kaydeder.
    func endRest(emergency: Bool) {
        guard phase == .rest else { return }
        if emergency, let s = session { Store.shared.markEmergency(session: s.id) }
        phase = .idle; session = nil; topic = nil; todos = []; restEnd = nil
        onRestEnd(emergency)
    }

    /// Acil durum: mola sürer ama ekran bırakılır; kayda işlenir, menüden molaya dönülebilir.
    func emergencyExit() {
        guard phase == .rest else { return }
        if let s = session { Store.shared.markEmergency(session: s.id) }
        RestOverlay.shared.hide()
    }

    /// Molasız tamamen durdurur (yeni oturum eskisinin üstüne başlarken).
    func stop() {
        if let s = session, phase == .focus || phase == .paused {
            Store.shared.finishSession(id: s.id, end: Date(), focusSeconds: focusSeconds)
        }
        phase = .idle; session = nil; topic = nil; todos = []; restEnd = nil
    }

    /// Geliştirici kancası: kayıtta oturum biraz önce başlamış gibi görünsün.
    func debugShift(by seconds: TimeInterval) { session?.start.addTimeInterval(seconds); now = Date() }

    /// 🤓 → 🙂‍↔️ → 🥳 → 🤓. Aynı anda tek görev "yapılıyor" olabilir.
    func cycle(_ todo: Todo) { set(todo, todo.state.next) }

    func set(_ todo: Todo, _ state: TodoState) {
        if state == .doing { todos.filter { $0.state == .doing && $0.id != todo.id }.forEach { Store.shared.setTodoState(id: $0.id, .waiting) } }
        Store.shared.setTodoState(id: todo.id, state)
        reloadTodos()
    }

    private func reloadTodos() {
        todos = session.map { Store.shared.todos(session: $0.id) } ?? []
    }

    private func tick() {
        now = Date()
        if phase == .focus && !isFree && remaining == 0 { finish() }
        if phase == .focus && isFree, let s = session {
            let mark = Int(elapsed) / Focus.freeNudgeSeconds
            if mark > nudges { nudges = mark; onBreakNudge() }
            // Uygulama kapanırsa geçen süre kaybolmasın diye dakikada bir kaydedilir.
            if Int(elapsed) % 60 == 0 { Store.shared.setFocus(session: s.id, seconds: Int(elapsed)) }
        }
        if phase == .rest && restRemaining == 0 { endRest(emergency: false) }
    }

    /// Uygulama oturum sürerken kapandıysa: yarım kalan oturum planlanan süreyle kapatılır.
    private func closeAbandoned() {
        let store = Store.shared
        for s in store.sessions(from: Date().addingTimeInterval(-3 * 86400), to: .distantFuture) where s.end == nil {
            let planned = s.workMinutes == 0 ? s.focusSeconds : s.workMinutes * 60   // serbest: son kaydedilen süre
            let end = min(Date(), s.start.addingTimeInterval(Double(planned)))
            store.finishSession(id: s.id, end: end, focusSeconds: Int(end.timeIntervalSince(s.start)))
        }
    }
}
