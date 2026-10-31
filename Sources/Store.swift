import Foundation
import SQLite3

// Yerel kayıt: ~/Library/Application Support/Houra/houra.sqlite.
// Kategoriler, günün yapılacakları ve oturumlar burada durur. HOURA_DB ortam değişkeni başka bir veritabanı verir.

struct Topic: Identifiable, Equatable {
    var id: Int64
    var name: String
    var color: String
    var emoji: String?
    var icon: String?
    var iconColor: String? = nil    // boşsa kategori rengine göre siyah ya da beyaz
}

enum TodoState: Int { case waiting = 0, doing = 1, done = 2
    var emoji: String { ["🤓", "🙂‍↔️", "🥳"][rawValue] }
    var next: TodoState { TodoState(rawValue: (rawValue + 1) % 3)! }
}

struct Todo: Identifiable, Equatable {
    var id: Int64
    var day: String          // yyyy-MM-dd
    var title: String
    var detail: String
    var state: TodoState
    var sessionID: Int64?
}

struct Session: Identifiable, Equatable {
    var id: Int64
    var categoryID: Int64
    var goal: String
    var workMinutes: Int
    var restMinutes: Int
    var start: Date
    var end: Date?
    var focusSeconds: Int     // duraklatmalar hariç gerçek odak
    var note: String
    var emergency: Bool       // moladan acil durumla erken dönüldü

    var minutes: Int { focusSeconds / 60 }
    /// "50 + 10" ya da serbest oturum için "serbest".
    var rhythm: String { workMinutes == 0 ? T("serbest", "free") : "\(workMinutes) + \(restMinutes)" }
}

extension Notification.Name {
    static let storeChanged = Notification.Name("HouraStoreChanged")
    /// Geliştirici kancası: kayıt betiği istatistik sayfasını yönetir (userInfo: chart, period, filter, open, close, hover).
    static let statsCommand = Notification.Name("HouraStatsCommand")
    static let stretchCommand = Notification.Name("HouraStretchCommand")   // README kaydı: molada esnemeyi aç
    /// Geliştirici kancası: kategori seçicisini açar (userInfo: tab).
    static let pickerCommand = Notification.Name("HouraPickerCommand")
}

func dayKey(_ date: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

final class Store {
    static let shared = Store(path: ProcessInfo.processInfo.environment["HOURA_DB"] ?? Store.defaultPath())

    let path: String
    private var db: OpaquePointer?

    static func defaultPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Houra")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("houra.sqlite").path
    }

    init(path: String) {
        self.path = path
        guard sqlite3_open(path, &db) == SQLITE_OK else { fatalError("Veritabanı açılamadı: \(path)") }
        exec("""
        CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL,
            emoji TEXT, icon TEXT, position INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY, day TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '',
            state INTEGER NOT NULL DEFAULT 0, session_id INTEGER, position INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL, goal TEXT NOT NULL,
            work_min INTEGER NOT NULL, rest_min INTEGER NOT NULL, start REAL NOT NULL, end REAL, focus_sec INTEGER NOT NULL DEFAULT 0,
            note TEXT NOT NULL DEFAULT '', emergency INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX IF NOT EXISTS todos_day ON todos(day);
        CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);
        """)
        var columns: [String] = []
        query("PRAGMA table_info(categories)") { columns.append(str($0, 1)) }
        if !columns.contains("icon_color") { exec("ALTER TABLE categories ADD COLUMN icon_color TEXT") }
        if categories().isEmpty {
            addCategory(name: T("Genel", "General"), color: "#4c8df0")
        }
    }

    deinit { sqlite3_close(db) }

    private func changed() { NotificationCenter.default.post(name: .storeChanged, object: nil) }

    // MARK: Kategoriler

    func categories() -> [Topic] {
        var out: [Topic] = []
        query("SELECT id, name, color, emoji, icon, icon_color FROM categories ORDER BY position, id") { s in
            out.append(Topic(id: col(s, 0), name: str(s, 1), color: str(s, 2), emoji: optStr(s, 3), icon: optStr(s, 4), iconColor: optStr(s, 5)))
        }
        return out
    }

    @discardableResult
    func addCategory(name: String, color: String, emoji: String? = nil, icon: String? = nil) -> Int64 {
        run("INSERT INTO categories (name, color, emoji, icon, position) VALUES (?, ?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM categories))",
            [.text(name), .text(color), .optText(emoji), .optText(icon)])
        changed()
        return sqlite3_last_insert_rowid(db)
    }

    func updateCategory(_ c: Topic) {
        run("UPDATE categories SET name = ?, color = ?, emoji = ?, icon = ?, icon_color = ? WHERE id = ?",
            [.text(c.name), .text(c.color), .optText(c.emoji), .optText(c.icon), .optText(c.iconColor), .int(c.id)])
        changed()
    }

    func deleteCategory(id: Int64) {
        run("DELETE FROM categories WHERE id = ?", [.int(id)])
        changed()
    }

    // MARK: Yapılacaklar

    func todos(day: String) -> [Todo] {
        var out: [Todo] = []
        query("SELECT id, day, title, detail, state, session_id FROM todos WHERE day = ? ORDER BY position, id", [.text(day)]) { s in
            out.append(todo(s))
        }
        return out
    }

    func todos(session: Int64) -> [Todo] {
        var out: [Todo] = []
        query("SELECT id, day, title, detail, state, session_id FROM todos WHERE session_id = ? ORDER BY position, id", [.int(session)]) { s in
            out.append(todo(s))
        }
        return out
    }

    private func todo(_ s: OpaquePointer) -> Todo {
        Todo(id: col(s, 0), day: str(s, 1), title: str(s, 2), detail: str(s, 3),
             state: TodoState(rawValue: Int(col(s, 4))) ?? .waiting, sessionID: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : col(s, 5))
    }

    @discardableResult
    func addTodo(day: String, title: String, detail: String) -> Int64 {
        run("INSERT INTO todos (day, title, detail, position) VALUES (?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM todos WHERE day = ?))",
            [.text(day), .text(title), .text(detail), .text(day)])
        changed()
        return sqlite3_last_insert_rowid(db)
    }

    func setTodoState(id: Int64, _ state: TodoState) {
        run("UPDATE todos SET state = ? WHERE id = ?", [.int(Int64(state.rawValue)), .int(id)])
        changed()
    }

    func attachTodo(id: Int64, session: Int64) {
        run("UPDATE todos SET session_id = ? WHERE id = ?", [.int(session), .int(id)])
        changed()
    }

    func deleteTodo(id: Int64) {
        run("DELETE FROM todos WHERE id = ?", [.int(id)])
        changed()
    }

    // MARK: Oturumlar

    func startSession(category: Int64, goal: String, work: Int, rest: Int, at start: Date = Date()) -> Int64 {
        run("INSERT INTO sessions (category_id, goal, work_min, rest_min, start) VALUES (?, ?, ?, ?, ?)",
            [.int(category), .text(goal), .int(Int64(work)), .int(Int64(rest)), .real(start.timeIntervalSince1970)])
        changed()
        return sqlite3_last_insert_rowid(db)
    }

    func finishSession(id: Int64, end: Date, focusSeconds: Int) {
        run("UPDATE sessions SET end = ?, focus_sec = ? WHERE id = ?", [.real(end.timeIntervalSince1970), .int(Int64(focusSeconds)), .int(id)])
        changed()
    }

    func setFocus(session: Int64, seconds: Int) {
        run("UPDATE sessions SET focus_sec = ? WHERE id = ?", [.int(Int64(seconds)), .int(session)])
    }

    func setNote(session: Int64, _ note: String) {
        run("UPDATE sessions SET note = ? WHERE id = ?", [.text(note), .int(session)])
    }

    /// Yanlış açılmış oturumun kategorisini, hedefini ve notunu sonradan düzeltir.
    func updateSession(id: Int64, category: Int64, goal: String, note: String) {
        run("UPDATE sessions SET category_id = ?, goal = ?, note = ? WHERE id = ?", [.int(category), .text(goal), .text(note), .int(id)])
        changed()
    }

    /// Oturumu siler; bağlı görevler günün listesinde kalır, yalnız oturumdan ayrılır.
    func deleteSession(id: Int64) {
        run("UPDATE todos SET session_id = NULL WHERE session_id = ?", [.int(id)])
        run("DELETE FROM sessions WHERE id = ?", [.int(id)])
        changed()
    }

    func markEmergency(session: Int64) {
        run("UPDATE sessions SET emergency = 1 WHERE id = ?", [.int(session)])
        changed()
    }

    /// [from, to) aralığında başlamış oturumlar, eskiden yeniye.
    func sessions(from: Date, to: Date) -> [Session] {
        var out: [Session] = []
        query("SELECT id, category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency FROM sessions WHERE start >= ? AND start < ? ORDER BY start",
              [.real(from.timeIntervalSince1970), .real(to.timeIntervalSince1970)]) { s in
            out.append(Session(id: col(s, 0), categoryID: col(s, 1), goal: str(s, 2), workMinutes: Int(col(s, 3)), restMinutes: Int(col(s, 4)),
                               start: Date(timeIntervalSince1970: sqlite3_column_double(s, 5)),
                               end: sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(s, 6)),
                               focusSeconds: Int(col(s, 7)), note: str(s, 8), emergency: col(s, 9) != 0))
        }
        return out
    }

    func lastSession() -> Session? {
        sessions(from: .distantPast, to: .distantFuture).last
    }

    // MARK: SQLite

    enum Value { case int(Int64), real(Double), text(String), optText(String?) }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { NSLog("Houra SQLite: %@", String(cString: sqlite3_errmsg(db))) }
    }

    private func prepare(_ sql: String, _ values: [Value]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("Houra SQLite: %@", String(cString: sqlite3_errmsg(db)))
            return nil
        }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, v) in values.enumerated() {
            let n = Int32(i + 1)
            switch v {
            case .int(let x): sqlite3_bind_int64(stmt, n, x)
            case .real(let x): sqlite3_bind_double(stmt, n, x)
            case .text(let x): sqlite3_bind_text(stmt, n, x, -1, transient)
            case .optText(let x): if let x { sqlite3_bind_text(stmt, n, x, -1, transient) } else { sqlite3_bind_null(stmt, n) }
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ values: [Value] = []) {
        guard let stmt = prepare(sql, values) else { return }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) != SQLITE_DONE { NSLog("Houra SQLite: %@", String(cString: sqlite3_errmsg(db))) }
    }

    private func query(_ sql: String, _ values: [Value] = [], row: (OpaquePointer) -> Void) {
        guard let stmt = prepare(sql, values) else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }
}

private func col(_ s: OpaquePointer, _ i: Int32) -> Int64 { sqlite3_column_int64(s, i) }
private func str(_ s: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
private func optStr(_ s: OpaquePointer, _ i: Int32) -> String? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : str(s, i) }
