// Houra (Windows): sistem tepsisinde duran odak zamanlayıcısı. Oturumlar, molalar, günün yapılacakları ve istatistikler; hepsi yerel.
//   --hidden   açılışta kendiliğinden başlarken panel açılmaz
//   --demo     HOURA_DB ile verilen veritabanına örnek veri yazar ve çıkar
//   HOURA_DB   başka bir veritabanı dosyası · HOURA_LANG=tr|en dili zorlar
const { app, BrowserWindow, Tray, Menu, ipcMain, screen, globalShortcut, nativeImage, dialog, shell } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const U = require('./shared/util');
const { Store } = require('./core/store');
const { Focus } = require('./core/focus');
const weekly = require('./core/weekly');
const { statsData } = require('./core/stats');
const { glyph, SIZE: GLYPH_SIZE } = require('./glyph');

const T = U.T;
const HOTKEY = 'Control+Alt+N';
const EXAMPLE_PATTERN = ['AA Daily', '* - {YYYY}', 'Hafta {WW}', 'Hafta {WW} - Yapılacaklar.md'].join(path.sep);

// Kurulu olmayan kopya (ve Windows dışındaki her çalıştırma) kendi klasörünü kullanır; Mac'te gerçek Houra'nın verisine dokunmaz.
if (!app.isPackaged || process.platform !== 'win32') app.setPath('userData', path.join(app.getPath('appData'), 'Houra-dev'));

let store, focus, tray, panel, newSession, stretch;
let settings = {};
let panelPage = 'today';
let newSessionInit = {};

// MARK: Ayarlar

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
function setSetting(key, value) {
  settings[key] = value;
  fs.writeFileSync(settingsFile(), JSON.stringify(settings, null, 2));
}
function applyLanguage() {
  const lang = process.env.HOURA_LANG ?? settings.language ?? 'system';
  U.setTurkish(lang === 'tr' || (lang !== 'en' && (app.getPreferredSystemLanguages()[0] ?? app.getLocale()).startsWith('tr')));
}
const weeklyOn = () => (settings.weeklyOn ?? true) && !!(settings.weeklyTemplate ?? '').trim();
const weeklyLoad = () => (weeklyOn() ? weekly.load(settings.weeklyTemplate, store.categories()) : null);

// MARK: Pencereler

const floating = { frame: false, transparent: true, backgroundColor: '#00000000', resizable: false, skipTaskbar: true, hasShadow: false,
  alwaysOnTop: true, fullscreenable: false, minimizable: false, maximizable: false, thickFrame: false };
const titleBar = { titleBarStyle: 'hidden', titleBarOverlay: { color: '#111111', symbolColor: '#f5f5f5', height: 40 } };

function open(view, options, query = {}) {
  const win = new BrowserWindow({ show: false, backgroundColor: '#0a0a0a', title: 'Houra', ...options,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), autoplayPolicy: 'no-user-gesture-required' } });
  // Windows, ölçekli ekranda pencereyi istenenden birkaç nokta büyük kurar; ölçü kurulduktan sonra bir kez daha verilir.
  const { x, y, width, height } = options;
  if (x != null && !options.fullscreen) win.setBounds({ x, y, width, height });
  win.loadFile(path.join(__dirname, 'ui', view + '.html'), { query });
  return win;
}
const alive = (win) => win && !win.isDestroyed();
function broadcast(channel, ...args) {
  for (const win of BrowserWindow.getAllWindows()) if (alive(win)) win.webContents.send(channel, ...args);
}
const contains = (r, p) => p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
const inflate = (r, d) => ({ x: r.x - d, y: r.y - d, width: r.width + 2 * d, height: r.height + 2 * d });
const clamp = (v, lo, hi) => Math.min(Math.max(lo, v), Math.max(lo, hi));
const round = (r) => ({ x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) });

/** Pencereyi hedef çerçeveye yumuşakça taşır. */
function glide(win, target, ms = 320) {
  const from = win.getBounds(), began = Date.now();
  const timer = setInterval(() => {
    if (!alive(win)) return clearInterval(timer);
    const t = Math.min(1, (Date.now() - began) / ms), k = 1 - Math.pow(1 - t, 3);
    win.setBounds(round({ x: from.x + (target.x - from.x) * k, y: from.y + (target.y - from.y) * k,
      width: from.width + (target.width - from.width) * k, height: from.height + (target.height - from.height) * k }));
    if (t === 1) clearInterval(timer);
  }, 16);
}

function showPanel(page) {
  if (page) panelPage = page;
  if (alive(panel)) {
    if (page) panel.webContents.send('page', page);
    if (panel.isMinimized()) panel.restore();
    panel.show(); panel.focus();
    return;
  }
  panel = open('panel', { width: 1120, height: 740, minWidth: 940, minHeight: 620, ...titleBar, ...(settings.panelBounds ?? {}) });
  panel.once('ready-to-show', () => panel.show());
  panel.on('close', () => setSetting('panelBounds', panel.getBounds()));
}

function showNewSession(preselect = null) {
  if (focus.phase === 'rest') return focus.endRest(false);   // mola bitince pencere yeniden açılır
  if (alive(newSession)) newSession.destroy();
  newSessionInit = { preselect };
  const work = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  newSession = open('newsession', { ...floating, width: 580, height: 700,
    x: Math.round(work.x + (work.width - 580) / 2), y: Math.round(work.y + (work.height - 700) / 2) });
  newSession.setAlwaysOnTop(true, 'floating');
  const win = newSession;
  win.once('ready-to-show', () => { win.show(); win.focus(); });
}

/** Moladan bağımsız esneme penceresi; her açılışta ilk hareketten başlar. */
function showStretch() {
  if (alive(stretch)) stretch.destroy();
  stretch = open('rest', { width: 640, height: 820, resizable: false, maximizable: false, backgroundColor: '#000000', ...titleBar,
    titleBarOverlay: { ...titleBar.titleBarOverlay, color: '#000000' } }, { stretch: '1' });
  const win = stretch;
  win.once('ready-to-show', () => win.show());
}

// MARK: Ekrandaki görünümler (etiket, ince şerit, kapsül, kart, halka) ve ayrıntı paneli

const SHADOW = 36;   // gölge pencerenin kenarında kesilmesin diye görünümün çevresinde bırakılan boşluk
const widget = { win: null, detail: null, size: [0, 0], rects: [], over: false, overTimer: null, detailOpen: false, nudging: false, typing: false, drag: null, openTimer: null, watchTimer: null, outsideSince: 0 };
const widgetStyle = () => settings.widgetStyle ?? 'tag';
const snapsToEdge = () => widgetStyle() === 'tag' || widgetStyle() === 'strip';
const shadowPad = () => (widgetStyle() === 'strip' ? 0 : SHADOW);
const onLeft = () => !!settings.widgetLeft;
const workOf = (bounds) => screen.getDisplayMatching(bounds).workArea;
const visibleCompact = () => inflate(widget.win.getBounds(), -shadowPad());
const widgetConfig = () => ({ style: widgetStyle(), onLeft: onLeft(), detailOpen: widget.detailOpen, nudging: widget.nudging });
const pushWidget = () => { if (alive(widget.win)) widget.win.webContents.send('widget', widgetConfig()); };

function compactSize(work) {
  const p = 2 * shadowPad();
  return { tag: [300 + p, 92 + p], strip: [260, work.height], capsule: [372 + p, 96 + p], card: [250 + p, 290 + p], ring: [116 + p, 116 + p] }[widgetStyle()];
}
function nudgeSize(work) {
  const [w, h] = compactSize(work), style = widgetStyle();
  return style === 'strip' || style === 'card' ? [w, h] : [Math.max(w, 270 + 2 * SHADOW), 186 + 2 * SHADOW];
}

function restoredBounds([width, height]) {
  const work = screen.getPrimaryDisplay().workArea, pad = shadowPad(), style = widgetStyle();
  const edgeX = onLeft() ? work.x : work.x + work.width - width;
  if (style === 'strip') return { x: edgeX, y: work.y, width, height };
  if (style === 'tag') {
    const y = (settings.tagY ?? work.y + 208) - pad;
    return { x: edgeX, y: clamp(y, work.y - pad, work.y + work.height - height + pad), width, height };
  }
  const saved = settings['pos.' + style];
  if (saved && screen.getAllDisplays().some((d) => contains(d.bounds, { x: saved.x + 20, y: saved.y + 20 }))) return { x: saved.x - pad, y: saved.y - pad, width, height };
  return { x: work.x + work.width - width - 30 + pad, y: work.y + 30 - pad, width, height };
}

function teardownWidget() {
  closeDetail();
  clearTimeout(widget.openTimer);
  clearInterval(widget.overTimer);
  for (const key of ['win', 'detail']) { if (alive(widget[key])) widget[key].destroy(); widget[key] = null; }
  Object.assign(widget, { nudging: false, drag: null, typing: false, rects: [], over: false });
}

function buildWidget() {
  teardownWidget();
  if (widgetStyle() === 'none' || (focus.phase !== 'focus' && focus.phase !== 'paused')) return;
  widget.size = compactSize(screen.getPrimaryDisplay().workArea);
  const win = open('widget', { ...floating, focusable: false, ...round(restoredBounds(widget.size)) });
  win.setAlwaysOnTop(true, 'floating');
  win.setIgnoreMouseEvents(true);   // saydam yerler tıklamayı alttaki pencereye bırakır
  win.once('ready-to-show', () => win.showInactive());
  widget.win = win;
  // Pencere fareyi yalnız imleç görünümün kendisinin (pencerenin bildirdiği dikdörtgenlerin) üzerindeyken tutar.
  // İmleç buradan izlenir: tıklamayı bırakan pencereye fare olayı iletmek Windows'ta güvenilir çalışmıyor.
  widget.overTimer = setInterval(() => {
    if (!alive(win) || widget.drag) return;
    const b = win.getBounds(), m = screen.getCursorScreenPoint();
    const over = widget.rects.some(([x, y, w, h]) => contains({ x: b.x + x, y: b.y + y, width: w, height: h }, m));
    if (over === widget.over) return;
    widget.over = over;
    win.setIgnoreMouseEvents(!over);
    hoverWidget(over);
  }, 60);
  widget.detail = open('detail', { ...floating, width: 360, height: 400 });   // üzerine gelince hemen açılsın diye hazır bekler
  widget.detail.setAlwaysOnTop(true, 'floating');
}

function hoverWidget(inside) {
  clearTimeout(widget.openTimer);
  if (!inside || widget.detailOpen || widget.nudging || widget.drag) return;
  widget.openTimer = setTimeout(() => {
    if (!alive(widget.detail) || widget.detailOpen) return;
    const vertical = widgetStyle() === 'strip';
    widget.detail.webContents.send('prepare', { vertical, edgeLeft: snapsToEdge() ? onLeft() : null });   // boyunu ölçüp detail.ready ile döner
  }, 300);
}

function placeDetail(contentHeight) {
  if (!alive(widget.win) || !alive(widget.detail) || widget.detailOpen) return;
  const style = widgetStyle(), vertical = style === 'strip';
  const work = workOf(widget.win.getBounds()), c = visibleCompact();
  const width = vertical ? 380 : 360, height = vertical ? work.height : Math.min(Math.ceil(contentHeight), work.height - 24);
  const edgeX = onLeft() ? work.x : work.x + work.width - width;
  let x = edgeX, y = c.y - 40;
  if (vertical) y = work.y;
  else if (style !== 'tag') x = c.x + c.width / 2 < work.x + work.width / 2 ? c.x + c.width + 12 : c.x - width - 12;
  if (!vertical) y = clamp(y, work.y + 8, work.y + work.height - height - 8);
  widget.detail.setBounds(round({ x: clamp(x, work.x, work.x + work.width - width), y, width, height }));
  widget.detail.showInactive();
  widget.detailOpen = true;
  pushWidget();
  // Fare iki pencerenin de dışında kalınca kapat
  widget.outsideSince = 0;
  clearInterval(widget.watchTimer);
  widget.watchTimer = setInterval(() => {
    if (!alive(widget.win) || !alive(widget.detail)) return closeDetail();
    const m = screen.getCursorScreenPoint();
    const inside = contains(inflate(widget.detail.getBounds(), 8), m) || contains(inflate(visibleCompact(), 4), m);
    if (inside || (widget.typing && widget.detail.isFocused())) { widget.outsideSince = 0; return; }
    widget.outsideSince ||= Date.now();
    if (Date.now() - widget.outsideSince > 280) closeDetail();
  }, 100);
}

function closeDetail() {
  clearInterval(widget.watchTimer);
  if (!widget.detailOpen) return;
  widget.detailOpen = false; widget.typing = false;
  const detail = widget.detail;
  if (alive(detail)) {
    detail.webContents.send('hide');
    setTimeout(() => { if (alive(detail) && !widget.detailOpen) detail.hide(); }, 220);
  }
  pushWidget();
}

/** Üst kenarı ve yapıştığı yanı yerinde tutarak boyutu değiştirir. */
function resizeCompact([width, height]) {
  if (!alive(widget.win)) return;
  const f = widget.win.getBounds(), work = workOf(f);
  const right = snapsToEdge() ? !onLeft() : f.x + f.width / 2 > work.x + work.width / 2;
  widget.size = [width, height];
  widget.win.setBounds(round({ x: right ? f.x + f.width - width : f.x, y: f.y, width, height }));
}

/** Serbest oturumda 50 dakika dolunca görünümün kendisi mola sorusuna döner; Devam et ile eski haline gelir. */
function setNudge(on) {
  if (!alive(widget.win)) return;
  if (on) closeDetail();
  widget.nudging = on;
  const work = workOf(widget.win.getBounds());
  resizeCompact(on ? nudgeSize(work) : compactSize(work));
  pushWidget();
}

function dragWidget() {
  if (!alive(widget.win) || widget.nudging) return;
  clearTimeout(widget.openTimer);
  if (widget.detailOpen) closeDetail();
  const m = screen.getCursorScreenPoint();
  widget.drag ??= { m, b: widget.win.getBounds() };
  const { m: o, b } = widget.drag;
  // Boyut pencereden okunmaz: ölçekli ekranda okunan değer her seferinde bir iki nokta büyür.
  widget.win.setBounds({ x: b.x + m.x - o.x, y: widgetStyle() === 'strip' ? b.y : b.y + m.y - o.y, width: widget.size[0], height: widget.size[1] });
}

/** Etiket ve şerit bırakılınca en yakın kenara (sol ya da sağ) yapışır; ötekilerin yeri hatırlanır. */
function dropWidget() {
  if (!alive(widget.win) || !widget.drag) return;
  widget.drag = null;
  const f = { ...widget.win.getBounds(), width: widget.size[0], height: widget.size[1] }, work = workOf(f), pad = shadowPad(), style = widgetStyle();
  if (!snapsToEdge()) return setSetting('pos.' + style, { x: f.x + pad, y: f.y + pad });
  setSetting('widgetLeft', f.x + f.width / 2 < work.x + work.width / 2);
  const height = style === 'strip' ? work.height : f.height;
  const target = { x: onLeft() ? work.x : work.x + work.width - f.width, width: f.width, height,
    y: style === 'strip' ? work.y : clamp(f.y, work.y - pad, work.y + work.height - height + pad) };
  if (style === 'tag') setSetting('tagY', target.y + pad);
  widget.size = [target.width, target.height];
  glide(widget.win, target);
  pushWidget();
}

/** Bütün ekranlar üç kez beyaz yanıp söner ve çan çalar; tıklamaları engellemez. */
function pulseScreens() {
  screen.getAllDisplays().forEach((display, i) => {
    const win = open('pulse', { ...floating, focusable: false, ...display.bounds }, i === 0 ? { sound: '1' } : {});
    win.setAlwaysOnTop(true, 'screen-saver');
    win.setIgnoreMouseEvents(true);
    win.once('ready-to-show', () => win.showInactive());
    setTimeout(() => { if (alive(win)) win.destroy(); }, 4500);   // çanın sönümü bitsin
  });
}

// MARK: Mola ekranı

let restWindows = [];

/** Bütün ekranları kaplar; yalnız 1,5 sn basılı tutulan "Acil durum" ile erken dönülür. */
function showRest() {
  if (restWindows.length) return;
  const active = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const mine = [];
  for (const display of screen.getAllDisplays()) {
    // Tam ekran: Windows, pencereyi çalışma alanına sığdırıp görev çubuğunu açıkta bırakmasın.
    const win = open('rest', { ...floating, transparent: false, backgroundColor: '#000000', movable: false, ...display.bounds, fullscreenable: true, fullscreen: true },
      display.id === active.id ? { content: '1' } : {});
    win.setAlwaysOnTop(true, 'screen-saver');
    win.once('ready-to-show', () => { win.show(); if (display.id === active.id) win.focus(); });
    win.on('close', (e) => { if (restWindows.includes(win)) e.preventDefault(); });   // Alt+F4 molayı kapatmasın
    // Başka bir pencereye geçilirse mola ekranı öne döner.
    win.on('blur', () => setTimeout(() => {
      if (restWindows.includes(win) && !restWindows.some((w) => alive(w) && w.isFocused())) { win.moveTop(); win.focus(); }
    }, 200));
    mine.push(win);
  }
  restWindows = mine;
}

function hideRest() {
  const closing = restWindows;
  restWindows = [];
  for (const win of closing) {
    if (!alive(win)) continue;
    win.webContents.send('fadeout');
    setTimeout(() => { if (alive(win)) win.destroy(); }, 600);
  }
}

// MARK: Tepsi

let lastGlyph = '', lastTip = '';

function refreshTray() {
  if (!tray) return;
  const phase = focus.phase === 'paused' ? 'focus' : focus.phase;
  const key = phase + Math.round(focus.progress * 60);
  if (key !== lastGlyph) {
    lastGlyph = key;
    tray.setImage(nativeImage.createFromBitmap(glyph(phase, focus.progress), { width: GLYPH_SIZE, height: GLYPH_SIZE, scaleFactor: 2 }));
  }
  const tip = focus.phase === 'idle' ? 'Houra'
    : focus.phase === 'rest' ? T(`Mola · ${U.formatClock(focus.restRemaining)}`, `Break · ${U.formatClock(focus.restRemaining)}`)
    : `${focus.topic?.name ?? ''} · ${U.formatClock(focus.clock)}`;
  if (tip !== lastTip) { lastTip = tip; tray.setToolTip(tip); }
}

const header = (label) => ({ label, enabled: false });
const swatch = (hex) => {
  const v = parseInt(hex.replace('#', ''), 16) || 0, px = Buffer.alloc(12 * 12 * 4);
  for (let i = 0; i < px.length; i += 4) px.set([v & 255, (v >> 8) & 255, (v >> 16) & 255, 255], i);
  return nativeImage.createFromBitmap(px, { width: 12, height: 12 });
};

function recentMenu() {
  const topics = new Map(store.categories().map((t) => [t.id, t])), seen = new Set(), items = [];
  for (const s of store.sessions(U.nowSec() - 30 * 86400).reverse()) {
    const topic = topics.get(s.categoryID), key = `${s.categoryID}|${s.goal}|${s.workMinutes}`;
    if (!topic || seen.has(key)) continue;
    seen.add(key);
    items.push({ label: `${topic.name} · ${s.goal}  (${U.rhythm(s)})`, icon: swatch(topic.color),
      click: () => focus.start({ topic, goal: s.goal, work: s.workMinutes, rest: s.restMinutes }) });
    if (items.length === 5) break;
  }
  return items.length ? items : [header(T('Henüz oturum yok', 'No sessions yet'))];
}

function trayMenu() {
  const items = [];
  if (focus.phase === 'idle') {
    const today = store.sessions(U.startOfDay(U.nowSec())), todos = store.todos(U.dayKey(U.nowSec()));
    const minutes = U.formatMinutes(U.sum(today, U.sessionMinutes)), done = todos.filter((t) => t.state === 2).length;
    items.push(header(T(`Bugün ${minutes} odak`, `Today ${minutes} focused`)),
      header(T(`${today.length} oturum · ${done} / ${todos.length} görev 🥳`, `${today.length} sessions · ${done} / ${todos.length} tasks 🥳`)),
      { type: 'separator' },
      { label: T('Oturum başlat…', 'Start session…'), accelerator: HOTKEY, click: () => showNewSession() },
      { label: T('Son oturumu tekrarla', 'Repeat a recent session'), submenu: recentMenu() });
  } else if (focus.phase === 'rest') {
    items.push(header(T(`Mola · ${U.formatClock(focus.restRemaining)}`, `Break · ${U.formatClock(focus.restRemaining)}`)),
      { type: 'separator' },
      { label: T('Molaya geri dön', 'Back to break'), click: showRest },
      { label: T('Molayı bitir, yeni oturum…', 'End break, new session…'), click: () => focus.endRest(false) });
  } else {
    const active = focus.activeTodo;
    items.push(header(`● ${focus.topic?.name ?? ''} · ${focus.session.goal}`),
      header((focus.isFree ? T(`serbest · ${U.formatClock(focus.clock)}`, `free · ${U.formatClock(focus.clock)}`)
        : T(`${U.formatClock(focus.remaining)} kaldı`, `${U.formatClock(focus.remaining)} left`)) + (active ? T(' · şu an: ', ' · now: ') + active.title : '')),
      { type: 'separator' },
      focus.phase === 'focus' ? { label: T('Duraklat', 'Pause'), click: () => focus.pause() } : { label: T('Devam et', 'Resume'), click: () => focus.resume() },
      { label: T('Oturumu bitir', 'Finish session'), click: () => focus.finish() });
  }
  const styles = [['tag', T('Etiket', 'Tag')], ['strip', T('İnce şerit', 'Thin strip')], ['capsule', T('Kapsül', 'Capsule')],
    ['card', T('Kart', 'Card')], ['ring', T('Halka', 'Ring')], ['none', T('Hiçbiri', 'None')]];
  items.push({ type: 'separator' },
    { label: T('Ekranda göster', 'Show on screen'), submenu: styles.map(([id, label]) => ({ label, type: 'radio', checked: widgetStyle() === id, click: () => api['settings.set']('widgetStyle', id) })) },
    { label: T('Paneli aç…', 'Open panel…'), click: () => showPanel() },
    { label: T('Esneme hareketleri…', 'Stretches…'), click: showStretch },
    { type: 'separator' },
    { label: T('Açılışta başlat', 'Launch at login'), type: 'checkbox', enabled: app.isPackaged, checked: app.getLoginItemSettings().openAtLogin,
      click: (item) => api['settings.set']('login', item.checked) },
    { label: T('Ayarlar…', 'Settings…'), click: () => showPanel('settings') },
    { label: T("Houra'dan çık", 'Quit Houra'), click: () => app.quit() });
  return Menu.buildFromTemplate(items);
}

// MARK: Pencerelerin çağırdığı işler

const today = () => U.dayKey(U.nowSec());
const withTodos = (sessions) => sessions.map((s) => ({ ...s, todos: store.sessionTodos(s.id) }));

const api = {
  state: () => focus.snapshot(),
  categories: () => store.categories(),
  addCategory: () => store.addCategory({ name: T('Yeni kategori', 'New category'), color: U.palette[store.categories().length % U.palette.length] }),
  updateCategory: (c) => store.updateCategory(c),
  deleteCategory: (id) => store.deleteCategory(id),
  todos: () => store.todos(today()),
  addTodo: (title, detail) => store.addTodo(today(), title, detail),
  setTodoState: (id, state) => store.setTodoState(id, state),
  deleteTodo: (id) => store.deleteTodo(id),
  sessions: (from, to) => withTodos(store.sessions(from ?? undefined, to ?? undefined).filter((s) => s.end != null)),
  deleteSession: (id) => store.deleteSession(id),
  /** Süren oturumda kategori ve hedef motorda da değişir; bitmiş oturumda not da kaydedilir. */
  editSession(id, topicID, goal, note) {
    const topic = store.categories().find((t) => t.id === topicID);
    if (!topic) return;   // silinmiş kategori: önce yenisi seçilmeli
    if (id === focus.session?.id) focus.retag(topic, goal.trim());
    else store.updateSession(id, topic.id, goal.trim() || topic.name, note);
  },
  weekly: weeklyLoad,
  stats: (from, to, filter) => statsData(store, from, to, filter),

  'focus.pause': () => focus.pause(),
  'focus.resume': () => focus.resume(),
  'focus.finish': () => focus.finish(),
  'focus.emergencyExit': () => focus.emergencyExit(),
  'focus.setNote': (text) => focus.setNote(text),
  'focus.setTodo': (id, state) => focus.setTodo(id, state),

  'widget.config': widgetConfig,
  'widget.rects': (rects) => { widget.rects = rects; },
  'widget.drag': dragWidget,
  'widget.drop': dropWidget,
  'widget.endNudge': () => setNudge(false),
  'detail.ready': placeDetail,
  'detail.typing': (on) => { widget.typing = on; },

  'newSession.show': (preselect) => showNewSession(preselect),
  'newSession.init': () => ({ ...newSessionInit, topics: store.categories(), last: store.lastSession(), lastTopic: settings.lastTopic,
    work: settings.rhythmWork ?? 50, weekly: weeklyLoad()?.tasks ?? [], hotkey: HOTKEY.replaceAll('+', ' + ').replace('Control', 'Ctrl'),
    waiting: store.todos(today()).filter((t) => t.state !== 2 && t.sessionID == null) }),
  /** Yeni oturumu başlatır; repeat verilirse bir önceki oturum aynı kategori, hedef ve ritimle tekrarlanır. */
  'newSession.begin'({ topicID, goal, todoIDs, newTodos, work, repeat }) {
    const last = repeat ? store.lastSession() : null;
    const topic = store.categories().find((t) => t.id === (last ? last.categoryID : topicID));
    if (!topic) return;
    if (last) work = last.workMinutes;
    setSetting('lastTopic', topic.id); setSetting('rhythmWork', work);
    focus.start(last ? { topic, goal: last.goal, work, rest: last.restMinutes } : { topic, goal: goal.trim(), todoIDs, newTodos, work, rest: work === 25 ? 5 : 10 });
    if (alive(newSession)) newSession.destroy();
  },

  'panel.page': () => panelPage,
  'stretch.show': showStretch,
  /** Pencere içeriğinin boyuna oturur (yeni oturum penceresi). */
  'window.fit'(height) {
    const win = this, b = win.getBounds(), work = workOf(b), h = Math.min(Math.ceil(height), work.height);
    win.setBounds({ x: Math.round(work.x + (work.width - 580) / 2), y: Math.round(clamp(work.y + (work.height - h) / 2 - 40, work.y, work.y + work.height - h)), width: 580, height: h });
  },
  'window.close'() { this.destroy(); },

  'settings.get': () => ({ language: settings.language ?? 'system', widgetStyle: widgetStyle(), weeklyOn: settings.weeklyOn ?? true,
    weeklyTemplate: settings.weeklyTemplate ?? '', examplePattern: EXAMPLE_PATTERN, login: app.getLoginItemSettings().openAtLogin, loginAvailable: app.isPackaged,
    dbPath: store.path, version: app.getVersion() }),
  'settings.set'(key, value) {
    if (key === 'login') return app.setLoginItemSettings({ openAtLogin: !!value, args: ['--hidden'] });
    if (!['language', 'widgetStyle', 'weeklyOn', 'weeklyTemplate'].includes(key)) return;
    setSetting(key, value);
    if (key === 'language') { applyLanguage(); broadcast('reload'); }   // bütün metinler yeniden kurulur
    else if (key === 'widgetStyle') buildWidget();
    else broadcast('store');
  },
  'settings.weeklyStatus'() {
    const template = (settings.weeklyTemplate ?? '').trim();
    if (!(settings.weeklyOn ?? true)) return T('Kapalı. Yol saklanır, açınca kaldığı yerden okunur.', 'Off. The path is kept for when you turn it back on.');
    if (!template) return T('Yol verilmedi.', 'No path set.');
    const found = weekly.load(template, store.categories());
    if (!found.file) return T('Bu haftanın dosyası bulunamadı.', "This week's file wasn't found.");
    return T(`Bu hafta: ${path.basename(found.file)} · ${found.tasks.length} açık görev`, `This week: ${path.basename(found.file)} · ${found.tasks.length} open tasks`);
  },
  async 'settings.chooseVault'() {
    const picked = await dialog.showOpenDialog(this, { properties: ['openDirectory'], buttonLabel: T('Seç', 'Choose') });
    if (picked.canceled) return null;
    setSetting('weeklyTemplate', path.join(picked.filePaths[0], EXAMPLE_PATTERN));
    broadcast('store');
    return settings.weeklyTemplate;
  },
  'settings.showData': () => shell.showItemInFolder(store.path),
  async 'settings.exportCSV'() {
    const picked = await dialog.showSaveDialog(this, { defaultPath: 'houra.csv', filters: [{ name: 'CSV', extensions: ['csv'] }] });
    if (picked.canceled) return;
    const topics = new Map(store.categories().map((t) => [t.id, t.name]));
    const q = (s) => `"${String(s).replaceAll('"', '""')}"`, iso = (s) => new Date(s * 1000).toISOString().replace('.000Z', 'Z');
    const rows = store.sessions().map((s) => [iso(s.start), s.end ? iso(s.end) : '', q(topics.get(s.categoryID) ?? ''), q(s.goal),
      s.workMinutes, s.restMinutes, U.sessionMinutes(s), s.emergency ? 1 : 0, q(s.note)].join(','));
    try { fs.writeFileSync(picked.filePath, ['start,end,category,goal,work_min,rest_min,focus_min,emergency,note', ...rows].join('\n')); }
    catch (error) { dialog.showErrorBox('Houra', error.message); }
  },
};

// MARK: Açılış

function boot() {
  try { settings = JSON.parse(fs.readFileSync(settingsFile(), 'utf8')); } catch { settings = {}; }
  applyLanguage();
  fs.mkdirSync(app.getPath('userData'), { recursive: true });

  let storeDirty = false;
  store = new Store(process.env.HOURA_DB ?? path.join(app.getPath('userData'), 'houra.sqlite'), {
    defaultCategory: T('Genel', 'General'),
    onChange() {   // art arda gelen yazmalar pencerelere tek haber olarak gider
      if (storeDirty) return;
      storeDirty = true;
      setImmediate(() => { storeDirty = false; broadcast('store'); });
    },
  });
  if (process.argv.includes('--demo')) { require('./core/demo').seed(store); console.log('demo verisi yazıldı:', store.path); return app.quit(); }

  focus = new Focus(store, {
    onChange() {
      const active = focus.phase === 'focus' || focus.phase === 'paused';
      if (active && !alive(widget.win)) buildWidget();
      if (!active && alive(widget.win)) teardownWidget();
      broadcast('state', focus.snapshot());
      refreshTray();
    },
    onRestStart: showRest,
    onEmergency: hideRest,
    onRestEnd() { hideRest(); showNewSession(); },
    onBreakNudge() { pulseScreens(); setNudge(true); },
  });
  setInterval(() => {
    focus.tick();
    if (focus.phase !== 'idle') { broadcast('state', focus.snapshot()); refreshTray(); }
  }, 500);

  const stretchDir = pathToFileURL(app.isPackaged ? path.join(process.resourcesPath, 'Stretches') : path.join(__dirname, '..', '..', 'Stretches')).href;
  ipcMain.on('boot', (e) => { e.returnValue = { turkish: U.isTurkish(), stretchDir }; });
  ipcMain.handle('call', (e, name, ...args) => {
    if (!Object.hasOwn(api, name)) throw new Error('bilinmeyen çağrı: ' + name);
    return api[name].apply(BrowserWindow.fromWebContents(e.sender), args);
  });

  if (process.platform === 'win32') Menu.setApplicationMenu(null);
  tray = new Tray(nativeImage.createEmpty());
  refreshTray();
  const popUp = () => tray.popUpContextMenu(trayMenu());
  tray.on('click', popUp);
  tray.on('right-click', popUp);
  tray.on('double-click', () => showPanel());
  globalShortcut.register(HOTKEY, () => showNewSession());
  for (const event of ['display-added', 'display-removed', 'display-metrics-changed']) screen.on(event, () => { if (alive(widget.win)) buildWidget(); });

  if (process.argv.includes('--new')) showNewSession();
  else if (!process.argv.includes('--hidden')) showPanel();   // elle açıldıysa panel görünür; tepsi simgesi gizli kalabilir
  // Geliştirme araçları: pencere görüntüleri (her yerde) ve gerçek masaüstü sınaması (Windows)
  const tools = { app, focus, store, widget, api, showPanel, showNewSession, showStretch, hoverWidget, setNudge, setSetting, buildWidget, pulseScreens,
    getTray: () => tray, getSettings: () => settings };
  if (!app.isPackaged && process.env.HOURA_SHOTS) require('../scripts/shots')(tools);
  if (!app.isPackaged && process.env.HOURA_CHECK) require('../scripts/wincheck')(tools);
}

if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => showPanel());
  app.on('window-all-closed', () => {});   // pencere kalmasa da tepside yaşar
  app.on('before-quit', () => { restWindows = []; if (focus?.phase === 'focus' || focus?.phase === 'paused') focus.stop(); });
  app.whenReady().then(boot);
}
