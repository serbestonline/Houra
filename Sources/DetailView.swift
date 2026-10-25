import SwiftUI

// Ekran görünümlerinin üzerine gelince açılan ayrıntı paneli: süre, yapılacaklar, notlar, bugünün akışı.

struct DetailView: View {
    /// İnce şeridin çekmecesinde gün dikey çizelgeyle gösterilir.
    var vertical = false
    /// Ölçerken kaydırma kapalı (kaydırma alanı içeriğin boyunu gizler).
    var scrolls = true
    @ObservedObject private var focus = Focus.shared
    @State private var today: [Session] = []
    @State private var topics: [Int64: Topic] = [:]

    var body: some View {
        Group {
            if scrolls { ScrollView(showsIndicators: false) { content } } else { content }
        }
        .foregroundStyle(Ink.text)
        .onAppear(perform: load)
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow(focus.phase == .paused ? T("Duraklatıldı", "Paused") : T("Odak", "Focus"))
                    Spacer()
                    if let t = focus.topic {
                        HStack(spacing: 7) { CategorySwatch(category: t, size: 14); Text(t.name) }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Ink.line))
                    }
                }
                Text(focus.session?.goal ?? "").font(.system(size: 21, weight: .medium)).padding(.top, 14)
                Text(formatClock(focus.remaining))
                    .font(.system(size: 68, weight: .ultraLight)).monospacedDigit().tracking(-2)
                    .padding(.top, 10)
                if let s = focus.session, let end = focus.plannedEnd {
                    Text("\(formatTime(s.start)) → \(formatTime(end)) · \(T("\(s.workMinutes) dk", "\(s.workMinutes) min"))")
                        .font(.system(size: 12.5)).foregroundStyle(Ink.muted).monospacedDigit().padding(.top, 6)
                }
                ProgressLine(value: focus.progress).padding(.top, 16)
                HStack(spacing: 8) {
                    Button(focus.phase == .paused ? T("Devam et", "Resume") : T("Duraklat", "Pause")) {
                        focus.phase == .paused ? focus.resume() : focus.pause()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button(T("Bitir", "Finish")) { focus.finish() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(.top, 16)

                Divider().overlay(Ink.line).padding(.vertical, 18)
                HStack {
                    Eyebrow(T("Yapılacaklar", "To-do"))
                    Spacer()
                    if !focus.todos.isEmpty {
                        Text("\(focus.todos.filter { $0.state == .done }.count)/\(focus.todos.count)").font(.system(size: 12)).foregroundStyle(Ink.muted)
                    }
                }
                if focus.todos.isEmpty {
                    Text(T("Bu oturum için liste yok.", "No list for this session.")).font(.system(size: 12.5)).foregroundStyle(Ink.faint).padding(.top, 8)
                } else {
                    VStack(spacing: 2) { ForEach(focus.todos) { TodoRow(todo: $0) } }.padding(.top, 8)
                }

                Divider().overlay(Ink.line).padding(.vertical, 18)
                Eyebrow(T("Notlar", "Notes"))
                NotesEditor(text: $focus.note).padding(.top, 10)

                Divider().overlay(Ink.line).padding(.vertical, 18)
                Eyebrow(T("Bugün", "Today"))
                HStack(alignment: .firstTextBaseline) {
                    Text(formatMinutes(today.reduce(0) { $0 + $1.minutes } + Int(focus.elapsed) / 60)).font(.system(size: 20, weight: .light))
                    Spacer()
                    Text(T("\(today.count + 1) oturum", "\(today.count + 1) sessions")).font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                .padding(.top, 8)
                if vertical { DayColumn(sessions: today, topics: topics).padding(.top, 14) }
                else { DayStrip(sessions: today).padding(.top, 12) }
                HStack(spacing: 6) {
                    Text(T("Sırada", "Up next")).foregroundStyle(Ink.muted)
                    Text(T("\(focus.restSeconds / 60) dakika mola", "\(focus.restSeconds / 60) minute break"))
                }
                .font(.system(size: 12.5)).padding(.top, 16)
            }
            .padding(22)
    }

    private func load() {
        let start = Calendar.current.startOfDay(for: Date())
        today = Store.shared.sessions(from: start, to: .distantFuture).filter { $0.id != focus.session?.id && $0.end != nil }
        topics = Dictionary(uniqueKeysWithValues: Store.shared.categories().map { ($0.id, $0) })
    }
}

struct ProgressLine: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            Capsule().fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.66)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, g.size.width * value))
                }
        }
        .frame(height: 4)
    }
}

struct TodoRow: View {
    let todo: Todo
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { Focus.shared.cycle(todo) } label: {
                Text(todo.state.emoji).font(.system(size: 15)).frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.12 : 0.06)))
            }
            .buttonStyle(.plain)
            .help(T("Durumu değiştir", "Change state"))
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title).font(.system(size: 13.5, weight: todo.state == .doing ? .medium : .regular))
                    .foregroundStyle(todo.state == .done ? Ink.faint : Ink.text)
                if !todo.detail.isEmpty { Text(todo.detail).font(.system(size: 11.5)).foregroundStyle(todo.state == .done ? Ink.faint : Ink.muted) }
            }
            .padding(.top, 4)
            .onTapGesture { if todo.state != .done { Focus.shared.set(todo, .doing) } }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(todo.state == .doing ? 0.07 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(todo.state == .doing ? 0.25 : 0)))
        .onHover { hovering = $0 }
    }
}

/// Serbest yazılan oturum notu.
struct NotesEditor: View {
    @Binding var text: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(T("Aklına geleni yaz…", "Write down whatever comes to mind…")).font(.system(size: 13)).foregroundStyle(Ink.faint).padding(.top, 8).padding(.leading, 5)
            }
            TextEditor(text: $text)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .frame(minHeight: 78, maxHeight: 160)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.line))
    }
}

/// Günün yatay şeridi (08–20): biten oturumlar, şimdiki oturum ve şu an.
struct DayStrip: View {
    let sessions: [Session]
    @ObservedObject private var focus = Focus.shared

    var body: some View {
        let start = Calendar.current.startOfDay(for: Date())
        let from = 8.0, to = 20.0
        let x = { (d: Date) -> Double in (hourOfDay(d) - from) / (to - from) }
        VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05))
                    ForEach(sessions) { s in
                        let a = x(s.start), b = x(s.end ?? s.start)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.45))
                            .frame(width: max(3, g.size.width * (b - a)), height: 16).offset(x: g.size.width * a)
                    }
                    if let s = focus.session {
                        let a = x(s.start), b = x(Date())
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.9))
                            .frame(width: max(3, g.size.width * (b - a)), height: 16).offset(x: g.size.width * a)
                    }
                    Rectangle().fill(Color.white).frame(width: 1.5).offset(x: g.size.width * x(Date()))
                }
            }
            .frame(height: 26)
            HStack { ForEach(["08", "11", "14", "17", "20"], id: \.self) { Text($0); if $0 != "20" { Spacer() } } }
                .font(.system(size: 10)).foregroundStyle(Ink.faint).monospacedDigit()
        }
    }
}

/// Günün dikey çizelgesi: saat sütunu, bloklar gerçek saatlerinde, şu an solda etiket.
struct DayColumn: View {
    let sessions: [Session]
    let topics: [Int64: Topic]
    @ObservedObject private var focus = Focus.shared

    var body: some View {
        let cal = Calendar.current, startOfDay = cal.startOfDay(for: Date())
        let all = sessions.map { ($0.goal, $0.categoryID, $0.start, $0.end ?? $0.start, false) }
            + (focus.session.map { [($0.goal, $0.categoryID, $0.start, focus.plannedEnd ?? Date(), true)] } ?? [])
        let firstHour = Double(cal.component(.hour, from: all.map(\.2).min() ?? Date()))
        let lastHour = ceil(max(hourOfDay(all.map(\.3).max() ?? Date()), hourOfDay(Date())) + 0.01)
        let h: CGFloat = 60, hours = max(1, Int(lastHour - firstHour))
        let y = { (d: Date) -> CGFloat in CGFloat(hourOfDay(d) - firstHour) * h }
        ZStack(alignment: .topLeading) {
            ForEach(0...hours, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(String(format: "%02d:00", Int(firstHour) + i)).font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.faint)
                        .monospacedDigit().frame(width: 38, alignment: .trailing)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                .offset(y: CGFloat(i) * h - 6)
            }
            ForEach(Array(all.enumerated()), id: \.offset) { _, s in
                let top = y(s.2) + 1, height = max(18, y(s.3) - y(s.2) - 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(topics[s.1]?.name ?? "") · \(s.0)").font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    if height > 36 { Text("\(formatTime(s.2)) – \(formatTime(s.3))").font(.system(size: 10)).foregroundStyle(Ink.muted).monospacedDigit() }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: min(7, max(4, height * 0.2))).fill(Color.white.opacity(s.4 ? 0.16 : 0.07)))
                .overlay(RoundedRectangle(cornerRadius: min(7, max(4, height * 0.2))).strokeBorder(Color.white.opacity(s.4 ? 0.4 : 0)))
                .padding(.leading, 54)
                .offset(y: top)
            }
            Text(formatTime(Date())).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black).monospacedDigit()
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white))
                .offset(x: 0, y: y(Date()) - 8)
        }
        .frame(height: CGFloat(hours) * h, alignment: .top)
    }
}
