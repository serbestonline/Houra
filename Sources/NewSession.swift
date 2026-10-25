import AppKit
import SwiftUI

// Yeni oturum penceresi: kategori, hedef, bugünün listesinden görevler, yeni görev, ritim (25 + 5 ya da 50 + 10).

final class NewSessionController {
    static let shared = NewSessionController()
    /// Geliştirici kancası: kayıt betiği hedefi önceden doldurur.
    static var prefillGoal = ""
    private var window: NSWindow?

    func show() {
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
    @State private var topicID: Int64? = UserDefaults.standard.object(forKey: "lastTopic") as? Int64
    @State private var goal = NewSessionController.prefillGoal
    @State private var waiting = Store.shared.todos(day: dayKey(Date())).filter { $0.state != .done && $0.sessionID == nil }
    @State private var picked: [Int64] = []
    @State private var extra: [(String, String)] = []
    @State private var newTitle = ""
    @State private var newDetail = ""
    @State private var long = UserDefaults.standard.object(forKey: "longRhythm") as? Bool ?? true

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

            if !waiting.isEmpty || !extra.isEmpty {
                HStack {
                    Eyebrow(T("Bugünün listesinden seç", "Pick from today's list"))
                    Spacer()
                    let n = picked.count + extra.count
                    if n > 0 { Text(T("\(n) görev seçildi", "\(n) tasks selected")).font(.system(size: 12)).foregroundStyle(Ink.muted) }
                }
                .padding(.top, 22)
                VStack(spacing: 2) {
                    ForEach(waiting) { todo in
                        PickRow(title: todo.title, detail: todo.detail, selected: picked.contains(todo.id)) {
                            if let i = picked.firstIndex(of: todo.id) { picked.remove(at: i) } else { picked.append(todo.id) }
                        }
                    }
                    ForEach(Array(extra.enumerated()), id: \.offset) { i, item in
                        PickRow(title: item.0, detail: item.1, selected: true) { extra.remove(at: i) }
                    }
                }
                .padding(.top, 8)
            }

            Eyebrow(T("Yeni görev", "New task")).padding(.top, 22)
            UnderlineField(placeholder: T("Görev başlığı", "Task title"), text: $newTitle, onSubmit: addTask)
            UnderlineField(placeholder: T("Açıklama (isteğe bağlı) · Enter ile ekle", "Details (optional) · Enter to add"), text: $newDetail, size: 12, onSubmit: addTask)
                .padding(.top, 2)

            Eyebrow(T("Ritim", "Rhythm")).padding(.top, 22)
            HStack(spacing: 10) {
                RhythmCard(work: 25, rest: 5, selected: !long) { long = false }
                RhythmCard(work: 50, rest: 10, selected: long) { long = true }
            }
            .padding(.top, 10)

            HStack(spacing: 8) {
                Button(T("Vazgeç", "Cancel"), action: close).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(T("Başla · \(long ? 50 : 25) dk", "Start · \(long ? 50 : 25) min"), action: begin).buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 24)
            Text(T("Her yerden: ⌥⌘N", "From anywhere: ⌥⌘N")).font(.system(size: 11)).foregroundStyle(Ink.faint)
                .frame(maxWidth: .infinity).padding(.top, 12)
        }
        .padding(30)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Ink.glassStrong))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Ink.line))
        .foregroundStyle(Ink.text)
        .environment(\.colorScheme, .dark)
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
        UserDefaults.standard.set(long, forKey: "longRhythm")
        Focus.shared.start(topic: topic, goal: goal.trimmingCharacters(in: .whitespaces), todoIDs: picked, newTodos: extra,
                           work: long ? 50 : 25, rest: long ? 10 : 5)
        close()
    }
}

private struct PickRow: View {
    let title: String, detail: String, selected: Bool, toggle: () -> Void
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
                    Text(title).font(.system(size: 13.5))
                    if !detail.isEmpty { Text(detail).font(.system(size: 11.5)).foregroundStyle(Ink.muted) }
                }
                .padding(.top, 3)
                Spacer()
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
    let work: Int, rest: Int, selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(work)").font(.system(size: 28, weight: .ultraLight))
                    Text(T("dk odak", "min focus")).font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                Text(T("+ \(rest) dk mola", "+ \(rest) min break")).font(.system(size: 11.5)).foregroundStyle(Ink.muted)
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
