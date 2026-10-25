import Foundation

// Haftalık görev dosyası (örneğin Obsidian'daki haftalık not). Yalnız okunur, hiçbir şey yazılmaz.
// Yol bir şablondur; her açılışta bugünün tarihiyle çözülür, böylece hafta dönünce kendiliğinden yeni dosyaya geçer.
//   {YYYY} ISO hafta yılı · {WW} iki haneli ISO hafta · {W} hafta · {MM} ay · * herhangi bir klasör adı
// Örnek: ~/Obsidian/Kasa/AA Daily/* - {YYYY}/Hafta {WW}/Hafta {WW} - Yapılacaklar.md

struct WeeklyTask: Identifiable, Equatable {
    let id: Int               // dosyadaki satır numarası
    let title: String
    let detail: String        // alt görevse üst görevin başlığı
    let heading: String       // altında durduğu ##### başlığı
    let topicID: Int64?
    let waiting: Bool         // [w] bekleniyor
    var depth = 0             // 0 ana görev, 1 alt görev

    /// Alt görev, üst görevi hemen üstünde listelenmiyorsa üst görevin adı ayrı bir satırda gösterilir.
    static func startsSubgroup(_ list: [WeeklyTask], at i: Int) -> Bool {
        guard list[i].depth > 0 else { return false }
        guard i > 0 else { return true }
        let prev = list[i - 1]
        return prev.depth == 0 ? prev.title != list[i].detail : prev.detail != list[i].detail
    }
}

enum WeeklyList {
    static var template: String {
        get { UserDefaults.standard.string(forKey: "weeklyTemplate") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "weeklyTemplate") }
    }

    static var isOn: Bool { !template.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Şablonu verilen tarihe göre çözer ve var olan dosyayı bulur. Birden fazla eşleşme varsa en son değişeni.
    static func file(for date: Date = Date(), template: String = WeeklyList.template) -> URL? {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = .current
        let week = iso.component(.weekOfYear, from: date), year = iso.component(.yearForWeekOfYear, from: date)
        let month = Calendar.current.component(.month, from: date)
        let path = (template as NSString).expandingTildeInPath
            .replacingOccurrences(of: "{YYYY}", with: String(year))
            .replacingOccurrences(of: "{WW}", with: String(format: "%02d", week))
            .replacingOccurrences(of: "{W}", with: String(week))
            .replacingOccurrences(of: "{MM}", with: String(format: "%02d", month))
        guard path.hasPrefix("/") else { return nil }
        var candidates = ["/"]
        for part in path.split(separator: "/").map(String.init) {
            var next: [String] = []
            for base in candidates {
                if part.contains("*") {
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
                    next += names.filter { fnmatch(part, $0, 0) == 0 }.map { (base as NSString).appendingPathComponent($0) }
                } else {
                    let p = (base as NSString).appendingPathComponent(part)
                    if FileManager.default.fileExists(atPath: p) { next.append(p) }
                }
            }
            candidates = next
            if candidates.isEmpty { return nil }
        }
        let modified = { (p: String) -> Date in ((try? FileManager.default.attributesOfItem(atPath: p))?[.modificationDate] as? Date) ?? .distantPast }
        return candidates.max { modified($0) < modified($1) }.map { URL(fileURLWithPath: $0) }
    }

    /// Açık ve bekleyen görevler. Bitmiş, iptal ya da başka haftaya taşınmış görevler atlanır.
    static func load(topics: [Topic]) -> [WeeklyTask] {
        guard isOn, let url = file(), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text, topics: topics)
    }

    static func parse(_ text: String, topics: [Topic]) -> [WeeklyTask] {
        var out: [WeeklyTask] = []
        var heading = ""
        var parent: (indent: Int, title: String)?
        for (n, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.replacingOccurrences(of: "    ", with: "\t")
            if line.hasPrefix("#") {
                heading = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
                parent = nil
                continue
            }
            let indent = line.prefix { $0 == "\t" }.count
            let body = line.dropFirst(indent)
            guard body.hasPrefix("- ["), body.count > 5 else {
                // "- 1.0" gibi görev olmayan üst madde, altındaki görevlerin grubudur
                if indent == 0, body.hasPrefix("- ") { parent = (0, clean(String(body.dropFirst(2)))) }
                continue
            }
            let state = body[body.index(body.startIndex, offsetBy: 3)]
            let rest = String(body.dropFirst(6))
            let title = clean(rest)
            if indent == 0 { parent = (0, title) }
            guard state == " " || state == "w" || state == "/", !rest.contains("→ Hafta"), !title.isEmpty else { continue }
            let tag = rest.split(separator: " ").first { $0.hasPrefix("#") }.map { String($0.dropFirst()) }
            out.append(WeeklyTask(id: n, title: title, detail: indent > 0 ? (parent?.title ?? "") : "",
                                  heading: heading, topicID: match(heading: heading, tag: tag, topics: topics), waiting: state == "w",
                                  depth: indent > 0 ? 1 : 0))
        }
        return out
    }

    /// "[[Kişi|Takma ad]]" → "Takma ad", "#etiket" ve "✅ tarih" atılır, "→ [[Düğüm]]" gibi son ekler kesilir.
    static func clean(_ s: String) -> String {
        var t = s
        if let r = t.range(of: " → ") { t = String(t[..<r.lowerBound]) }
        if let r = t.range(of: " ✅") { t = String(t[..<r.lowerBound]) }
        while let open = t.range(of: "[["), let close = t.range(of: "]]", range: open.upperBound..<t.endIndex) {
            let inner = String(t[open.upperBound..<close.lowerBound])
            t.replaceSubrange(open.lowerBound..<close.upperBound, with: inner.split(separator: "|").last.map(String.init) ?? inner)
        }
        t = t.split(separator: " ").filter { !($0.hasPrefix("#") && $0.count > 1) }.joined(separator: " ")
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Başlığı ya da etiketi kategori adıyla eşleştirir; büyük-küçük harf ve sondaki "s" önemsenmez (Maestrock ~ Maestrocks).
    static func match(heading: String, tag: String?, topics: [Topic]) -> Int64? {
        func norm(_ s: String) -> String {
            var x = s.lowercased(with: Locale(identifier: "tr_TR")).filter { $0.isLetter || $0.isNumber }
            if x.hasSuffix("s") { x.removeLast() }
            return x
        }
        for key in [heading, tag ?? ""] where !key.isEmpty {
            if let t = topics.first(where: { norm($0.name) == norm(key) }) { return t.id }
        }
        return nil
    }
}
