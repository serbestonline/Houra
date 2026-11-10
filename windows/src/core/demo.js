// Deneme ve ekran görüntüleri için on haftalık örnek veri. Yalnız --demo ile, HOURA_DB'deki veritabanına yazılır.
const U = require('../shared/util');

function seed(store) {
  const T = U.T, existing = store.categories();
  const cats = [
    store.addCategory({ name: T('Müşteri işi', 'Client work'), color: '#e5675c', icon: 'briefcase' }),
    store.addCategory({ name: T('Video', 'Video'), color: '#e6b450', emoji: '🎬' }),
    store.addCategory({ name: T('Tez', 'Thesis'), color: '#9a7bea', icon: 'brain' }),
    store.addCategory({ name: T('Kişisel', 'Personal'), color: '#4fbf95', icon: 'leaf' }),
  ];
  existing.forEach((c) => store.deleteCategory(c.id));
  const goals = [
    [T("Brief'i incele", 'Review the brief'), T('Sunum taslağı', 'Deck outline')],
    [T('Kaba kurgu', 'Rough cut'), T('Altyazı', 'Subtitles')],
    [T('Literatür taraması', 'Literature review'), T('Analiz betiği', 'Analysis script')],
    [T('Faturalar', 'Bills'), T('Okuma', 'Reading')],
  ];
  let x = 42;
  const rnd = () => { x = (x * 1103515245 + 12345) % 2147483648; return x / 2147483648; };
  const today = U.startOfDay(U.nowSec());
  for (let back = 70; back >= 0; back--) {
    if (back > 0 && rnd() < 0.18) continue;   // boş günler
    let t = U.addDays(today, -back) + (8 * 60 + Math.floor(rnd() * 90)) * 60;
    for (let i = 0, n = 2 + Math.floor(rnd() * 5); i < n; i++) {
      const c = Math.floor(rnd() * 4), work = rnd() < 0.15 ? 0 : rnd() < 0.7 ? 50 : 25;
      const focus = work === 0 ? (30 + Math.floor(rnd() * 60)) * 60 : work * 60;
      if (t + focus > U.nowSec()) break;
      const id = store.startSession(cats[c], goals[c][Math.floor(rnd() * 2)], work, work === 25 ? 5 : 10, t);
      if (rnd() < 0.5) { const todo = store.addTodo(U.dayKey(t), goals[c][0], ''); store.attachTodo(todo, id); store.setTodoState(todo, rnd() < 0.7 ? 2 : 0); }
      if (rnd() < 0.2) store.setNote(id, T('Yarın kaldığım yerden devam.', 'Pick this up tomorrow.'));
      store.finishSession(id, t + focus, focus);
      if (rnd() < 0.06) store.markEmergency(id);
      t += focus + (10 + Math.floor(rnd() * 50)) * 60;
    }
  }
}

module.exports = { seed };
