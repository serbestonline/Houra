import AppKit
import SwiftUI

// Yeni oturum penceresi: kategori, hedef, bugünün listesinden görevler, yeni görev, ritim (25 + 5 ya da 50 + 10).

final class NewSessionController {
    static let shared = NewSessionController()
    /// Geliştirici kancası: kayıt betiği hedefi önceden doldurur.
    static var prefillGoal = ""
    private var window: NSWindow?

    /// Bugün sayfasında tıklanan haftalık görev: pencere onu seçili ve kategorisi ayarlı açılır.
    static var preselect: WeeklyTask?

    func show(preselect: WeeklyTask? = nil) {
        Self.preselect = preselect
        if Focus.shared.phase == .rest { Focus.shared.endRest(emergency: false); return }   // endRest yeniden çağırır
        window?.close()
        let w = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: NewSessionView(close: { [weak self] in self?.close() }))
        w.contentView = host
        w.setContentSize(host.fittingSize)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame { w.setFrameOrigin(NSPoint(x: f.midX - w.frame.width / 2, y: f.midY - w.frame.height / 2 + 40)) }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}

private struct NewSessionView: View {
    let close: () -> Void

    @State private var topics = Store.shared.categories()
    @State private var topicID: Int64? = NewSessionController.preselect?.topicID ?? UserDefaults.standard.object(forKey: "lastTopic") as? Int64
    @State private var goal = NewSessionController.prefillGoal
    @State private var waiting = Store.shared.todos(day: dayKey(Date())).filter { $0.state != .done && $0.sessionID == nil }
    @State private var picked: [Int64] = []
    @State private var weekly = WeeklyList.load(topics: Store.shared.categories())
    @State private var pickedWeekly: [Int] = NewSessionController.preselect.map { [$0.id] } ?? []
    @State private var source = NewSessionController.preselect == nil ? 0 : 1     // 0 bugünün listesi, 1 haftanın listesi
    @State private var extra: [(String, String)] = []
    @State private var newTitle = ""
    @State private var newDetail = ""
    /// 25, 50 ya da 0 (serbest: ileri sayar, 50. dakikada mola hatırlatır).
    @State private var work = UserDefaults.standard.object(forKey: "rhythmWork") as? Int
        ?? (UserDefaults.standard.object(forKey: "longRhythm") as? Bool ?? true ? 50 : 25)

    private var topic: Topic? { topics.first { $0.id == topicID } ?? topics.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(T("Yeni oturum", "New session"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(topics) { t in
                        Button { topicID = t.id } label: {
                            HStack(spacing: 7) { CategorySwatch(category: t, size: 18); Text(t.name) }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(t.id == topic?.id ? Ink.text : Ink.muted)
                                .padding(.leading, 6).padding(.trailing, 11).padding(.vertical, 5)
                                .background(Capsule().fill(Color.white.opacity(t.id == topic?.id ? 0.09 : 0.03)))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(t.id == topic?.id ? 0.5 : 0.09)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 12)

            UnderlineField(placeholder: T("Neye odaklanıyorsun?", "What are you focusing on?"), text: $goal, size: 26, autofocus: true, onSubmit: begin)
                .padding(.top, 18)

            if !waiting.isEmpty || !extra.isEmpty || !weekly.isEmpty {
                HStack {
                    if weekly.isEmpty {
                        Eyebrow(T("Bugünün listesinden seç", "Pick from today's list"))
                    } else {
                        Segmented(options: [T("Bugünün listesi", "Today's list"), T("Haftanın listesi", "This week's list")], selection: source) { source = $0 }
                    }
                    Spacer()
                    let n = picked.count + pickedWeekly.count + extra.count
                    if n > 0 { Text(T("\(n) görev seçildi", "\(n) tasks selected")).font(.system(size: 12)).foregroundStyle(Ink.muted) }
                }
                .padding(.top, 22)
                ScrollView {
                    VStack(spacing: 2) {
                        if source == 0 {
                            if waiting.isEmpty && extra.isEmpty {
                                Text(T("Bugünün listesinde bekleyen görev yok.", "Nothing waiting on today's list.")).font(.system(size: 12.5)).foregroundStyle(Ink.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            }
                            ForEach(waiting) { todo in
                                PickRow(title: todo.title, detail: todo.detail, selected: picked.contains(todo.id)) {
                                    if let i = picked.firstIndex(of: todo.id) { picked.remove(at: i) } else { picked.append(todo.id) }
                                }
                            }
                        } else {
                            let list = weeklySorted
                            ForEach(Array(list.enumerated()), id: \.element.id) { i, task in
                                if WeeklyTask.startsSubgroup(list, at: i) {
                                    Text(task.detail).font(.system(size: 12)).foregroundStyle(Ink.faint).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 42).padding(.top, 6)
                                }
                                PickRow(title: task.title, detail: task.depth > 0 ? "" : task.detail, selected: pickedWeekly.contains(task.id),
                                        topic: task.topicID.flatMap { id in topics.first { $0.id == id } }, waiting: task.waiting) {
                                    if let i = pickedWeekly.firstIndex(of: task.id) { pickedWeekly.remove(at: i) } else { pickedWeekly.append(task.id) }
                                }
                                .padding(.leading, task.depth > 0 ? 28 : 0)
                            }
                        }
                        ForEach(Array(extra.enumerated()), id: \.offset) { i, item in
                            PickRow(title: item.0, detail: item.1, selected: true) { extra.remove(at: i) }
                        }
                    }
                }
                .frame(maxHeight: 260)
                .padding(.top, 8)
            }

            Eyebrow(T("Yeni görev", "New task")).padding(.top, 22)
            UnderlineField(placeholder: T("Görev başlığı", "Task title"), text: $newTitle, onSubmit: addTask)
            UnderlineField(placeholder: T("Açıklama (isteğe bağlı) · Enter ile ekle", "Details (optional) · Enter to add"), text: $newDetail, size: 12, onSubmit: addTask)
                .padding(.top, 2)

            Eyebrow(T("Ritim", "Rhythm")).padding(.top, 22)
            HStack(spacing: 10) {
                RhythmCard(big: "25", unit: T("dk odak", "min focus"), sub: T("+ 5 dk mola", "+ 5 min break"), selected: work == 25) { work = 25 }
                RhythmCard(big: "50", unit: T("dk odak", "min focus"), sub: T("+ 10 dk mola", "+ 10 min break"), selected: work == 50) { work = 50 }
            }
            .padding(.top, 10)
            RhythmCard(big: T("Serbest", "Free"), unit: "", sub: T("İleri sayar, 50. dakikada mola önerir", "Counts up, suggests a break at 50 min"),
                       icon: "infinity", selected: work == 0) { work = 0 }
                .padding(.top, 10)

            HStack(spacing: 8) {
                Button(T("Vazgeç", "Cancel"), action: close).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(work == 0 ? T("Başla · serbest", "Start · free") : T("Başla · \(work) dk", "Start · \(work) min"), action: begin).buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
            Text(T("Her yerden: ⌥⌘N", "From anywhere: ⌥⌘N")).font(.system(size: 11)).foregroundStyle(Ink.faint)
                .frame(maxWidth: .infinity).padding(.top, 12)
        }
        .padding(30)
        .frame(width: 520)
        .onAppear { if waiting.isEmpty && !weekly.isEmpty { source = 1 } }
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Ink.glassStrong))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Ink.line))
        .foregroundStyle(Ink.text)
        .environment(\.colorScheme, .dark)
    }

    /// Seçili kategorinin görevleri üstte; dosyadaki sıra korunur.
    private var weeklySorted: [WeeklyTask] {
        let mine = weekly.filter { $0.topicID != nil && $0.topicID == topic?.id }
        return mine + weekly.filter { !mine.contains($0) }
    }

    private func addTask() {
        let t = newTitle.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        extra.append((t, newDetail.trimmingCharacters(in: .whitespaces)))
        newTitle = ""; newDetail = ""
    }

    private func begin() {
        addTask()
        guard let topic else { return }
        UserDefaults.standard.set(topic.id, forKey: "lastTopic")
        UserDefaults.standard.set(work, forKey: "rhythmWork")
        let fromWeek = weekly.filter { pickedWeekly.contains($0.id) }.map { ($0.title, $0.detail) }
        Focus.shared.start(topic: topic, goal: goal.trimmingCharacters(in: .whitespaces), todoIDs: picked, newTodos: fromWeek + extra,
                           work: work, rest: work == 25 ? 5 : 10)
        close()
    }
}

private struct PickRow: View {
    let title: String, detail: String, selected: Bool
    var topic: Topic? = nil
    var waiting = false
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color(white: 0.96) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.white.opacity(selected ? 0 : 0.2)))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black).opacity(selected ? 1 : 0))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5)).lineLimit(2)
                    if !detail.isEmpty || waiting {
                        Text((waiting ? T("bekleniyor", "waiting") + (detail.isEmpty ? "" : " · ") : "") + detail)
                            .font(.system(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                }
                .padding(.top, 3)
                Spacer(minLength: 6)
                if let topic { CategorySwatch(category: topic, size: 14).padding(.top, 5) }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(selected ? 0.08 : hovering ? 0.04 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(selected ? 0.35 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RhythmCard: View {
    let big: String, unit: String, sub: String
    var icon: String? = nil
    let selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if let icon { Image(systemName: icon).font(.system(size: 22, weight: .light)).frame(width: 30) }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(big).font(.system(size: 28, weight: .ultraLight))
                        Text(unit).font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                    Text(sub).font(.system(size: 11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(selected ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(selected ? 0.65 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
