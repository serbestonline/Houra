// Veri katmanı, oturum motoru, haftalık not ayrıştırıcısı ve biçimlendirme: node --test test/
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const U = require('../src/shared/util');
const { Store } = require('../src/core/store');
const { Focus } = require('../src/core/focus');
const weekly = require('../src/core/weekly');
const { statsData } = require('../src/core/stats');
const { glyph } = require('../src/glyph');

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'houra-test-'));
test.after(() => fs.rmSync(tmp, { recursive: true, force: true }));
const newStore = (name) => new Store(path.join(tmp, name + '.sqlite'));

test('kayıt: kategori, görev, oturum, düzenleme, serbest, silme', () => {
  const store = newStore('store');
  assert.equal(store.categories().length, 1);
  const cat = store.addCategory({ name: 'Test', color: '#e5675c', icon: 'brain' });
  const now = U.nowSec(), today = U.dayKey(now);
  const a = store.addTodo(today, 'Bir', 'açıklama');
  store.addTodo(today, 'İki');
  assert.equal(store.todos(today).length, 2);
  const s = store.startSession(cat, 'Hedef', 25, 5);
  store.attachTodo(a, s); store.setTodoState(a, 2);
  store.finishSession(s, now, 1500);
  let rows = store.sessions(now - 60, now + 60);
  assert.equal(rows.length, 1);
  assert.equal(U.sessionMinutes(rows[0]), 25);
  assert.equal(store.sessionTodos(s)[0].state, 2);
  store.updateSession(s, 1, 'Düzeltildi', 'not');
  const edited = store.sessions(now - 60, now + 60)[0];
  assert.deepEqual([edited.categoryID, edited.goal, edited.note, U.sessionMinutes(edited)], [1, 'Düzeltildi', 'not', 25]);
  const free = store.startSession(cat, 'Serbest', 0, 10);
  store.setFocus(free, 4200);
  const freeRow = store.lastSession();
  assert.deepEqual([freeRow.id, U.sessionMinutes(freeRow), freeRow.end], [free, 70, null]);
  assert.notEqual(U.rhythm(freeRow), '0 + 10');
  store.deleteSession(s);
  assert.deepEqual(store.sessions(now - 60, now + 60).map((x) => x.id), [free]);
  assert.equal(store.todos(today).find((t) => t.id === a).sessionID, null);
  const first = store.categories()[0];
  store.updateCategory({ ...first, iconColor: '#123456' });
  assert.equal(store.categories()[0].iconColor, '#123456');
  store.close();
});

test('motor: sayaç, duraklatma, mola, acil durum', () => {
  const store = newStore('focus');
  let now = 1_800_000_000;
  const seen = [];
  const focus = new Focus(store, { onRestStart: () => seen.push('rest'), onRestEnd: (e) => seen.push('end:' + e), onEmergency: () => seen.push('emergency') }, () => now);
  const topic = store.categories()[0];
  const todo = store.addTodo(U.dayKey(now), 'Var olan');
  focus.start({ topic, goal: '', todoIDs: [todo], newTodos: [['Yeni', 'ayrıntı']], work: 25, rest: 5 });
  assert.equal(focus.session.goal, topic.name);
  assert.deepEqual(focus.todos.map((t) => t.state), [1, 0]);
  assert.equal(focus.snapshot().headline, 'Var olan');
  now += 600; focus.pause(); now += 300; focus.resume();
  assert.equal(focus.remaining, 15 * 60);
  assert.equal(focus.plannedEnd, focus.session.start + 1500 + 300);
  focus.setTodo(focus.todos[1].id, 1);
  assert.deepEqual(focus.todos.map((t) => t.state), [0, 1]);
  now += 900; focus.tick();
  assert.equal(focus.phase, 'rest');
  assert.equal(U.sessionMinutes(store.lastSession()), 25);
  focus.emergencyExit();
  assert.equal(focus.phase, 'rest');
  assert.equal(store.lastSession().emergency, true);
  now += 300; focus.tick();
  assert.equal(focus.phase, 'idle');
  assert.deepEqual(seen, ['rest', 'emergency', 'end:false']);
  store.close();
});

test('motor: serbest oturum ileri sayar, 50. dakikada hatırlatır; yarım kalan oturum kapanır', () => {
  const store = newStore('free');
  let now = 1_800_000_000, nudges = 0;
  const focus = new Focus(store, { onBreakNudge: () => nudges++ }, () => now);
  focus.start({ topic: store.categories()[0], goal: 'Serbest', work: 0, rest: 10 });
  now += 49 * 60; focus.tick();
  assert.deepEqual([nudges, focus.clock, focus.plannedEnd], [0, 49 * 60, null]);
  now += 60; focus.tick(); focus.tick();
  assert.equal(nudges, 1);
  assert.equal(store.lastSession().focusSeconds, 3000);
  now += 600;   // uygulama burada kapanmış gibi: yeni motor yarım oturumu son kaydedilen süreyle kapatır
  new Focus(store, {}, () => now);
  assert.deepEqual([store.lastSession().end, store.lastSession().focusSeconds], [focus.session.start + 3000, 3000]);
  store.close();
});

test('haftalık not: ayrıştırma, alt görev, eşleştirme, Windows satır sonu', () => {
  const note = '##### Labra\r\n- [ ] #labra Siteyi gez → [[Demo]]\r\n- [x] #labra Bitti ✅ 2026-10-20\n##### Maestrock\n- 1.0\n\t- [ ] #maestrock Sunum\n- [w] #maestrock Bekleyen [[Kişi|Ali]]\n- [ ] #maestrock Taşındı → Hafta 44\n\t- 22.10: not';
  const topics = [{ id: 1, name: 'Genel' }, { id: 99, name: 'Maestrocks' }];
  const week = weekly.parse(note, topics);
  assert.deepEqual(week.map((t) => t.title), ['Siteyi gez', 'Sunum', 'Bekleyen Ali']);
  assert.deepEqual([week[1].detail, week[1].topicID, week[2].waiting], ['1.0', 99, true]);
  assert.deepEqual(week.map((t) => t.depth), [0, 1, 0]);
});

test('haftalık not: şablon bugünün haftasına çözülür, * klasörü eşler', () => {
  const at = new Date(2026, 10, 9, 12).getTime() / 1000;   // 9 Kasım 2026, ISO hafta 46
  assert.deepEqual(U.isoWeek(at), { year: 2026, week: 46 });
  assert.deepEqual(U.isoWeek(new Date(2027, 0, 1, 12).getTime() / 1000), { year: 2026, week: 53 });
  const dir = path.join(tmp, 'vault', 'AA Daily', '11 - 2026', 'Hafta 46');
  fs.mkdirSync(dir, { recursive: true });
  const target = path.join(dir, 'Hafta 46 - Yapılacaklar.md');
  fs.writeFileSync(target, '- [ ] Görev');
  const template = path.join(tmp, 'vault', 'AA Daily', '* - {YYYY}', 'Hafta {WW}', 'Hafta {WW} - Yapılacaklar.md');
  assert.equal(weekly.file(template, at), target);
  assert.equal(weekly.file(template, at + 7 * 86400), null);
  assert.equal(weekly.file('göreli/yol.md', at), null);
});

test('biçimlendirme ve takvim', () => {
  assert.ok(U.lightness('#000000') < 1 && U.lightness('#ffffff') > 99);
  assert.equal(U.inkOn('#e9e9ee'), '#000000');
  assert.equal(U.formatClock(2052), '34:12');
  U.setTurkish(true);
  assert.deepEqual([U.formatMinutes(95), U.formatMinutesShort(95), U.percent(22)], ['1 sa 35 dk', '1s 35d', '%22']);
  U.setTurkish(false);
  assert.deepEqual([U.formatMinutes(95), U.formatMinutes(35), U.percent(22)], ['1 h 35 min', '35 min', '22%']);
  // Yaz saatinden çıkılan gün 25 saat sürer; gün eklemek yine gece yarısına düşmeli.
  const day = new Date(2026, 9, 24).getTime() / 1000;
  assert.equal(U.dayKey(U.addDays(day, 2)), '2026-10-26');
  assert.equal(new Date(U.addDays(day, 2) * 1000).getHours(), 0);
  assert.equal(U.dayKey(U.mondayOf(new Date(2026, 10, 15, 18).getTime() / 1000)), '2026-11-09');
});

test('istatistik: toplamlar, önceki dönem, saatler', () => {
  const store = newStore('stats');
  const cat = store.categories()[0].id, other = store.addCategory({ name: 'Öteki', color: '#000000' });
  const monday = U.mondayOf(U.nowSec() - 14 * 86400);
  const add = (day, hour, minutes, c) => { const t = U.addDays(monday, day) + hour * 3600; store.finishSession(store.startSession(c, 'x', 50, 10, t), t + minutes * 60, minutes * 60); };
  add(0, 9, 50, cat); add(0, 11, 30, other); add(2, 9, 50, cat); add(-3, 9, 40, cat);
  const data = statsData(store, monday, U.addDays(monday, 6));
  assert.deepEqual([data.days.length, data.total, data.previousTotal, data.elapsedDays], [7, 130, 40, 7]);
  assert.deepEqual(data.bestDay, { day: monday, minutes: 80 });
  assert.deepEqual([data.peakHour, data.hourMinutes[9], data.hourMinutes[11]], [9, 100, 30]);
  assert.equal(statsData(store, monday, U.addDays(monday, 6), other).total, 30);
  store.close();
});

test('ikonlar ve tepsi simgesi', () => {
  const icons = require('../src/shared/icons');
  assert.equal(icons.length, 100);
  assert.ok(icons.every(([name, d]) => name && /^m/i.test(d)));
  const idle = glyph('idle', 0), half = glyph('focus', 0.5);
  assert.equal(idle.length, 32 * 32 * 4);
  assert.notDeepEqual(idle, half);
});
