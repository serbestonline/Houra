import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

// Uygulama paneli: Bugün, İstatistik, Oturumlar, Kategoriler, Ayarlar. Yalnız menüden açılır;
// açıkken Houra Dock'ta normal bir uygulama gibi görünür.

final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()
    enum Page: String, CaseIterable { case today, stats, sessions, categories, settings }

    private var window: NSWindow?
    let state = PanelState()

    func show(page: Page? = nil) {
        if let page { state.page = page }
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(white: 0.04, alpha: 1)
            w.minSize = NSSize(width: 940, height: 620)
            w.delegate = self
            w.contentView = NSHostingView(rootView: PanelRoot().environmentObject(state))
            w.center()
            w.setFrameAutosaveName("HouraPanel")
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.mainMenu = MainMenu.make()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.window?.makeFirstResponder(nil) }   // kenar çubuğunda odak çerçevesi çıkmasın
    }

    /// Dil değişince bütün metinler yeniden kurulur.
    func reload() {
        window?.contentView = NSHostingView(rootView: PanelRoot().environmentObject(state))
        NSApp.mainMenu = MainMenu.make()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

final class PanelState: ObservableObject {
    @Published var page: PanelController.Page = .today
    @Published var version = 0      // veritabanı değişince artar, sayfalar yeniden okur
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .storeChanged, object: nil, queue: .main) { [weak self] _ in self?.version += 1 }
    }
}

private struct PanelRoot: View {
    @EnvironmentObject private var state: PanelState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(Ink.line).frame(width: 1)
            ZStack {
                switch state.page {
                case .today: TodayPage()
                case .stats: StatsPage()
                case .sessions: SessionsPage()
                case .categories: CategoriesPage()
                case .settings: SettingsPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(state.page)
        }
        .background(Ink.background)
        .foregroundStyle(Ink.text)
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Language.locale)
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var state: PanelState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            nav(.today, "clock", T("Bugün", "Today"))
            nav(.stats, "chart.bar.xaxis", T("İstatistik", "Statistics"))
            nav(.sessions, "list.bullet", T("Oturumlar", "Sessions"))
            nav(.categories, "square.grid.2x2", T("Kategoriler", "Categories"))
            Spacer()
            nav(.settings, "gearshape", T("Ayarlar", "Settings"))
            Button { NewSessionController.shared.show() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
                        .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.96)))
                    Text(T("Yeni oturum", "New session")).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text("⌥⌘N").font(.system(size: 11)).foregroundStyle(Ink.faint)
                }
                .padding(.leading, 8).padding(.trailing, 10).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(.horizontal, 12).padding(.top, 52).padding(.bottom, 16)
        .frame(width: 214)
        .background(Color.white.opacity(0.02))
    }

    private func nav(_ page: PanelController.Page, _ icon: String, _ title: String) -> some View {
        Button { state.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18).foregroundStyle(state.page == page ? Ink.text : Ink.muted)
                Text(title).font(.system(size: 13.5))
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(state.page == page ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(state.page == page ? Ink.text : Ink.text.opacity(0.75))
    }
}

/// Sayfa başlığı: küçük üst yazı ve büyük ince başlık.
struct PageHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(eyebrow)
                Text(title).font(.system(size: 34, weight: .ultraLight)).tracking(-0.6)
            }
            Spacer()
            trailing
        }
        .padding(.bottom, 26)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ink.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ink.line))
    }
}

struct StatCard: View {
    let title: String, value: String, detail: String
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(title)
                Text(value).font(.system(size: 28, weight: .light)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(detail).font(.system(size: 12)).foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
    }
}

// MARK: - Bugün

private struct TodayPage: View {
    @EnvironmentObject private var state: PanelState
    @State private var title = ""
    @State private var detail = ""

    var body: some View {
        let _ = state.version
        let dayStart = Calendar.current.startOfDay(for: Date())
        let sessions = Store.shared.sessions(from: dayStart, to: .distantFuture).filter { $0.end != nil }
        let todos = Store.shared.todos(day: dayKey(Date()))
        let topics = Dictionary(uniqueKeysWithValues: Store.shared.categories().map { ($0.id, $0) })
        let restMin = sessions.reduce(0) { $0 + $1.restMinutes }
        let focusMin = sessions.reduce(0) { $0 + $1.minutes }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(eyebrow: T("Bugün", "Today") + " · " + formatDate(Date(), "dMMMMEEEE"),
                           title: T("\(formatMinutes(focusMin)) odak", "\(formatMinutes(focusMin)) focused")) { EmptyView() }
                Grid(horizontalSpacing: 14, verticalSpacing: 14) {   // alt satır üstteki dört kartın sütunlarına otursun
                GridRow {
                    StatCard(title: T("Oturum", "Sessions"), value: "\(sessions.count)",
                             detail: T("\(sessions.filter { $0.workMinutes == 50 }.count) tanesi 50 + 10", "\(sessions.filter { $0.workMinutes == 50 }.count) of them 50 + 10"))
                    StatCard(title: T("Mola", "Breaks"), value: formatMinutes(restMin), detail: T("\(sessions.count) mola", "\(sessions.count) breaks"))
                    StatCard(title: T("Görev", "Tasks"), value: "\(todos.filter { $0.state == .done }.count) / \(todos.count)", detail: T("tamamlandı 🥳", "done 🥳"))
                    StatCard(title: T("Acil durum", "Emergency"), value: "\(sessions.filter(\.emergency).count)", detail: T("moladan erken dönüş", "early returns from a break"))
                }
                GridRow(alignment: .top) {
                    VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Eyebrow(T("Bugün yapılacaklar", "Today's to-do"))
                                Spacer()
                                Text("\(todos.filter { $0.state == .done }.count) / \(todos.count)").font(.system(size: 12)).foregroundStyle(Ink.muted)
                            }
                            VStack(spacing: 2) {
                                if todos.isEmpty {
                                    Text(T("Bugün için liste boş.", "Nothing on today's list.")).font(.system(size: 12.5)).foregroundStyle(Ink.faint)
                                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }
                                ForEach(todos) { DayTodoRow(todo: $0) }
                            }
                            .padding(.top, 10)
                            UnderlineField(placeholder: T("Görev başlığı", "Task title"), text: $title, onSubmit: add).padding(.top, 8)
                            UnderlineField(placeholder: T("Açıklama (isteğe bağlı) · Enter ile ekle", "Details (optional) · Enter to add"), text: $detail, size: 12, onSubmit: add)
                        }
                    }
                    if WeeklyList.isOn { WeekCard(topics: Array(topics.values)) }
                    }
                    .gridCellColumns(2)
                    Card {
                        VStack(alignment: .leading, spacing: 16) {
                            Eyebrow(T("Gün akışı", "Day flow"))
                            if sessions.isEmpty && Focus.shared.session == nil {
                                Text(T("Bugün henüz oturum yok.", "No sessions yet today.")).font(.system(size: 12.5)).foregroundStyle(Ink.faint)
                            } else {
                                DayColumn(sessions: sessions, topics: topics)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)   // gün akışı sol sütunun boyunca uzasın
                    }
                    .gridCellColumns(2)
                }
                }
            }
            .padding(36)
        }
    }

    private func add() {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        Store.shared.addTodo(day: dayKey(Date()), title: t, detail: detail.trimmingCharacters(in: .whitespaces))
        title = ""; detail = ""
    }
}

/// Haftalık nottaki açık görevler, proje proje. Bir göreve tıklayınca o görev seçili yeni oturum açılır.
private struct WeekCard: View {
    let topics: [Topic]
    @State private var tasks: [WeeklyTask] = []
    @State private var fileName = ""
    private let refresh = Timer.publish(every: 20, on: .main, in: .common).autoconnect()   // Obsidian'daki değişiklikler gelsin

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Eyebrow(T("Bu hafta", "This week"))
                    Spacer()
                    Text(fileName.isEmpty ? T("haftalık not bulunamadı", "weekly note not found") : "\(fileName) · \(T("\(tasks.count) açık görev", "\(tasks.count) open tasks"))")
                        .font(.system(size: 12)).foregroundStyle(Ink.muted)
                }
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(groups, id: \.heading) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                if let t = group.topic { CategorySwatch(category: t, size: 16) }
                                Text(group.heading).font(.system(size: 13, weight: .semibold))
                                Text("\(group.tasks.count)").font(.system(size: 12)).foregroundStyle(Ink.faint)
                            }
                            .padding(.bottom, 4)
                            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { i, task in
                                if WeeklyTask.startsSubgroup(group.tasks, at: i) {
                                    Text(task.detail).font(.system(size: 12)).foregroundStyle(Ink.faint).lineLimit(1)
                                        .padding(.leading, 26).padding(.top, 4)
                                }
                                WeekTaskRow(task: task).padding(.leading, task.depth > 0 ? 20 : 0)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onReceive(refresh) { _ in load() }
    }

    private var groups: [(heading: String, topic: Topic?, tasks: [WeeklyTask])] {
        var order: [String] = [], byHeading: [String: [WeeklyTask]] = [:]
        for t in tasks {
            let h = t.heading.isEmpty ? T("Diğer", "Other") : t.heading
            if byHeading[h] == nil { order.append(h) }
            byHeading[h, default: []].append(t)
        }
        return order.map { h in (h, byHeading[h]?.first?.topicID.flatMap { id in topics.first { $0.id == id } }, byHeading[h] ?? []) }
    }

    private func load() {
        tasks = WeeklyList.load(topics: topics)
        fileName = WeeklyList.file()?.deletingPathExtension().lastPathComponent ?? ""
    }
}

private struct WeekTaskRow: View {
    let task: WeeklyTask
    @State private var hovering = false
    var body: some View {
        Button { NewSessionController.shared.show(preselect: task) } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle().strokeBorder(Color.white.opacity(task.waiting ? 0.25 : 0.4), style: StrokeStyle(lineWidth: 1, dash: task.waiting ? [2, 2] : []))
                    .frame(width: 12, height: 12).padding(.top, 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.title).font(.system(size: 13)).foregroundStyle(task.waiting ? Ink.muted : Ink.text).lineLimit(2)
                    if task.waiting {
                        Text(T("bekleniyor", "waiting")).font(.system(size: 11)).foregroundStyle(Ink.faint)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Ink.muted).opacity(hovering ? 1 : 0).padding(.top, 4)
            }
            .padding(.vertical, 5).padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(T("Bu görevle oturum başlat", "Start a session with this task"))
    }
}

private struct DayTodoRow: View {
    let todo: Todo
    @State private var hovering = false
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { Store.shared.setTodoState(id: todo.id, todo.state.next) } label: {
                Text(todo.state.emoji).font(.system(size: 14)).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title).font(.system(size: 13.5)).foregroundStyle(todo.state == .done ? Ink.faint : Ink.text)
                if !todo.detail.isEmpty { Text(todo.detail).font(.system(size: 11.5)).foregroundStyle(todo.state == .done ? Ink.faint : Ink.muted) }
            }
            .padding(.top, 3)
            Spacer()
            Button { Store.shared.deleteTodo(id: todo.id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Ink.muted).opacity(hovering ? 1 : 0).padding(.top, 6)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(todo.state == .doing ? 0.07 : hovering ? 0.03 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(todo.state == .doing ? 0.25 : 0)))
        .onHover { hovering = $0 }
    }
}

// MARK: - Oturumlar

private struct SessionsPage: View {
    @EnvironmentObject private var state: PanelState
    @State private var topicFilter: Int64?
    @State private var notesOnly = false
    @State private var open: Set<Int64> = []

    var body: some View {
        let _ = state.version
        let topics = Store.shared.categories()
        let byID = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
        let all = Store.shared.sessions(from: Date().addingTimeInterval(-90 * 86400), to: .distantFuture)
            .filter { $0.end != nil && (topicFilter == nil || $0.categoryID == topicFilter) && (!notesOnly || !$0.note.isEmpty) }
        let days = Dictionary(grouping: all) { Calendar.current.startOfDay(for: $0.start) }.sorted { $0.key > $1.key }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(eyebrow: T("Oturumlar", "Sessions"), title: T("Geçmiş", "History")) {
                    Segmented(options: [T("Tümü", "All"), T("Notlu", "With notes")], selection: notesOnly ? 1 : 0) { notesOnly = $0 == 1 }
                }
                HStack(spacing: 6) {
                    FilterChip(title: T("Tüm kategoriler", "All categories"), topic: nil, selected: topicFilter == nil) { topicFilter = nil }
                    ForEach(topics) { t in FilterChip(title: t.name, topic: t, selected: topicFilter == t.id) { topicFilter = t.id } }
                }
                .padding(.top, -8).padding(.bottom, 22)
                if days.isEmpty {
                    Text(T("Bu filtreye uyan oturum yok.", "No sessions match this filter.")).font(.system(size: 13)).foregroundStyle(Ink.faint)
                }
                ForEach(days, id: \.key) { day, list in
                    HStack {
                        Text(formatDate(day, "dMMMMEEEE")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                        Spacer()
                        Text(formatMinutes(list.reduce(0) { $0 + $1.minutes })).font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                    }
                    .padding(.bottom, 8)
                    ForEach(list.reversed()) { s in
                        SessionRow(session: s, topic: byID[s.categoryID], open: open.contains(s.id)) {
                            if open.contains(s.id) { open.remove(s.id) } else { open.insert(s.id) }
                        }
                    }
                    Spacer().frame(height: 22)
                }
            }
            .padding(36)
        }
    }
}

private struct SessionRow: View {
    let session: Session, topic: Topic?, open: Bool, toggle: () -> Void
    @State private var hovering = false
    @State private var editing = false
    @State private var confirming = false
    var body: some View {
        let todos = Store.shared.todos(session: session.id)
        let done = todos.filter { $0.state == .done }.count
        let meta = "\(formatTime(session.start)) – \(formatTime(session.end ?? session.start)) · \(session.rhythm)"
            + (todos.isEmpty ? "" : T(" · \(done)/\(todos.count) görev", " · \(done)/\(todos.count) tasks"))
            + (session.note.isEmpty ? "" : " · 📝") + (session.emergency ? T(" · acil durum", " · emergency") : "")
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                if let topic { CategorySwatch(category: topic, size: 16).padding(.top, 2) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(topic?.name ?? "") · \(session.goal)").font(.system(size: 14, weight: .medium))
                    Text(meta).font(.system(size: 12)).foregroundStyle(Ink.muted).monospacedDigit()
                }
                Spacer()
                Button { editing = true; if !open { toggle() } } label: { Image(systemName: "pencil").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).opacity(hovering || editing ? 1 : 0).padding(.top, 3)
                    .help(T("Kategoriyi, hedefi ve notu düzenle", "Edit category, goal and notes"))
                Button { confirming = true } label: { Image(systemName: "trash").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).opacity(hovering ? 1 : 0).padding(.top, 3)
                    .help(T("Oturumu sil", "Delete session"))
                    .confirmationDialog(T("Bu oturum silinsin mi? Süresi istatistiklerden düşer; görevleri günün listesinde kalır.",
                                          "Delete this session? Its time leaves the stats; its tasks stay on the day's list."), isPresented: $confirming) {
                        Button(T("Sil", "Delete"), role: .destructive) { Store.shared.deleteSession(id: session.id) }
                    }
                Text(formatMinutes(session.minutes)).font(.system(size: 15, weight: .light)).monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture { if open { editing = false }; toggle() }   // açık alandaki alanlara tıklamak satırı kapatmasın
            if open && editing {
                SessionEditor(session: session) { editing = false }.padding(.leading, 30).padding(.top, 14)
            } else if open {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(todos) { t in
                        HStack(alignment: .top, spacing: 10) {
                            Text(t.state.emoji)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.title).font(.system(size: 13)).foregroundStyle(t.state == .done ? Ink.faint : Ink.text)
                                if !t.detail.isEmpty { Text(t.detail).font(.system(size: 11.5)).foregroundStyle(Ink.muted) }
                            }
                        }
                    }
                    if !session.note.isEmpty {
                        Text(session.note).font(.system(size: 12.5)).lineSpacing(3).foregroundStyle(Ink.text.opacity(0.8))
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
                    }
                    if todos.isEmpty && session.note.isEmpty {
                        Text(T("Liste ve not yok.", "No list and no notes.")).font(.system(size: 12)).foregroundStyle(Ink.faint)
                    }
                }
                .padding(.leading, 30).padding(.top, 12)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(open ? 0.06 : hovering ? 0.05 : 0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(open ? Ink.line : .clear))
        .onHover { hovering = $0 }
        .padding(.bottom, 6)
    }
}

/// Oturumun kategorisini, hedefini ve notunu düzeltir; süren oturumda not ayrıntı panelinde zaten yazıldığından gizlenir.
struct SessionEditor: View {
    let session: Session
    var showsNote = true
    let done: () -> Void
    @State private var topicID: Int64 = 0
    @State private var goal = ""
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Store.shared.categories()) { t in FilterChip(title: t.name, topic: t, selected: topicID == t.id) { topicID = t.id } }
                }
            }
            UnderlineField(placeholder: T("Hedef", "Goal"), text: $goal, onSubmit: save)
            if showsNote { NotesEditor(text: $note) }
            HStack(spacing: 8) {
                Button(T("Vazgeç", "Cancel"), action: done).buttonStyle(SecondaryButtonStyle())
                Button(T("Kaydet", "Save"), action: save).buttonStyle(PrimaryButtonStyle())
            }
        }
        .onAppear { topicID = session.categoryID; goal = session.goal; note = session.note }
    }

    private func save() {
        guard let topic = Store.shared.categories().first(where: { $0.id == topicID }) else { return }   // silinmiş kategori: önce yenisi seçilmeli
        let g = goal.trimmingCharacters(in: .whitespaces)
        if session.id == Focus.shared.session?.id { Focus.shared.retag(topic: topic, goal: g) }
        else { Store.shared.updateSession(id: session.id, category: topic.id, goal: g.isEmpty ? topic.name : g, note: note) }
        done()
    }
}

struct FilterChip: View {
    let title: String, topic: Topic?, selected: Bool, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let topic { CategorySwatch(category: topic, size: 16) }
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(selected ? Ink.text : Ink.muted)
            .padding(.leading, topic == nil ? 11 : 5).padding(.trailing, 11).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.09 : 0.03)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(selected ? 0.5 : 0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Segmented: View {
    let options: [String], selection: Int, choose: (Int) -> Void
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Button { choose(i) } label: {
                    Text(o).font(.system(size: 12.5, weight: .medium)).foregroundStyle(selection == i ? Ink.text : Ink.muted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(selection == i ? 0.13 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Kategoriler

private struct CategoriesPage: View {
    @EnvironmentObject private var state: PanelState
    var body: some View {
        let _ = state.version
        let topics = Store.shared.categories()
        let sessions = Store.shared.sessions(from: .distantPast, to: .distantFuture)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PageHeader(eyebrow: T("Kategoriler", "Categories"), title: T("Renkler ve adlar", "Colours and names")) {
                    Button(T("+ Kategori", "+ Category")) {
                        Store.shared.addCategory(name: T("Yeni kategori", "New category"), color: palette[topics.count % palette.count])
                    }
                    .buttonStyle(SecondaryButtonStyle()).frame(width: 130)
                }
                ForEach(topics) { t in
                    let mine = sessions.filter { $0.categoryID == t.id }
                    CategoryRow(topic: t, count: mine.count, minutes: mine.reduce(0) { $0 + $1.minutes }, canDelete: topics.count > 1, first: t.id == topics.first?.id)
                }
            }
            .padding(36)
        }
    }
}

private struct CategoryRow: View {
    let topic: Topic, count: Int, minutes: Int, canDelete: Bool
    var first = false
    @State private var name = ""
    @State private var picking = false
    @State private var hovering = false
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 14) {
            Button { picking = true } label: { CategorySwatch(category: topic, size: 36) }
                .buttonStyle(.plain)
                .help(T("Renk, emoji ya da ikon", "Colour, emoji or icon"))
                .popover(isPresented: $picking, arrowEdge: .bottom) { SymbolPicker(topic: topic) }
            TextField("", text: $name)
                .textFieldStyle(.plain).font(.system(size: 14, weight: .medium))
                .onSubmit(save)
                .onAppear { name = topic.name }
            Text(T("\(count) oturum · \(formatMinutes(minutes))", "\(count) sessions · \(formatMinutes(minutes))"))
                .font(.system(size: 12)).foregroundStyle(Ink.muted).monospacedDigit()
            if canDelete {
                Button { confirming = true } label: { Image(systemName: "trash").font(.system(size: 12)) }
                    .buttonStyle(.plain).foregroundStyle(Ink.muted).opacity(hovering ? 1 : 0)
                    .confirmationDialog(T("\(topic.name) silinsin mi? Oturumları kayıtta kalır ama kategorisiz görünür.",
                                          "Delete \(topic.name)? Its sessions stay recorded but show without a category."), isPresented: $confirming) {
                        Button(T("Sil", "Delete"), role: .destructive) { Store.shared.deleteCategory(id: topic.id) }
                    }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.03)))
        .onHover { hovering = $0 }
        .onDisappear(perform: save)
        .onReceive(NotificationCenter.default.publisher(for: .pickerCommand)) { n in
            guard first else { return }
            SymbolPicker.startTab = n.userInfo?["tab"] as? Int ?? 0
            picking = n.userInfo?["close"] == nil
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != topic.name else { return }
        var t = topic; t.name = n
        Store.shared.updateCategory(t)
    }
}

/// Kategorinin rengi, emojisi ya da ikonu.
private struct SymbolPicker: View {
    static var startTab = 0
    let topic: Topic
    @State private var tab = SymbolPicker.startTab
    @State private var query = ""
    @State private var typed = ""

    private let emojis = "🎬 🎥 ✍️ 📝 📚 📖 🎓 🧠 🔬 🧪 🧬 💡 🎯 🚀 💼 🤝 📈 📊 💰 🏦 🛒 🏠 🚗 ✈️ 🏋️ 🏃 🧘 🕌 🤲 ☕ 🍳 🎮 🎸 🎧 🎨 📷 💻 ⌨️ 🖥️ 📱 🌍 🗣️ 📞 ✉️ 🗓️ ⏰ 🔥 ⭐ ❤️ 🌱 🐾 👶".split(separator: " ").map(String.init)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Segmented(options: [T("Renk", "Colour"), T("Emoji", "Emoji"), T("İkon", "Icon")], selection: tab) { tab = $0 }
            switch tab {
            case 0: colours
            case 1: emojiTab
            default: iconTab
            }
        }
        .padding(12)
        .frame(width: 330)
        .environment(\.colorScheme, .dark)
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }   // sekmede odak çerçevesi çıkmasın
    }

    private var colours: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 8), spacing: 10) {
                ForEach(palette, id: \.self) { hex in
                    Button { update { $0.color = hex } } label: { ColourDot(hex: hex, selected: hex == topic.color) }
                    .buttonStyle(.plain)
                }
                CustomColorButton(current: topic.color, isCustom: !palette.contains(topic.color)) { hex in update { $0.color = hex } }
            }
            Text(topic.color.uppercased()).font(.system(size: 11)).foregroundStyle(Ink.faint).monospacedDigit()
        }
    }

    private var emojiTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            UnderlineField(placeholder: T("Bir emoji yaz ya da yapıştır (⌃⌘Boşluk)", "Type or paste an emoji (⌃⌘Space)"), text: $typed, size: 13) {
                if let first = typed.first { update { $0.emoji = String(first); $0.icon = nil } }
            }
            grid(items: [""] + emojis, selected: { !$0.isEmpty && $0 == (topic.emoji ?? "") }) { e in
                Text(e.isEmpty ? "∅" : e).font(.system(size: 17)).foregroundStyle(Ink.muted)
            } choose: { e in update { $0.emoji = e.isEmpty ? nil : e; $0.icon = nil } }
        }
    }

    private var iconTab: some View {
        let q = query.lowercased(with: Language.locale)
        let names = [""] + iconLibrary.filter { q.isEmpty || $0.name.contains(q) || $0.keywords.contains(q) }.map(\.name)
        return VStack(alignment: .leading, spacing: 10) {
            UnderlineField(placeholder: T("İkon ara: kitap, kamera, beyin…", "Search icons: book, camera, brain…"), text: $query, size: 13)
            grid(items: names, selected: { !$0.isEmpty && $0 == (topic.icon ?? "") }) { n in
                if n.isEmpty { Text("∅").font(.system(size: 17)).foregroundStyle(Ink.muted) }
                else if let shape = IconShape(name: n) { shape.fill(Color.white.opacity(0.85)).frame(width: 18, height: 18) }
            } choose: { n in update { $0.icon = n.isEmpty ? nil : n; $0.emoji = nil } }
            HStack(spacing: 8) {
                Eyebrow(T("İkon rengi", "Icon colour"))
                Spacer()
                CategorySwatch(category: topic, size: 22)
            }
            .padding(.top, 4)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 8), spacing: 10) {
                ForEach(Self.inkColours, id: \.self) { hex in
                    Button { update { $0.iconColor = hex } } label: { ColourDot(hex: hex, selected: hex == topic.iconColor) }.buttonStyle(.plain)
                }
                CustomColorButton(current: topic.iconColor ?? "#ffffff", isCustom: topic.iconColor.map { !Self.inkColours.contains($0) } ?? false) { hex in
                    update { $0.iconColor = hex }
                }
            }
            Text(T("Phosphor ikonları · MIT lisansı", "Phosphor icons · MIT licence")).font(.system(size: 10.5)).foregroundStyle(Ink.faint)
        }
    }

    private func grid<Cell: View>(items: [String], selected: @escaping (String) -> Bool,
                                  @ViewBuilder cell: @escaping (String) -> Cell, choose: @escaping (String) -> Void) -> some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button { choose(item) } label: {
                        cell(item).frame(maxWidth: .infinity, minHeight: 32)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected(item) ? 0.18 : 0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(selected(item) ? 0.6 : 0)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: tab == 2 ? 170 : 230)
    }

    private static let inkColours = ["#ffffff", "#000000"] + palette.filter { $0 != "#e9e9ee" && $0 != "#3a3f4d" }

    private func update(_ change: (inout Topic) -> Void) {
        var t = Store.shared.categories().first { $0.id == topic.id } ?? topic
        change(&t)
        Store.shared.updateCategory(t)
    }
}

private struct ColourDot: View {
    let hex: String, selected: Bool
    var body: some View {
        Circle().fill(Color(hex: hex)).frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
            .padding(2)
            .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.85 : 0), lineWidth: 1.5))
    }
}

/// Paletin sonundaki gökkuşağı daire: sistemin renk panelini açar.
private struct CustomColorButton: View {
    let current: String, isCustom: Bool
    let pick: (String) -> Void
    var body: some View {
        Button { ColorPanelBridge.shared.open(current, onPick: pick) } label: {
            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                .frame(width: 22, height: 22)
                .overlay(Circle().fill(isCustom ? Color(hex: current) : .clear).padding(5))
                .padding(2)
                .overlay(Circle().strokeBorder(Color.white.opacity(isCustom ? 0.85 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(T("Özel renk", "Custom colour"))
    }
}

final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onPick: ((String) -> Void)?

    func open(_ hex: String, onPick: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        self.onPick = nil
        panel.showsAlpha = false
        panel.color = NSColor(hex: hex)
        self.onPick = onPick
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        onPick?(String(format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255)))
    }
}

// MARK: - Ayarlar

private struct SettingsPage: View {
    @State private var language = Language.current
    @State private var style = Widgets.shared.style
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var weeklyTemplate = WeeklyList.template
    @State private var weeklyOn = WeeklyList.enabled
    private static let examplePattern = "AA Daily/* - {YYYY}/Hafta {WW}/Hafta {WW} - Yapılacaklar.md"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(eyebrow: T("Ayarlar", "Settings"), title: "Houra") { EmptyView() }
                Card {
                    row(T("Dil", "Language")) {
                        Segmented(options: [T("Sistem", "System"), "Türkçe", "English"], selection: Language.allCases.firstIndex(of: language) ?? 0) { i in
                            language = Language.allCases[i]; Language.current = language
                            DispatchQueue.main.async { PanelController.shared.reload() }
                        }
                    }
                }
                Card {
                    row(T("Ekranda göster", "Show on screen")) {
                        Segmented(options: WidgetStyle.allCases.map(\.title), selection: WidgetStyle.allCases.firstIndex(of: style) ?? 0) { i in
                            style = WidgetStyle.allCases[i]; Widgets.shared.style = style
                        }
                    }
                }
                Card {
                    row(T("Açılışta başlat", "Launch at login")) {
                        Toggle("", isOn: $login).labelsHidden().toggleStyle(.switch)
                            .onChange(of: login) { on in
                                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                                catch { login = SMAppService.mainApp.status == .enabled }
                            }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(T("Haftalık görevler", "Weekly tasks")).font(.system(size: 14))
                            Spacer()
                            Toggle("", isOn: $weeklyOn).labelsHidden().toggleStyle(.switch)
                                .onChange(of: weeklyOn) { WeeklyList.enabled = $0 }
                        }
                        Text(T("Obsidian'daki haftalık notun gibi bir Markdown dosyasındaki açık görevler Bugün sayfasında \"Bu hafta\" kartında ve yeni oturum penceresinde \"Haftanın listesi\" olarak görünür. Dosya yalnız okunur. Yol her açılışta bugünün tarihiyle çözülür: {YYYY} yıl, {WW} hafta, {MM} ay, * herhangi bir klasör.",
                               "Open tasks from a Markdown file, such as your weekly note in Obsidian, show up in a \"This week\" card on the Today page and as \"This week's list\" in the new session window. The file is only read. The path is resolved with today's date every time: {YYYY} year, {WW} week, {MM} month, * any folder."))
                            .font(.system(size: 13)).foregroundStyle(Ink.muted)
                        VStack(alignment: .leading, spacing: 10) {
                        UnderlineField(placeholder: "~/Obsidian/Vault/" + Self.examplePattern, text: $weeklyTemplate, size: 12)
                            .onChange(of: weeklyTemplate) { WeeklyList.template = $0 }
                        HStack(spacing: 8) {
                            Button(T("Kasa klasörünü seç…", "Choose vault folder…"), action: chooseVault).buttonStyle(SecondaryButtonStyle()).frame(width: 200)
                        }
                        Text(weeklyStatus).font(.system(size: 12)).foregroundStyle(Ink.faint)
                        }
                        .disabled(!weeklyOn).opacity(weeklyOn ? 1 : 0.4)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(T("Veriler", "Data"))
                        Text(T("Bütün oturumlar, görevler ve notlar yalnız bu Mac'te, yerel bir SQLite dosyasında durur.",
                               "All sessions, tasks and notes stay on this Mac, in a local SQLite file."))
                            .font(.system(size: 13)).foregroundStyle(Ink.muted)
                        Text((Store.shared.path as NSString).abbreviatingWithTildeInPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(Ink.faint).textSelection(.enabled)
                        HStack(spacing: 8) {
                            Button(T("Finder'da göster", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Store.shared.path)]) }
                                .buttonStyle(SecondaryButtonStyle()).frame(width: 170)
                            Button(T("CSV olarak dışa aktar…", "Export as CSV…"), action: exportCSV).buttonStyle(SecondaryButtonStyle()).frame(width: 200)
                        }
                    }
                }
                Text("Houra \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                    .font(.system(size: 11)).foregroundStyle(Ink.faint).padding(.top, 6)
            }
            .padding(36)
        }
    }

    private var weeklyStatus: String {
        guard weeklyOn else { return T("Kapalı. Yol saklanır, açınca kaldığı yerden okunur.", "Off. The path is kept for when you turn it back on.") }
        guard !weeklyTemplate.trimmingCharacters(in: .whitespaces).isEmpty else { return T("Yol verilmedi.", "No path set.") }
        guard let file = WeeklyList.file(template: weeklyTemplate) else { return T("Bu haftanın dosyası bulunamadı.", "This week's file wasn't found.") }
        let n = (try? String(contentsOf: file, encoding: .utf8)).map { WeeklyList.parse($0, topics: Store.shared.categories()).count } ?? 0
        return T("Bu hafta: \(file.lastPathComponent) · \(n) açık görev", "This week: \(file.lastPathComponent) · \(n) open tasks")
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = T("Seç", "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        weeklyTemplate = (url.path as NSString).abbreviatingWithTildeInPath + "/" + Self.examplePattern
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).font(.system(size: 14)); Spacer(); content() }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "houra.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let topics = Dictionary(uniqueKeysWithValues: Store.shared.categories().map { ($0.id, $0.name) })
        let iso = ISO8601DateFormatter()
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let rows = Store.shared.sessions(from: .distantPast, to: .distantFuture).map { s in
            [iso.string(from: s.start), s.end.map { iso.string(from: $0) } ?? "", q(topics[s.categoryID] ?? ""), q(s.goal),
             "\(s.workMinutes)", "\(s.restMinutes)", "\(s.minutes)", s.emergency ? "1" : "0", q(s.note)].joined(separator: ",")
        }
        do {
            try (["start,end,category,goal,work_min,rest_min,focus_min,emergency,note"] + rows).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

// MARK: - Uygulama menüsü (panel açıkken)

enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        func sub(_ m: NSMenu) { let it = NSMenuItem(); it.submenu = m; menu.addItem(it) }
        let app = NSMenu(title: "Houra")
        app.addItem(withTitle: T("Houra'yı Gizle", "Hide Houra"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: T("Houra'dan Çık", "Quit Houra"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        sub(app)
        let edit = NSMenu(title: T("Düzen", "Edit"))
        edit.addItem(withTitle: T("Geri Al", "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: T("Kes", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: T("Kopyala", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: T("Yapıştır", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: T("Tümünü Seç", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        sub(edit)
        let window = NSMenu(title: T("Pencere", "Window"))
        window.addItem(withTitle: T("Küçült", "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: T("Kapat", "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        sub(window)
        return menu
    }
}
