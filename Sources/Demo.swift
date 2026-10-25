import Foundation

// Ekran görüntüleri ve README için iki aylık örnek veri. Yalnız --demo ile, HOURA_DB'deki veritabanına yazılır.

enum Demo {
    static func seed(_ store: Store) {
        let existing = store.categories()
        let cats: [Int64] = [
            store.addCategory(name: T("Müşteri işi", "Client work"), color: "#e5675c", icon: "briefcase"),
            store.addCategory(name: T("Video", "Video"), color: "#e6b450", emoji: "🎬"),
            store.addCategory(name: T("Tez", "Thesis"), color: "#9a7bea", icon: "brain"),
            store.addCategory(name: T("Kişisel", "Personal"), color: "#4fbf95", icon: "leaf"),
        ]
        existing.forEach { store.deleteCategory(id: $0.id) }

        let goals = [
            [T("Brief'i incele", "Review the brief"), T("Sunum taslağı", "Deck outline"), T("Teklif metni", "Proposal copy")],
            [T("Kaba kurgu", "Rough cut"), T("Altyazı", "Subtitles"), T("Kapak tasarımı", "Thumbnail")],
            [T("Literatür taraması", "Literature review"), T("Etik formu", "Ethics form"), T("Analiz betiği", "Analysis script")],
            [T("Faturalar", "Bills"), T("Okuma", "Reading"), T("Planlama", "Planning")],
        ]
        let tasks: [[(String, String)]] = [
            [(T("Hedef kitleyi işaretle", "Mark the target audience"), T("Brief'in ikinci sayfası", "Second page of the brief")),
             (T("Rakip sunumlara bak", "Look at competitor decks"), T("En az üç örnek", "At least three examples")),
             (T("Sorulacakları yaz", "Write down open questions"), ""), (T("Teklifi gönder", "Send the proposal"), "")],
            [(T("Kaba kurgu", "Rough cut"), T("Açılış 3 saniyede", "Hook in the first 3 seconds")), (T("Altyazıları yerleştir", "Place the subtitles"), T("Tek satır", "Single line")),
             (T("Sesi temizle", "Clean up the audio"), ""), (T("Kapak görseli", "Thumbnail"), T("İki seçenek", "Two options"))],
            [(T("Üç makale oku", "Read three papers"), T("Notları al", "Take notes")), (T("Yöntem bölümünü yaz", "Draft the methods section"), ""),
             (T("Analiz betiğini düzelt", "Fix the analysis script"), T("Eksik veriler", "Missing values")), (T("Danışmana e-posta", "Email my supervisor"), "")],
            [(T("Faturaları öde", "Pay the bills"), ""), (T("Haftayı planla", "Plan the week"), T("Üç öncelik", "Three priorities")),
             (T("20 sayfa oku", "Read 20 pages"), ""), (T("Spor", "Workout"), "")],
        ]
        var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
        let cal = Calendar.current, today = cal.startOfDay(for: Date())

        for back in stride(from: 70, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            if back > 0 && rnd() < 0.18 { continue }          // boş günler
            var t = day.addingTimeInterval(TimeInterval((8 * 60 + Int(rnd() * 90)) * 60))
            let count = back == 0 ? 3 : 2 + Int(rnd() * 5)
            for i in 0..<count {
                let k = Int(rnd() * 4)
                let long = rnd() < 0.65
                let work = long ? 50 : 25, rest = long ? 10 : 5
                if back == 0 && t.addingTimeInterval(TimeInterval(work * 60)) > Date() { break }
                let id = store.startSession(category: cats[k], goal: goals[k][Int(rnd() * 3)], work: work, rest: rest, at: t)
                let focus = rnd() < 0.15 ? Int(Double(work * 60) * (0.5 + rnd() * 0.4)) : work * 60
                store.finishSession(id: id, end: t.addingTimeInterval(TimeInterval(focus)), focusSeconds: focus)
                if rnd() < 0.35 { store.setNote(session: id, T("Açılış hala uzun; soruyla başlamayı dene.", "The intro is still long; try opening with a question.")) }
                if rnd() < 0.08 { store.markEmergency(session: id) }
                let dk = dayKey(day)
                for j in 0..<(1 + Int(rnd() * 3)) {
                    let pick = tasks[k][(i * 2 + j + back) % tasks[k].count]
                    let todo = store.addTodo(day: dk, title: pick.0, detail: pick.1)
                    store.attachTodo(id: todo, session: id)
                    store.setTodoState(id: todo, rnd() < 0.8 ? .done : .waiting)
                }
                t = t.addingTimeInterval(TimeInterval((work + rest) * 60) + (rnd() < 0.4 ? rnd() * 5400 : 0))
            }
        }
        let dk = dayKey(today)
        store.addTodo(day: dk, title: T("Rakip sunumlara bak", "Look at competitor decks"), detail: T("En az üç örnek", "At least three examples"))
        store.addTodo(day: dk, title: T("Sorulacakları not al", "Write down questions"), detail: "")
        store.addTodo(day: dk, title: T("Gün 15 altyazısı", "Day 15 subtitles"), detail: T("Tek satır", "Single line"))
    }
}
