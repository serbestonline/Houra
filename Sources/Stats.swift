import SwiftUI

// İstatistik sayfası: dönem (hafta, ay, yıl ya da takvimden aralık), özet metrikler, üç grafik türü
// (takvim, akış, zaman haritası), kategori dağılımı ve verimli saatler. Uygulamada rengin kullanıldığı tek yer.

private enum Period: Equatable { case week, month, year, custom }

struct StatsPage: View {
    @EnvironmentObject private var state: PanelState
    @State private var period: Period = .week
    @State private var from = Calendar.current.mondayOf(Date())
    @State private var to = Calendar.current.date(byAdding: .day, value: 6, to: Calendar.current.mondayOf(Date()))!
    @State private var filter: Int64?
    @State private var hoverTopic: Int64?
    @State private var chart = 0
    @State private var openDay: Date?
    @State private var picking = false

    private let cal = Calendar.current

    var body: some View {
        let _ = state.version
        let data = StatsData(from: from, to: to, filter: filter)
        ZStack(alignment: .trailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(eyebrow: T("İstatistik", "Statistics"), title: title(data.days.count)) { periodControls }
                    if let f = filter, let t = data.topics[f] {
                        Button { filter = nil } label: {
                            HStack(spacing: 8) {
                                CategorySwatch(category: t, size: 16)
                                Text(T("Yalnız \(t.name)", "Only \(t.name)")).font(.system(size: 12.5, weight: .medium))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.muted)
                            }
                            .padding(.leading, 6).padding(.trailing, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: t.color).opacity(0.14)))
                            .overlay(Capsule().strokeBorder(Color(hex: t.color).opacity(0.55)))
                        }
                        .buttonStyle(.plain).padding(.top, -12).padding(.bottom, 18)
                    }
                    metrics(data)
                    section(T("Zamana göre", "Over time")) {
                        Segmented(options: [T("1 · Takvim", "1 · Calendar"), T("2 · Akış", "2 · Flow"), T("3 · Zaman haritası", "3 · Time map")], selection: chart) { chart = $0 }
                    } content: {
                        switch chart {
                        case 0: CalendarChart(data: data, accent: accent(data), open: { openDay = $0 })
                        case 1: FlowChart(data: data, highlight: hoverTopic, open: { openDay = $0 })
                        default: TimeMap(data: data, highlight: hoverTopic, open: { openDay = $0 })
                        }
                    }
                    section(T("Kategoriler", "Categories"), hint: T("Üzerine gel: grafikte öne çıkar · Tıkla: sayfayı filtrele", "Hover: highlight in chart · Click: filter the page")) { EmptyView() } content: {
                        categoryList(data)
                    }
                    section(T("Gün içinde en verimli saatler", "Most productive hours"), hint: data.peakHour.map { T("en yoğun saat \(String(format: "%02d", $0)):00", "busiest hour \(String(format: "%02d", $0)):00") } ?? "") { EmptyView() } content: {
                        hours(data)
                    }
                }
                .padding(36)
            }
            if let d = openDay {
                DayDrawer(day: d, topics: data.topics, close: { openDay = nil }, toSessions: { openDay = nil; state.page = .sessions })
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: openDay)
        .onReceive(NotificationCenter.default.publisher(for: .statsCommand)) { n in
            let u = n.userInfo ?? [:]
            if let c = u["chart"] as? Int { chart = c }
            if let p = u["period"] as? String { set(["week": .week, "month": .month, "year": .year][p] ?? .week, anchor: Date()) }
            if let st = u["step"] as? Int { step(st) }
            withAnimation(.easeInOut(duration: 0.35)) {
                if let f = u["filter"] as? Int64 { filter = f < 0 ? nil : f }
                if let h = u["hover"] as? Int64 { hoverTopic = h < 0 ? nil : h }
                if let d = u["open"] as? Date { openDay = d }
                if u["close"] != nil { openDay = nil }
            }
        }
    }

    private func accent(_ data: StatsData) -> Color {
        filter.flatMap { data.topics[$0] }.map { Color(hex: $0.color) } ?? Ink.statsAccent
    }

    private func title(_ n: Int) -> String {
        let now = Date(), isNow = from <= now && now < cal.date(byAdding: .day, value: 1, to: to)!
        switch period {
        case .week: return isNow ? T("Bu hafta", "This week") : rangeLabel
        case .month: return isNow ? T("Bu ay", "This month") : formatDate(from, "MMMMyyyy")
        case .year: return isNow ? T("Bu yıl", "This year") : formatDate(from, "yyyy")
        case .custom: return T("\(n) gün", "\(n) days")
        }
    }

    private var rangeLabel: String {
        cal.component(.year, from: from) == cal.component(.year, from: to)
            ? "\(formatDate(from, "dMMM")) – \(formatDate(to, "dMMMyyyy"))"
            : "\(formatDate(from, "dMMMyyyy")) – \(formatDate(to, "dMMMyyyy"))"
    }

    // MARK: Dönem

    private var periodControls: some View {
        HStack(spacing: 10) {
            Segmented(options: [T("Hafta", "Week"), T("Ay", "Month"), T("Yıl", "Year")],
                      selection: [Period.week, .month, .year].firstIndex(of: period) ?? -1) { set([Period.week, .month, .year][$0], anchor: Date()) }
            HStack(spacing: 2) {
                arrow("chevron.left") { step(-1) }
                Button { picking = true } label: {
                    HStack(spacing: 8) { Image(systemName: "calendar").foregroundStyle(Ink.muted); Text(rangeLabel).monospacedDigit() }
                        .font(.system(size: 12.5, weight: .medium)).padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $picking, arrowEdge: .bottom) {
                    RangePicker(from: from, to: to) { a, b in
                        from = a; to = b; period = .custom; picking = false
                    }
                }
                arrow("chevron.right") { step(1) }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
    }

    private func arrow(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(Ink.muted)
    }

    private func set(_ p: Period, anchor: Date) {
        period = p
        switch p {
        case .week: from = cal.mondayOf(anchor); to = cal.date(byAdding: .day, value: 6, to: from)!
        case .month:
            from = cal.date(from: cal.dateComponents([.year, .month], from: anchor))!
            to = cal.date(byAdding: DateComponents(month: 1, day: -1), to: from)!
        case .year:
            from = cal.date(from: cal.dateComponents([.year], from: anchor))!
            to = cal.date(byAdding: DateComponents(year: 1, day: -1), to: from)!
        case .custom: break
        }
    }

    private func step(_ dir: Int) {
        switch period {
        case .week: set(.week, anchor: cal.date(byAdding: .day, value: 7 * dir, to: from)!)
        case .month: set(.month, anchor: cal.date(byAdding: .month, value: dir, to: from)!)
        case .year: set(.year, anchor: cal.date(byAdding: .year, value: dir, to: from)!)
        case .custom:
            let n = (cal.dateComponents([.day], from: from, to: to).day ?? 0) + 1
            from = cal.date(byAdding: .day, value: n * dir, to: from)!; to = cal.date(byAdding: .day, value: n * dir, to: to)!
        }
    }

    // MARK: Parçalar

    private func metrics(_ data: StatsData) -> some View {
        let change = data.previousTotal > 0 ? Int((Double(data.total - data.previousTotal) / Double(data.previousTotal) * 100).rounded()) : nil
        return HStack(spacing: 0) {
            metric(T("Toplam odak", "Total focus"), formatMinutes(data.total)) {
                if let c = change {
                    Text(c >= 0 ? "↑ " + percent(c) : "↓ " + percent(-c)).foregroundColor(c >= 0 ? Color(red: 0.37, green: 0.84, blue: 0.63) : Color(red: 1, green: 0.54, blue: 0.5))
                    + Text(T(" önceki döneme göre", " vs previous period")).foregroundColor(Ink.muted)
                } else { Text(T("önceki dönemde kayıt yok", "no data in previous period")).foregroundStyle(Ink.muted) }
            }
            divider
            metric(T("Günlük ortalama", "Daily average"), formatMinutes(data.total / max(1, data.elapsedDays))) {
                Text(T("\(data.sessions.count) oturum", "\(data.sessions.count) sessions")).foregroundStyle(Ink.muted)
            }
            divider
            metric(T("Görev", "Tasks"), "\(data.tasksDone) / \(data.tasks)") {
                Text(T("tamamlandı · %\(data.tasks > 0 ? data.tasksDone * 100 / data.tasks : 0)", "done · \(data.tasks > 0 ? data.tasksDone * 100 / data.tasks : 0)%")).foregroundStyle(Ink.muted)
            }
            divider
            Button { if let b = data.bestDay { openDay = b.day } } label: {
                metric(T("En iyi gün", "Best day"), data.bestDay.map { formatMinutes($0.minutes) } ?? "—") {
                    Text(data.bestDay.map { formatDate($0.day, "dMMMMEEEE") + " ›" } ?? T("kayıt yok", "no data")).foregroundStyle(Ink.muted)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 30)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
        .padding(.bottom, 30)
    }

    private var divider: some View { Rectangle().fill(Ink.line).frame(width: 1, height: 64).padding(.horizontal, 22) }

    private func metric<Detail: View>(_ title: String, _ value: String, @ViewBuilder detail: () -> Detail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
            Text(value).font(.system(size: 28, weight: .ultraLight)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            detail().font(.system(size: 12)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section<Trailing: View, Content: View>(_ title: String, hint: String = "", @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(title)
                Spacer()
                if !hint.isEmpty { Text(hint).font(.system(size: 11)).foregroundStyle(Ink.faint) }
                trailing()
            }
            content()
        }
        .padding(.bottom, 36)
    }

    private func categoryList(_ data: StatsData) -> some View {
        let all = data.allTotalsByTopic, sum = max(1, all.values.reduce(0, +)), top = max(1, all.values.max() ?? 1)
        return VStack(spacing: 0) {
            ForEach(Array(data.topics.values).sorted { $0.id < $1.id }) { t in
                let m = all[t.id] ?? 0
                Button { filter = filter == t.id ? nil : t.id } label: {
                    VStack(spacing: 8) {
                        HStack {
                            CategorySwatch(category: t, size: 18)
                            Text(t.name).font(.system(size: 13.5, weight: .medium))
                            Spacer()
                            Text(percent(m * 100 / sum)).font(.system(size: 12.5)).foregroundStyle(Ink.muted).monospacedDigit().frame(width: 60, alignment: .trailing)
                            Text(formatMinutes(m)).font(.system(size: 12.5)).foregroundStyle(Ink.muted).monospacedDigit().frame(width: 110, alignment: .trailing)
                        }
                        GeometryReader { g in
                            Capsule().fill(Color.white.opacity(0.06)).overlay(alignment: .leading) {
                                Capsule().fill(Color(hex: t.color)).frame(width: g.size.width * Double(m) / Double(top))
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.vertical, 12)
                    .opacity(filter == nil || filter == t.id ? 1 : 0.35)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoverTopic = $0 ? t.id : (hoverTopic == t.id ? nil : hoverTopic) }
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }
        }
    }

    private func hours(_ data: StatsData) -> some View {
        let max = Swift.max(1, data.hourMinutes.max() ?? 1)
        return VStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<24, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 4).fill(accent(data).opacity(0.06 + Double(data.hourMinutes[h]) / Double(max) * 0.9))
                        .frame(height: 26)
                        .help("\(String(format: "%02d", h)):00 – \(String(format: "%02d", (h + 1) % 24)):00 · \(formatMinutes(data.hourMinutes[h]))")
                }
            }
            HStack { ForEach(["00", "06", "12", "18", "23"], id: \.self) { Text($0); if $0 != "23" { Spacer() } } }
                .font(.system(size: 10)).foregroundStyle(Ink.faint)
        }
    }
}

// MARK: - Veri

struct StatsData {
    let days: [Date]
    let sessions: [Session]
    let topics: [Int64: Topic]
    let filter: Int64?
    let total: Int
    let previousTotal: Int
    let elapsedDays: Int
    let tasks: Int
    let tasksDone: Int
    let bestDay: (day: Date, minutes: Int)?
    let hourMinutes: [Int]
    let peakHour: Int?
    /// Filtreden bağımsız kategori toplamları (liste her zaman bütün kategorileri gösterir).
    let allTotalsByTopic: [Int64: Int]
    private let byDay: [Date: [Session]]

    init(from: Date, to: Date, filter: Int64?) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from), end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to))!
        let n = (cal.dateComponents([.day], from: start, to: end).day ?? 1)
        days = (0..<n).map { cal.date(byAdding: .day, value: $0, to: start)! }
        topics = Dictionary(uniqueKeysWithValues: Store.shared.categories().map { ($0.id, $0) })
        self.filter = filter
        let all = Store.shared.sessions(from: start, to: end).filter { $0.end != nil }
        allTotalsByTopic = Dictionary(grouping: all, by: \.categoryID).mapValues { $0.reduce(0) { $0 + $1.minutes } }
        sessions = all.filter { filter == nil || $0.categoryID == filter }
        total = sessions.reduce(0) { $0 + $1.minutes }
        let prevStart = cal.date(byAdding: .day, value: -n, to: start)!
        previousTotal = Store.shared.sessions(from: prevStart, to: start).filter { filter == nil || $0.categoryID == filter }.reduce(0) { $0 + $1.minutes }
        let today = cal.startOfDay(for: Date())
        elapsedDays = max(1, min(n, (cal.dateComponents([.day], from: start, to: today).day ?? 0) + 1))
        var t = 0, d = 0
        for s in sessions { let todos = Store.shared.todos(session: s.id); t += todos.count; d += todos.filter { $0.state == .done }.count }
        tasks = t; tasksDone = d
        byDay = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.start) }
        let best = byDay.map { ($0.key, $0.value.reduce(0) { $0 + $1.minutes }) }.max { $0.1 < $1.1 }
        bestDay = best.map { (day: $0.0, minutes: $0.1) }
        var hours = Array(repeating: 0, count: 24)
        for s in sessions {
            var m = s.start
            let e = s.start.addingTimeInterval(Double(s.focusSeconds))
            while m < e { hours[cal.component(.hour, from: m)] += 1; m = m.addingTimeInterval(60) }
        }
        hourMinutes = hours
        peakHour = hours.max() == 0 ? nil : hours.firstIndex(of: hours.max()!)
    }

    func sessions(on day: Date) -> [Session] { byDay[day] ?? [] }
    func minutes(on day: Date) -> Int { sessions(on: day).reduce(0) { $0 + $1.minutes } }
    func minutes(on day: Date, topic: Int64) -> Int { sessions(on: day).filter { $0.categoryID == topic }.reduce(0) { $0 + $1.minutes } }
    var orderedTopics: [Topic] { topics.values.sorted { $0.id < $1.id }.filter { filter == nil || $0.id == filter } }
}

extension Calendar {
    func mondayOf(_ d: Date) -> Date {
        let day = startOfDay(for: d)
        let weekday = component(.weekday, from: day)   // 1 pazar
        return date(byAdding: .day, value: -((weekday + 5) % 7), to: day)!
    }
}

// MARK: - 1 · Takvim

private struct CalendarChart: View {
    let data: StatsData
    let accent: Color
    let open: (Date) -> Void
    private let cal = Calendar.current

    var body: some View {
        let max = Swift.max(1, data.days.map { data.minutes(on: $0) }.max() ?? 1)
        if data.days.count <= 42 { month(max) } else { year(max) }
    }

    private func month(_ max: Int) -> some View {
        let first = cal.mondayOf(data.days.first!), last = data.days.last!
        let count = (cal.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let cells = (0..<(Int(ceil(Double(count) / 7)) * 7)).map { cal.date(byAdding: .day, value: $0, to: first)! }
        let names = (0..<7).map { formatDate(cal.date(byAdding: .day, value: $0, to: first)!, "EEE") }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(names, id: \.self) { Text($0).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Ink.faint).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(cells, id: \.self) { d in
                DayCell(day: d, data: data, inRange: d >= data.days.first! && d <= last, max: max, accent: accent, open: open)
            }
        }
    }

    private func year(_ max: Int) -> some View {
        let first = cal.mondayOf(data.days.first!)
        let weeks = Int(ceil(Double((cal.dateComponents([.day], from: first, to: data.days.last!).day ?? 0) + 1) / 7))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { i in
                            let d = cal.date(byAdding: .day, value: w * 7 + i, to: first)!
                            let inRange = d >= data.days.first! && d <= data.days.last!, m = inRange ? data.minutes(on: d) : 0
                            Button { if inRange { open(d) } } label: {
                                RoundedRectangle(cornerRadius: 3).fill(m > 0 ? accent.opacity(0.1 + Double(m) / Double(max) * 0.75) : Color.white.opacity(0.04))
                                    .aspectRatio(1, contentMode: .fit)
                                    .opacity(inRange ? 1 : 0)
                            }
                            .buttonStyle(.plain)
                            .help(inRange ? "\(formatDate(d, "dMMMMEEEE")) · \(formatMinutes(m))" : "")
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text(T("az", "less")).font(.system(size: 10.5)).foregroundStyle(Ink.faint)
                ForEach([0.1, 0.3, 0.5, 0.75], id: \.self) { RoundedRectangle(cornerRadius: 3).fill(accent.opacity($0)).frame(width: 11, height: 11) }
                Text(T("çok", "more")).font(.system(size: 10.5)).foregroundStyle(Ink.faint)
            }
        }
    }
}

private struct DayCell: View {
    let day: Date, data: StatsData, inRange: Bool, max: Int, accent: Color, open: (Date) -> Void

    var body: some View {
        let m = inRange ? data.minutes(on: day) : 0
        let today = Calendar.current.isDateInToday(day)
        let fill: Color = m > 0 ? accent.opacity(0.1 + Double(m) / Double(max) * 0.6) : Color.white.opacity(0.03)
        let label = inRange ? "\(formatDate(day, "dMMMMEEEE")) · \(formatMinutes(m)) · \(data.sessions(on: day).count) \(T("oturum", "sessions"))" : ""
        return Button { if inRange { open(day) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Calendar.current.component(.day, from: day))").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(day > Date() ? Ink.faint : Ink.text.opacity(0.8))
                Spacer()
                if m > 0 { Text(formatMinutesShort(m)).font(.system(size: 14, weight: .light)).monospacedDigit() }
                mix(m).padding(.top, 6)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: 80, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(today ? 0.55 : 0)))
            .opacity(inRange ? 1 : 0.25)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverLift())
        .help(label)
    }

    /// Günün kategori dağılımını gösteren ince çizgi.
    private func mix(_ total: Int) -> some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(data.orderedTopics) { t in
                    let v = data.minutes(on: day, topic: t.id)
                    if v > 0 { RoundedRectangle(cornerRadius: 2).fill(Color(hex: t.color)).frame(width: Swift.max(2, (g.size.width - 6) * Double(v) / Double(Swift.max(1, total)))) }
                }
            }
        }
        .frame(height: 3)
    }
}

private struct HoverLift: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Lift(configuration: configuration) }
    private struct Lift: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .offset(y: hovering ? -2 : 0)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(hovering ? 0.25 : 0)))
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - 2 · Akış

private struct FlowChart: View {
    let data: StatsData
    let highlight: Int64?
    let open: (Date) -> Void
    @State private var hoverIndex: Int?

    var body: some View {
        let daily = data.days.count <= 62
        let buckets: [[Date]] = daily ? data.days.map { [$0] } : stride(from: 0, to: data.days.count, by: 7).map { Array(data.days[$0..<min($0 + 7, data.days.count)]) }
        let past = max(1, buckets.filter { $0[0] <= Date() }.count)
        let topics = data.orderedTopics
        let values = buckets.prefix(past).map { b in topics.map { t in b.reduce(0) { $0 + data.minutes(on: $1, topic: t.id) } } }
        let maxTotal = max(1, values.map { $0.reduce(0, +) }.max() ?? 1)
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                let x = { (i: Int) -> CGFloat in buckets.count == 1 ? w / 2 : 8 + CGFloat(i) * (w - 16) / CGFloat(buckets.count - 1) }
                let y = { (v: Int) -> CGFloat in h - CGFloat(v) / CGFloat(maxTotal) * (h - 16) }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(topics.enumerated()), id: \.element.id) { j, t in
                        let lo = values.map { Array($0.prefix(j)).reduce(0, +) }, hi = values.map { Array($0.prefix(j + 1)).reduce(0, +) }
                        FlowLayer(top: hi.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) },
                                  bottom: lo.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) })
                            .fill(Color(hex: t.color).opacity(0.85))
                            .opacity(highlight == nil || highlight == t.id ? 1 : 0.15)
                            .animation(.easeOut(duration: 0.2), value: highlight)
                    }
                    if let i = hoverIndex, i < past {
                        Rectangle().fill(Color.white.opacity(0.5)).frame(width: 1, height: h).offset(x: x(i))
                        tooltip(bucket: buckets[i], values: values[i], topics: topics)
                            .offset(x: min(x(i) + 12, w - 220), y: 8)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase {
                        let i = Int(((p.x - 8) / max(1, w - 16) * CGFloat(buckets.count - 1)).rounded())
                        hoverIndex = min(max(0, i), buckets.count - 1)
                    } else { hoverIndex = nil }
                }
                .onTapGesture { if daily, let i = hoverIndex, i < past { open(buckets[i][0]) } }
            }
            .frame(height: 230)
            let step = max(1, Int(ceil(Double(buckets.count) / 10)))
            HStack { ForEach(Array(stride(from: 0, to: buckets.count, by: step)), id: \.self) { i in
                Text(formatDate(buckets[i][0], "dMMM")); if i + step < buckets.count { Spacer() }
            } }
            .font(.system(size: 10.5)).foregroundStyle(Ink.faint)
        }
    }

    private func tooltip(bucket: [Date], values: [Int], topics: [Topic]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bucket.count == 1 ? formatDate(bucket[0], "dMMMMEEEE") : T("\(formatDate(bucket[0], "dMMMM")) haftası", "Week of \(formatDate(bucket[0], "dMMMM"))"))
                .font(.system(size: 12, weight: .semibold))
            Text(T("Toplam \(formatMinutes(values.reduce(0, +)))", "Total \(formatMinutes(values.reduce(0, +)))")).font(.system(size: 12))
            Divider().overlay(Color.white.opacity(0.12))
            ForEach(Array(topics.enumerated()), id: \.element.id) { j, t in
                HStack(spacing: 6) { Circle().fill(Color(hex: t.color)).frame(width: 6, height: 6); Text("\(t.name) · \(formatMinutes(values[j]))") }
                    .font(.system(size: 12))
            }
        }
        .padding(10)
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.06).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
        .monospacedDigit()
    }
}

/// İki çizgi arasında kalan, yumuşak geçişli alan.
private struct FlowLayer: Shape {
    let top: [CGPoint], bottom: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = top.first else { return p }
        p.move(to: f)
        curve(&p, top)
        p.addLine(to: bottom.last!)
        curve(&p, bottom.reversed())
        p.closeSubpath()
        return p
    }
    private func curve(_ p: inout Path, _ pts: [CGPoint]) {
        for i in 1..<max(1, pts.count) {
            let a = pts[i - 1], b = pts[i], cx = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: cx, y: a.y), control2: CGPoint(x: cx, y: b.y))
        }
    }
}

// MARK: - 3 · Zaman haritası

private struct TimeMap: View {
    let data: StatsData
    let highlight: Int64?
    let open: (Date) -> Void

    var body: some View {
        let shown = data.days.count > 31 ? Array(data.days.suffix(31)) : data.days
        let a = 6.0, b = 24.0, cal = Calendar.current
        VStack(alignment: .leading, spacing: 4) {
            if data.days.count > 31 { Text(T("Aralığın son 31 günü gösteriliyor.", "Showing the last 31 days of the range.")).font(.system(size: 11.5)).foregroundStyle(Ink.faint) }
            HStack(spacing: 10) {
                Spacer().frame(width: 52)
                GeometryReader { g in
                    ForEach([6, 9, 12, 15, 18, 21, 24], id: \.self) { hr in
                        Text(String(format: "%02d:00", hr % 24)).font(.system(size: 10)).foregroundStyle(Ink.faint)
                            .position(x: g.size.width * (Double(hr) - a) / (b - a), y: 6)
                    }
                }
                .frame(height: 14)
                Spacer().frame(width: 46)
            }
            ForEach(shown, id: \.self) { d in TimeMapRow(day: d, data: data, highlight: highlight, open: open) }
        }
    }
}

private struct TimeMapRow: View {
    let day: Date, data: StatsData, highlight: Int64?, open: (Date) -> Void
    private let a = 6.0, b = 24.0

    var body: some View {
        let list = data.sessions(on: day)
        let isToday = Calendar.current.isDateInToday(day)
        return Button { open(day) } label: {
            HStack(spacing: 10) {
                Text(formatDate(day, "EEEd")).font(.system(size: 11, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(isToday ? Ink.text : Ink.muted).frame(width: 52, alignment: .trailing)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.035))
                        ForEach(list) { s in block(s, width: g.size.width) }
                    }
                }
                .frame(height: 12)
                Text(list.isEmpty ? "" : formatMinutesShort(data.minutes(on: day))).font(.system(size: 11)).foregroundStyle(Ink.muted).monospacedDigit()
                    .frame(width: 46, alignment: .leading)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func block(_ s: Session, width: CGFloat) -> some View {
        let start = hourOfDay(s.start)
        let topic = data.topics[s.categoryID]
        let hours: CGFloat = CGFloat(s.focusSeconds) / 3600
        let w: CGFloat = max(2, width * hours / CGFloat(b - a))
        return RoundedRectangle(cornerRadius: 3).fill(Color(hex: topic?.color ?? "#888888"))
            .frame(width: w)
            .offset(x: width * CGFloat((start - a) / (b - a)))
            .opacity(highlight == nil || highlight == s.categoryID ? 1 : 0.12)
            .help("\(topic?.name ?? "") · \(formatTime(s.start)) – \(formatTime(s.end ?? s.start)) · \(formatMinutes(s.minutes))")
    }
}

// MARK: - Gün ayrıntısı

private struct DayDrawer: View {
    let day: Date
    let topics: [Int64: Topic]
    let close: () -> Void
    let toSessions: () -> Void

    var body: some View {
        let cal = Calendar.current
        let list = Store.shared.sessions(from: day, to: cal.date(byAdding: .day, value: 1, to: day)!).filter { $0.end != nil }
        let total = list.reduce(0) { $0 + $1.minutes }
        let byTopic = Dictionary(grouping: list, by: \.categoryID).mapValues { $0.reduce(0) { $0 + $1.minutes } }.sorted { $0.value > $1.value }
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow(formatDate(day, "yyyy"))
                    Spacer()
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))) }
                        .buttonStyle(.plain).foregroundStyle(Ink.muted)
                }
                Text(formatDate(day, "dMMMMEEEE")).font(.system(size: 24, weight: .light)).padding(.top, 4)
                Text(total > 0 ? T("\(formatMinutes(total)) odak", "\(formatMinutes(total)) focused") : T("Bu gün oturum yok", "No sessions this day"))
                    .font(.system(size: 13)).foregroundStyle(Ink.muted).padding(.top, 6)
                if total > 0 {
                    HStack(spacing: 3) {
                        ForEach(byTopic, id: \.key) { k, v in
                            RoundedRectangle(cornerRadius: 2).fill(Color(hex: topics[k]?.color ?? "#888888")).frame(maxWidth: .infinity).layoutPriority(Double(v))
                                .frame(width: 300 * Double(v) / Double(total))
                        }
                    }
                    .frame(height: 6).padding(.top, 18)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(byTopic, id: \.key) { k, v in
                            if let t = topics[k] { HStack(spacing: 8) { CategorySwatch(category: t, size: 14); Text("\(t.name) · \(formatMinutes(v))") }.font(.system(size: 12)).foregroundStyle(Ink.muted) }
                        }
                    }
                    .padding(.top, 12)
                }
                VStack(spacing: 6) {
                    ForEach(list) { s in
                        let todos = Store.shared.todos(session: s.id)
                        HStack(spacing: 12) {
                            Circle().fill(Color(hex: topics[s.categoryID]?.color ?? "#888888")).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(topics[s.categoryID]?.name ?? "") · \(s.goal)").font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(formatTime(s.start)) – \(formatTime(s.end ?? s.start)) · \(s.rhythm)"
                                     + (todos.isEmpty ? "" : T(" · \(todos.filter { $0.state == .done }.count)/\(todos.count) görev 🥳", " · \(todos.filter { $0.state == .done }.count)/\(todos.count) tasks 🥳")))
                                    .font(.system(size: 11.5)).foregroundStyle(Ink.muted).monospacedDigit()
                            }
                            Spacer()
                            Text(formatMinutes(s.minutes)).font(.system(size: 13, weight: .light)).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                    }
                }
                .padding(.top, 20)
                if total > 0 {
                    Button(T("Oturumlar sayfasında aç", "Open in Sessions"), action: toSessions).buttonStyle(SecondaryButtonStyle()).padding(.top, 16)
                }
            }
            .padding(26)
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
        .background(Color(white: 0.04).opacity(0.98))
        .overlay(alignment: .leading) { Rectangle().fill(Ink.line).frame(width: 1) }
        .shadow(color: .black.opacity(0.5), radius: 30, x: -20)
    }
}

// MARK: - Tarih aralığı

private struct RangePicker: View {
    @State var from: Date
    @State var to: Date
    let apply: (Date, Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach([7, 30, 90], id: \.self) { n in
                    Button(T("Son \(n) gün", "Last \(n) days")) {
                        to = Calendar.current.startOfDay(for: Date()); from = Calendar.current.date(byAdding: .day, value: -(n - 1), to: to)!
                    }
                    .buttonStyle(SecondaryButtonStyle()).frame(width: 110)
                }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(T("Başlangıç", "From"))
                    DatePicker("", selection: $from, in: ...to, displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(T("Bitiş", "To"))
                    DatePicker("", selection: $to, in: from..., displayedComponents: .date).datePickerStyle(.graphical).labelsHidden()
                }
            }
            HStack {
                let n = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 0) + 1
                Text(T("\(n) gün", "\(n) days")).font(.system(size: 12.5)).foregroundStyle(Ink.muted)
                Spacer()
                Button(T("Uygula", "Apply")) { apply(Calendar.current.startOfDay(for: from), Calendar.current.startOfDay(for: to)) }
                    .buttonStyle(PrimaryButtonStyle()).frame(width: 110)
            }
        }
        .padding(16)
        .environment(\.locale, Language.locale)
        .environment(\.colorScheme, .dark)
    }
}
