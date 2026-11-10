// Uygulama paneli: Bugün, İstatistik, Oturumlar, Kategoriler, Ayarlar. Tepsi menüsünden ya da simgeye çift tıklayınca açılır.
const root = document.getElementById('page');
let page = 'today';
let focusState = null;
let drawing = 0;

const pages = { today: todayPage, stats: statsPage, sessions: sessionsPage, categories: categoriesPage, settings: settingsPage };

/** Sayfayı baştan kurar; veri her değiştiğinde çağrılır. */
async function render() {
  const turn = ++drawing;
  drawSidebar();
  const node = await pages[page]();
  if (turn === drawing) mount(root, node);   // bu sırada yeni bir çizim başladıysa eskisi atılır
}

function go(next) { page = next; root.replaceChildren(); render(); }

function drawSidebar() {
  const nav = (id, icon, title) => h('button.nav', { class: page === id ? 'on' : '', onclick: () => go(id) }, glyph(icon), title);
  document.getElementById('sidebar').replaceChildren(
    nav('today', 'clock', T('Bugün', 'Today')),
    nav('stats', 'chart', T('İstatistik', 'Statistics')),
    nav('sessions', 'list', T('Oturumlar', 'Sessions')),
    nav('categories', 'grid', T('Kategoriler', 'Categories')),
    h('button.nav', { onclick: () => call('stretch.show') }, glyph('stretch'), T('Esneme hareketleri', 'Stretches')),
    h('div.spacer'),
    nav('settings', 'gear', T('Ayarlar', 'Settings')),
    h('button.new-btn', { onclick: () => call('newSession.show') }, h('span.plus', null, glyph('plus', 12, 2)), T('Yeni oturum', 'New session'), h('kbd', null, 'Ctrl Alt N')));
}

/** Sayfa başlığı: küçük üst yazı ve büyük ince başlık. */
const pageHeader = (over, title, trailing) => h('div.page-header', null, h('div', null, eyebrow(over), h('h1', null, title)), trailing);
const card = (...kids) => h('div.card', null, kids);
const statCard = (title, value, detail) => h('div.card.stat', null, eyebrow(title), h('div.value', null, value), h('div.detail', null, detail));
const scroll = (...kids) => h('div.scroll', null, kids);
const empty = (text) => h('div.empty', null, text);

// MARK: Bugün

async function todayPage() {
  const now = nowSec();
  const [sessions, todos, cats, week] = await Promise.all([call('sessions', startOfDay(now)), call('todos'), call('categories'), call('weekly')]);
  const topics = Object.fromEntries(cats.map((t) => [t.id, t]));
  const done = todos.filter((t) => t.state === 2).length, fifty = sessions.filter((s) => s.workMinutes === 50).length;
  const focusMin = formatMinutes(sum(sessions, sessionMinutes));

  const title = field({ placeholder: T('Görev başlığı', 'Task title'), keep: 'todo-title', onSubmit: add });
  const detail = field({ placeholder: T('Açıklama (isteğe bağlı) · Enter ile ekle', 'Details (optional) · Enter to add'), size: 12, keep: 'todo-detail', onSubmit: add });
  function add() {
    const t = title.value.trim(), d = detail.value.trim();
    if (!t) return;
    title.value = ''; detail.value = '';
    call('addTodo', t, d);
  }

  return scroll(
    pageHeader(T('Bugün', 'Today') + ' · ' + formatDate(now, 'dMMMMEEEE'), T(`${focusMin} odak`, `${focusMin} focused`)),
    h('div.grid4', null,
      statCard(T('Oturum', 'Sessions'), sessions.length, T(`${fifty} tanesi 50 + 10`, `${fifty} of them 50 + 10`)),
      statCard(T('Mola', 'Breaks'), formatMinutes(sum(sessions, (s) => s.restMinutes)), T(`${sessions.length} mola`, `${sessions.length} breaks`)),
      statCard(T('Görev', 'Tasks'), `${done} / ${todos.length}`, T('tamamlandı 🥳', 'done 🥳')),
      statCard(T('Acil durum', 'Emergency'), sessions.filter((s) => s.emergency).length, T('moladan erken dönüş', 'early returns from a break')),
      h('div.span2.stack', null,
        card(
          h('div.row', null, eyebrow(T('Bugün yapılacaklar', "Today's to-do")), h('div.spacer'), h('span.note', null, `${done} / ${todos.length}`)),
          h('div.todo-list', null, todos.length === 0 && empty(T('Bugün için liste boş.', "Nothing on today's list.")), todos.map(dayTodoRow)),
          title, detail),
        week && weekCard(week, cats, new Set(todos.map((t) => t.title)))),
      h('div.card.span2', null, eyebrow(T('Gün akışı', 'Day flow')),
        sessions.length === 0 && !focusState?.session ? h('div.empty.top', null, T('Bugün henüz oturum yok.', 'No sessions yet today.'))
          : h('div.top', null, dayColumn(sessions, topics, focusState)))));
}

function dayTodoRow(todo) {
  return h('div.todo-row', { class: ['', 'doing', 'done'][todo.state] },
    h('button.state-btn', { onclick: () => call('setTodoState', todo.id, (todo.state + 1) % 3) }, todoEmoji[todo.state]),
    h('div.text', null, h('div.title', null, todo.title), todo.detail && h('div.sub', null, todo.detail)),
    iconButton('x', () => call('deleteTodo', todo.id), '', 'on-hover'));
}

/** Haftalık nottaki açık görevler, proje proje. Bir göreve tıklayınca o görev seçili yeni oturum açılır. */
function weekCard(week, cats, todayTitles) {
  const groups = new Map();
  for (const task of week.tasks) {
    const heading = task.heading || T('Diğer', 'Other');
    if (!groups.has(heading)) groups.set(heading, []);
    groups.get(heading).push(task);
  }
  return card(
    h('div.row', null, eyebrow(T("Bu hafta Obsidian'da", 'This week in Obsidian')), h('div.spacer'),
      h('span.note', null, week.file ? `${week.name} · ${T(`${week.tasks.length} açık görev`, `${week.tasks.length} open tasks`)}` : T('haftalık not bulunamadı', 'weekly note not found'))),
    [...groups].map(([heading, tasks]) => {
      const topic = cats.find((t) => t.id === tasks[0].topicID);
      return h('div.week-group', null,
        h('div.row.gap8.week-head', null, topic && swatch(topic, 16), h('b', null, heading), h('span.faint', null, tasks.length)),
        tasks.map((task, i) => [
          startsSubgroup(tasks, i) && h('div.subgroup', null, task.detail),
          weekTaskRow(task, todayTitles.has(task.title)),
        ]));
    }));
}

/** Alt görev, üst görevi hemen üstünde listelenmiyorsa üst görevin adı ayrı bir satırda gösterilir. */
function startsSubgroup(list, i) {
  if (list[i].depth === 0) return false;
  if (i === 0) return true;
  const prev = list[i - 1];
  return prev.depth === 0 ? prev.title !== list[i].detail : prev.detail !== list[i].detail;
}

function weekTaskRow(task, inToday) {
  // Görev bugünün listesine kopyalanır; Obsidian'daki haftalık not yalnız okunur, değişmez.
  const toToday = h('button.icon-btn.to-today', { class: inToday ? 'there' : 'on-hover', disabled: inToday,
    title: inToday ? T('Bugünün listesinde', "On today's list") : T('Bugünün listesine al', "Add to today's list"),
    onclick: (e) => { e.stopPropagation(); call('addTodo', task.title, task.detail); } }, glyph(inToday ? 'check' : 'down', 11, 1.8));
  return h('div.week-task', { class: (task.waiting ? 'waiting ' : '') + (task.depth > 0 ? 'sub' : ''), title: T('Bu görevle oturum başlat', 'Start a session with this task'),
    onclick: () => call('newSession.show', task) },
    h('i.circle'),
    h('div.text', null, h('div', null, task.title), task.waiting && h('small', null, T('bekleniyor', 'waiting'))),
    toToday, h('span.on-hover.play', null, glyph('play', 9)));
}

// MARK: Oturumlar

const sessionsView = { topic: null, notesOnly: false, open: new Set(), editing: null };

async function sessionsPage() {
  const v = sessionsView;
  const [all, cats] = await Promise.all([call('sessions', nowSec() - 90 * 86400), call('categories')]);
  const byID = Object.fromEntries(cats.map((t) => [t.id, t]));
  const days = new Map();
  for (const s of all.filter((x) => (v.topic == null || x.categoryID === v.topic) && (!v.notesOnly || x.note)).reverse()) {
    const day = startOfDay(s.start);
    if (!days.has(day)) days.set(day, []);
    days.get(day).push(s);
  }
  return scroll(
    pageHeader(T('Oturumlar', 'Sessions'), T('Geçmiş', 'History'),
      segmented([T('Tümü', 'All'), T('Notlu', 'With notes')], v.notesOnly ? 1 : 0, (i) => { v.notesOnly = i === 1; render(); })),
    h('div.chips.filters', null, chip(T('Tüm kategoriler', 'All categories'), null, v.topic == null, () => { v.topic = null; render(); }),
      cats.map((t) => chip(t.name, t, v.topic === t.id, () => { v.topic = t.id; render(); }))),
    days.size === 0 && empty(T('Bu filtreye uyan oturum yok.', 'No sessions match this filter.')),
    [...days].map(([day, list]) => h('div.day', null,
      h('div.day-head', null, h('span', null, formatDate(day, 'dMMMMEEEE')), h('span', null, formatMinutes(sum(list, sessionMinutes)))),
      list.map((s) => sessionRow(s, byID[s.categoryID], cats)))));
}

function sessionRow(session, topic, cats) {
  const v = sessionsView, open = v.open.has(session.id), editing = v.editing === session.id;
  const done = session.todos.filter((t) => t.state === 2).length;
  const meta = `${formatTime(session.start)} – ${formatTime(session.end)} · ${rhythm(session)}`
    + (session.todos.length ? T(` · ${done}/${session.todos.length} görev`, ` · ${done}/${session.todos.length} tasks`) : '')
    + (session.note ? ' · 📝' : '') + (session.emergency ? T(' · acil durum', ' · emergency') : '');
  const toggle = () => { if (open) { v.open.delete(session.id); v.editing = null; } else v.open.add(session.id); render(); };
  const remove = () => {
    if (confirm(T('Bu oturum silinsin mi? Süresi istatistiklerden düşer; görevleri günün listesinde kalır.',
      "Delete this session? Its time leaves the stats; its tasks stay on the day's list."))) call('deleteSession', session.id);
  };
  return h('div.session', { class: open ? 'open' : '' },
    h('div.head', { onclick: toggle },
      topic && swatch(topic, 16),
      h('div.text', null, h('div.name', null, `${topic?.name ?? ''} · ${session.goal}`), h('div.meta', null, meta)),
      iconButton('pencil', () => { v.editing = session.id; v.open.add(session.id); render(); }, T('Kategoriyi, hedefi ve notu düzenle', 'Edit category, goal and notes'), editing ? '' : 'on-hover'),
      iconButton('trash', remove, T('Oturumu sil', 'Delete session'), 'on-hover'),
      h('div.minutes', null, formatMinutes(sessionMinutes(session)))),
    open && editing && h('div.body', null, sessionEditor(session, cats, { done: () => { v.editing = null; render(); } })),
    open && !editing && h('div.body', null,
      session.todos.map((t) => h('div.row.gap10.top-align', null, h('span', null, todoEmoji[t.state]),
        h('div', null, h('div', { class: t.state === 2 ? 'faint' : '' }, t.title), t.detail && h('small.muted', null, t.detail)))),
      session.note && h('div.note-box', null, session.note),
      !session.todos.length && !session.note && h('small.faint', null, T('Liste ve not yok.', 'No list and no notes.'))));
}

// MARK: Kategoriler

const EMOJIS = '🎬 🎥 ✍️ 📝 📚 📖 🎓 🧠 🔬 🧪 🧬 💡 🎯 🚀 💼 🤝 📈 📊 💰 🏦 🛒 🏠 🚗 ✈️ 🏋️ 🏃 🧘 🕌 🤲 ☕ 🍳 🎮 🎸 🎧 🎨 📷 💻 ⌨️ 🖥️ 📱 🌍 🗣️ 📞 ✉️ 🗓️ ⏰ 🔥 ⭐ ❤️ 🌱 🐾 👶'.split(' ');
const INK_COLOURS = ['#ffffff', '#000000', ...palette.filter((c) => c !== '#e9e9ee' && c !== '#3a3f4d')];
let picker = null;   // { id, tab, query }: rengi, emojisi ya da ikonu seçilen kategori

document.addEventListener('click', (e) => {
  if (picker && !e.target.closest('.popover, .swatch-btn')) { picker = null; render(); }
});

async function categoriesPage() {
  const [cats, sessions] = await Promise.all([call('categories'), call('sessions', 0)]);
  return scroll(
    pageHeader(T('Kategoriler', 'Categories'), T('Renkler ve adlar', 'Colours and names'),
      h('div', { style: { width: '130px' } }, button('secondary', T('+ Kategori', '+ Category'), () => call('addCategory')))),
    cats.map((topic) => {
      const mine = sessions.filter((s) => s.categoryID === topic.id);
      const save = (e) => { const n = e.target.value.trim(); if (n && n !== topic.name) call('updateCategory', { ...topic, name: n }); };
      return h('div.cat-row', null,
        h('button.swatch-btn', { title: T('Renk, emoji ya da ikon', 'Colour, emoji or icon'),
          onclick: () => { picker = picker?.id === topic.id ? null : { id: topic.id, tab: 0, query: '' }; render(); } }, swatch(topic, 36)),
        h('input.cat-name', { value: topic.name, 'data-keep': 'cat-' + topic.id, spellcheck: 'false', onblur: save, onkeydown: (e) => { if (e.key === 'Enter') e.target.blur(); } }),
        h('span.note', null, T(`${mine.length} oturum · ${formatMinutes(sum(mine, sessionMinutes))}`, `${mine.length} sessions · ${formatMinutes(sum(mine, sessionMinutes))}`)),
        cats.length > 1 && iconButton('trash', () => {
          if (confirm(T(`${topic.name} silinsin mi? Oturumları kayıtta kalır ama kategorisiz görünür.`, `Delete ${topic.name}? Its sessions stay recorded but show without a category.`))) call('deleteCategory', topic.id);
        }, '', 'on-hover'),
        picker?.id === topic.id && symbolPicker(topic));
    }));
}

/** Kategorinin rengi, emojisi ya da ikonu. */
function symbolPicker(topic) {
  const update = (change) => call('updateCategory', { ...topic, ...change });
  const dots = (colours, current, pick) => h('div.dots', null,
    colours.map((hex) => h('button.dot', { class: hex === current ? 'on' : '', onclick: () => pick(hex) }, h('i', { style: { background: hex } }))),
    // Paletin sonundaki gökkuşağı daire: sistemin renk seçicisini açar.
    h('label.dot.custom', { class: current && !colours.includes(current) ? 'on' : '', title: T('Özel renk', 'Custom colour') },
      h('i', null, current && !colours.includes(current) && h('b', { style: { background: current } })),
      h('input', { type: 'color', value: current ?? '#ffffff', onchange: (e) => pick(e.target.value) })));
  const grid = (items, selected, cell, choose, tall) => h('div.pick-grid', { class: tall ? 'tall' : '' },
    items.map((item) => h('button', { class: item && item === selected ? 'on' : '', onclick: () => choose(item) }, item ? cell(item) : '∅')));

  let body;
  if (picker.tab === 0) {
    body = [dots(palette, topic.color, (hex) => update({ color: hex })), h('small.faint', null, topic.color.toUpperCase())];
  } else if (picker.tab === 1) {
    const typed = field({ placeholder: T('Bir emoji yaz ya da yapıştır (Win + .)', 'Type or paste an emoji (Win + .)'), size: 13, keep: 'emoji-typed',
      onSubmit: () => { const first = [...new Intl.Segmenter().segment(typed.value)][0]?.segment; if (first) update({ emoji: first, icon: null }); } });
    body = [typed, grid(['', ...EMOJIS], topic.emoji, (e) => e, (e) => update({ emoji: e || null, icon: null }), true)];
  } else {
    const q = picker.query.toLocaleLowerCase(locale());
    const names = ['', ...ICONS.filter(([name, , keywords]) => !q || name.includes(q) || keywords.includes(q)).map(([name]) => name)];
    body = [
      field({ placeholder: T('İkon ara: kitap, kamera, beyin…', 'Search icons: book, camera, brain…'), size: 13, keep: 'icon-query', value: picker.query,
        onInput: (v) => { picker.query = v; render(); } }),
      grid(names, topic.icon, (n) => categoryIcon(n, 18, 'rgba(255,255,255,.85)'), (n) => update({ icon: n || null, emoji: null })),
      h('div.row', null, eyebrow(T('İkon rengi', 'Icon colour')), h('div.spacer'), swatch(topic, 22)),
      dots(INK_COLOURS, topic.iconColor, (hex) => update({ iconColor: hex })),
      h('small.faint', null, T('Phosphor ikonları · MIT lisansı', 'Phosphor icons · MIT licence'))];
  }
  return h('div.popover', null,
    segmented([T('Renk', 'Colour'), 'Emoji', T('İkon', 'Icon')], picker.tab, (i) => { picker.tab = i; render(); }), body);
}

// MARK: Ayarlar

const STYLES = () => [['tag', T('Etiket', 'Tag')], ['strip', T('İnce şerit', 'Thin strip')], ['capsule', T('Kapsül', 'Capsule')],
  ['card', T('Kart', 'Card')], ['ring', T('Halka', 'Ring')], ['none', T('Hiçbiri', 'None')]];

async function settingsPage() {
  const [s, weeklyStatus] = await Promise.all([call('settings.get'), call('settings.weeklyStatus')]);
  const set = (key, value) => call('settings.set', key, value).then(render);
  const toggle = (on, change, disabled) => h('input.switch', { type: 'checkbox', checked: on, disabled, onchange: (e) => change(e.target.checked) });
  const settingRow = (title, control) => h('div.card.row', null, h('span.setting', null, title), h('div.spacer'), control);
  const languages = ['system', 'tr', 'en'], styles = STYLES();
  return scroll(
    pageHeader(T('Ayarlar', 'Settings'), 'Houra'),
    h('div.stack', null,
      settingRow(T('Dil', 'Language'), segmented([T('Sistem', 'System'), 'Türkçe', 'English'], languages.indexOf(s.language), (i) => set('language', languages[i]))),
      settingRow(T('Ekranda göster', 'Show on screen'), segmented(styles.map((x) => x[1]), styles.findIndex((x) => x[0] === s.widgetStyle), (i) => set('widgetStyle', styles[i][0]))),
      settingRow(T('Açılışta başlat', 'Launch at login') + (s.loginAvailable ? '' : T(' (kurulu sürümde)', ' (in the installed app)')),
        toggle(s.login, (on) => set('login', on), !s.loginAvailable)),
      card(
        h('div.row', null, h('span.setting', null, T('Haftalık görevler', 'Weekly tasks')), h('div.spacer'), toggle(s.weeklyOn, (on) => set('weeklyOn', on))),
        h('p.muted', null, T('Obsidian\'daki haftalık notun gibi bir Markdown dosyasındaki açık görevler Bugün sayfasında "Bu hafta" kartında ve yeni oturum penceresinde "Haftanın listesi" olarak görünür. Dosya yalnız okunur. Yol her açılışta bugünün tarihiyle çözülür: {YYYY} yıl, {WW} hafta, {MM} ay, * herhangi bir klasör.',
          'Open tasks from a Markdown file, such as your weekly note in Obsidian, show up in a "This week" card on the Today page and as "This week\'s list" in the new session window. The file is only read. The path is resolved with today\'s date every time: {YYYY} year, {WW} week, {MM} month, * any folder.')),
        h('div.stack10', { class: s.weeklyOn ? '' : 'disabled' },
          field({ placeholder: 'C:\\Users\\…\\Vault\\' + s.examplePattern, value: s.weeklyTemplate, size: 12, keep: 'weekly-template', onInput: (v) => call('settings.set', 'weeklyTemplate', v) }),
          h('div', { style: { width: '200px' } }, button('secondary', T('Kasa klasörünü seç…', 'Choose vault folder…'), async () => {
            const template = await call('settings.chooseVault');
            if (template) { root.querySelector('[data-keep="weekly-template"]').value = template; render(); }
          })),
          h('small.faint', null, weeklyStatus))),
      card(eyebrow(T('Veriler', 'Data')),
        h('p.muted', null, T('Bütün oturumlar, görevler ve notlar yalnız bu bilgisayarda, yerel bir SQLite dosyasında durur.', 'All sessions, tasks and notes stay on this computer, in a local SQLite file.')),
        h('p.path', null, s.dbPath),
        h('div.row.gap8', null,
          h('div', { style: { width: '170px' } }, button('secondary', T('Klasörde göster', 'Show in folder'), () => call('settings.showData'))),
          h('div', { style: { width: '200px' } }, button('secondary', T('CSV olarak dışa aktar…', 'Export as CSV…'), () => call('settings.exportCSV'))))),
      h('small.faint', null, 'Houra ' + s.version)));
}

// MARK: Olaylar

houra.on('store', render);
houra.on('page', go);
houra.on('state', (s) => {
  const changed = s.phase !== focusState?.phase || s.session?.id !== focusState?.session?.id || s.session?.goal !== focusState?.session?.goal;
  focusState = s;
  if (changed && page === 'today') render();
});
setInterval(() => { if (page === 'today') render(); }, 20_000);   // Obsidian'daki değişiklikler ve şu an çizgisi

(async () => {
  focusState = await call('state');
  page = await call('panel.page');
  render();
})();
