import AppKit
import ServiceManagement

// Houra: menü çubuğunda duran odak zamanlayıcısı. Oturumlar, molalar, günün yapılacakları ve istatistikler; hepsi yerel.
//   Houra --selftest   → veri katmanını ve ikon çözümleyicisini geçici bir veritabanında sınar
//   Houra --demo       → HOURA_DB ile verilen veritabanına iki aylık örnek veri yazar (ekran görüntüleri için)

if CommandLine.arguments.contains("--selftest") {
    let path = NSTemporaryDirectory() + "houra-selftest-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = Store(path: path)
    precondition(store.categories().count == 1, "ilk açılışta bir kategori")
    let cat = store.addCategory(name: "Test", color: "#e5675c", icon: "brain")
    let today = dayKey(Date())
    let a = store.addTodo(day: today, title: "Bir", detail: "açıklama")
    store.addTodo(day: today, title: "İki", detail: "")
    precondition(store.todos(day: today).count == 2, "günün listesi")
    let s = store.startSession(category: cat, goal: "Hedef", work: 25, rest: 5)
    store.attachTodo(id: a, session: s)
    store.setTodoState(id: a, .done)
    store.finishSession(id: s, end: Date(), focusSeconds: 1500)
    let sessions = store.sessions(from: Date().addingTimeInterval(-60), to: Date().addingTimeInterval(60))
    precondition(sessions.count == 1 && sessions[0].minutes == 25, "oturum kaydı")
    precondition(store.todos(session: s).first?.state == .done, "oturumun görevi")
    precondition(TodoState.done.next == .waiting, "durum döngüsü")
    for entry in iconLibrary {
        let box = SVGPath.parse(entry.path).boundingBoxOfPath
        precondition(box.width > 40 && box.width < 260 && box.height > 40 && box.height < 260, "ikon sınırları: \(entry.name) \(box)")
    }
    precondition(iconLibrary.count == 100, "100 ikon")
    precondition(lightness("#000000") < 1 && lightness("#ffffff") > 99, "açıklık")
    print("selftest: tamam")
    exit(0)
}

// Houra --login on|off   → açılışta başlatmayı terminalden açar ya da kapatır
if let i = CommandLine.arguments.firstIndex(of: "--login"), i + 1 < CommandLine.arguments.count {
    do {
        if CommandLine.arguments[i + 1] == "on" { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        print("açılışta başlat: \(SMAppService.mainApp.status == .enabled ? "açık" : "kapalı")")
        exit(0)
    } catch {
        FileHandle.standardError.write("açılış ayarı değiştirilemedi: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}

if CommandLine.arguments.contains("--demo") {
    Demo.seed(Store.shared)
    print("demo verisi yazıldı: \(Store.shared.path)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
