// Bütün pencerelerin ortak parçaları: öğe kurucu, simgeler, kategori karesi, alanlar, günün dikey çizelgesi.
// Arayüz siyah-beyazdır; renk yalnız İstatistik'te ve kategori işaretlerinde kullanılır.
setTurkish(houra.boot.turkish);
document.documentElement.lang = isTurkish() ? 'tr' : 'en';
houra.on('reload', () => location.reload());   // dil değişti
const call = houra.call;
const query = new URLSearchParams(location.search);

/** h('div.card.big', { onclick, style: { top: '4px' } }, çocuklar…) */
function h(tag, attrs, ...kids) {
  const [name, ...classes] = tag.split('.');
  return fill(document.createElement(name || 'div'), classes, attrs, kids);
}
function svg(tag, attrs, ...kids) {
  return fill(document.createElementNS('http://www.w3.org/2000/svg', tag), [], attrs, kids);
}
function fill(el, classes, attrs, kids) {
  if (classes.length) el.setAttribute('class', classes.join(' '));
  for (const [key, value] of Object.entries(attrs ?? {})) {
    if (value == null || value === false) continue;
    if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
    else if (key === 'style' && typeof value === 'object') Object.assign(el.style, value);
    else if (key === 'class') value.split(' ').filter(Boolean).forEach((c) => el.classList.add(c));
    else if (key === 'value') el.value = value;
    else el.setAttribute(key, value === true ? '' : value);
  }
  el.append(...kids.flat(Infinity).filter((k) => k != null && k !== false));
  return el;
}
const px = (n) => n + 'px';

/**
 * Sayfayı yeniden kurar; data-keep taşıyan alanların yazısı, odağı ve sayfanın kaydırması korunur
 * (başka bir pencerede veri değişince yarım yazılmış bir görev başlığı silinmesin).
 */
function mount(root, node) {
  const kept = new Map(), scroller = root.querySelector('.scroll'), top = scroller?.scrollTop ?? 0;
  const active = document.activeElement?.dataset?.keep;
  for (const el of root.querySelectorAll('[data-keep]')) kept.set(el.dataset.keep, [el.value, el.selectionStart, el.selectionEnd]);
  root.replaceChildren(node);
  for (const el of root.querySelectorAll('[data-keep]')) {
    const was = kept.get(el.dataset.keep);
    if (!was) continue;
    el.value = was[0];
    if (el.dataset.keep === active) { el.focus(); try { el.setSelectionRange(was[1], was[2]); } catch { /* seçimi olmayan alan */ } }
  }
  const next = root.querySelector('.scroll');
  if (next) next.scrollTop = top;
}

// MARK: Simgeler

const GLYPHS = {
  clock: '<circle cx="8" cy="8" r="6"/><path d="M8 4.6V8l2.4 1.5"/>',
  chart: '<path d="M3 13.5V9M8 13.5v-11M13 13.5V6"/>',
  list: '<path d="M5.5 4h8M5.5 8h8M5.5 12h8M2.5 4h.01M2.5 8h.01M2.5 12h.01"/>',
  grid: '<rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="9" y="2.5" width="4.5" height="4.5" rx="1"/><rect x="2.5" y="9" width="4.5" height="4.5" rx="1"/><rect x="9" y="9" width="4.5" height="4.5" rx="1"/>',
  gear: '<circle cx="8" cy="8" r="2.2"/><path d="M8 1.8v2M8 12.2v2M1.8 8h2M12.2 8h2M3.6 3.6l1.4 1.4M11 11l1.4 1.4M3.6 12.4L5 11M11 5l1.4-1.4"/>',
  plus: '<path d="M8 3v10M3 8h10"/>',
  pencil: '<path d="M2.8 13.2l.6-2.8 7.4-7.4 2.2 2.2-7.4 7.4-2.8.6z"/>',
  trash: '<path d="M2.8 4.5h10.4M6 4.5V2.8h4v1.7M4.3 4.5l.6 8.7h6.2l.6-8.7"/>',
  x: '<path d="M4 4l8 8M12 4l-8 8"/>',
  play: '<path d="M5 3l8 5-8 5z" fill="currentColor"/>',
  pause: '<path d="M4.5 3h2.5v10H4.5zM9 3h2.5v10H9z" fill="currentColor" stroke="none"/>',
  left: '<path d="M10 3L5 8l5 5"/>',
  right: '<path d="M6 3l5 5-5 5"/>',
  check: '<path d="M3 8.5l3.5 3.5L13 4.5"/>',
  down: '<path d="M8 2v8M4.5 6.5L8 10l3.5-3.5M3 13.5h10"/>',
  repeat: '<path d="M3.2 8a4.8 4.8 0 1 0 1.4-3.4L3 6.2M3 2.8v3.4h3.4"/>',
  calendar: '<rect x="2.5" y="3.5" width="11" height="10" rx="2"/><path d="M2.5 6.8h11M5.5 2v3M10.5 2v3"/>',
  infinity: '<path d="M8 8C6.8 6.4 5.8 5.5 4.4 5.5a2.5 2.5 0 0 0 0 5C5.8 10.5 6.8 9.6 8 8s2.2-2.5 3.6-2.5a2.5 2.5 0 0 1 0 5C10.2 10.5 9.2 9.6 8 8z"/>',
  stretch: '<circle cx="8" cy="2.8" r="1.4"/><path d="M2 6h12M8 6v4.5M8 10.5l-2.5 4M8 10.5l2.5 4"/>',
};
/** Arayüz simgesi: ince çizgili, yazının rengini alır. */
function glyph(name, size = 13, weight = 1.4) {
  const el = svg('svg', { viewBox: '0 0 16 16', width: size, height: size, fill: 'none', stroke: 'currentColor',
    'stroke-width': weight, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', class: 'glyph' });
  el.innerHTML = GLYPHS[name];
  return el;
}

const iconPaths = new Map(ICONS.map(([name, d]) => [name, d]));
/** Kategori ikonu (Phosphor, dolu). */
function categoryIcon(name, size, color) {
  if (!iconPaths.has(name)) return null;
  return svg('svg', { viewBox: '0 0 256 256', width: size, height: size }, svg('path', { d: iconPaths.get(name), fill: color }));
}

/** Kategorinin renkli karesi; içinde emoji ya da ikon olabilir. */
function swatch(category, size = 18) {
  const inner = category.emoji ? h('span', { style: { fontSize: px(size * 0.6), lineHeight: 1 } }, category.emoji)
    : category.icon ? categoryIcon(category.icon, size * 0.6, category.iconColor ?? inkOn(category.color)) : null;
  return h('span.swatch', { style: { width: px(size), height: px(size), borderRadius: px(size * 0.32), background: category.color } }, inner);
}

// MARK: Ortak parçalar

const eyebrow = (text) => h('div.eyebrow', null, upper(text));
const button = (kind, label, action, attrs) => h('button.btn.' + kind, { onclick: action, ...attrs }, label);
const iconButton = (name, action, title, extra = '') => h('button.icon-btn', { onclick: (e) => { e.stopPropagation(); action(e); }, title, class: extra }, glyph(name));

function segmented(options, selection, choose) {
  return h('div.segmented', null, options.map((o, i) => h('button', { class: i === selection ? 'on' : '', onclick: () => choose(i) }, o)));
}

function chip(title, topic, selected, action) {
  return h('button.chip', { class: (selected ? 'on ' : '') + (topic ? 'with-swatch' : ''), onclick: action }, topic && swatch(topic, 16), title);
}

/** Alt çizgili, çerçevesiz metin alanı. */
function field({ placeholder = '', value = '', size = 14, keep, autofocus, onSubmit, onInput }) {
  const input = h('input.field', { placeholder, value, 'data-keep': keep, spellcheck: 'false',
    style: { fontSize: px(size), fontWeight: size > 20 ? 300 : 400, padding: size > 20 ? '8px 0' : '7px 0' },
    onkeydown: (e) => { if (e.key === 'Enter' && onSubmit) onSubmit(); },
    oninput: () => onInput?.(input.value) });
  if (autofocus) setTimeout(() => input.focus(), 150);
  return input;
}

/** Serbest yazılan oturum notu; yer tutucu imleçle aynı satırda başlar. */
function notesEditor(value, onInput, keep) {
  const area = h('textarea.notes', { placeholder: T('Aklına geleni yaz…', 'Write down whatever comes to mind…'), 'data-keep': keep, spellcheck: 'false',
    oninput: () => onInput(area.value) });
  area.value = value;
  return area;
}

/** Oturumun kategorisini, hedefini ve notunu düzeltir; süren oturumda not ayrıntı panelinde zaten yazıldığından gizlenir. */
function sessionEditor(session, topics, { showsNote = true, done }) {
  let topicID = session.categoryID, note = session.note;
  const chips = h('div.chips.nowrap');
  const drawChips = () => chips.replaceChildren(...topics.map((t) => chip(t.name, t, t.id === topicID, () => { topicID = t.id; drawChips(); })));
  drawChips();
  const save = async () => { await call('editSession', session.id, topicID, goal.value, note); done(); };
  const goal = field({ placeholder: T('Hedef', 'Goal'), value: session.goal, onSubmit: save });
  return h('div.editor', { onclick: (e) => e.stopPropagation() }, chips, goal,
    showsNote && notesEditor(note, (v) => { note = v; }),
    h('div.row.gap8', null, button('secondary', T('Vazgeç', 'Cancel'), done), button('primary', T('Kaydet', 'Save'), save)));
}

/** Günün dikey çizelgesi: saat sütunu, bloklar gerçek saatlerinde, şu an solda etiket. */
function dayColumn(sessions, topics, state) {
  const now = nowSec(), H = 60;
  const all = sessions.map((s) => [s.goal, s.categoryID, s.start, s.end ?? s.start, false]);
  if (state?.session) all.push([state.session.goal, state.session.categoryID, state.session.start, state.plannedEnd ?? now, true]);
  const hoursFrom = (t) => daysBetween(now, t) * 24 + hourOfDay(t);   // gece yarısını aşan blok aşağı uzar
  const firstHour = Math.floor(Math.min(hourOfDay(now), ...all.map((s) => hoursFrom(s[2]))));
  const lastHour = Math.ceil(Math.max(hourOfDay(now), ...all.map((s) => hoursFrom(s[3]))) + 0.01);
  const hours = Math.max(1, lastHour - firstHour);
  const y = (t) => (hoursFrom(t) - firstHour) * H;
  const topic = (id) => topics[id]?.name ?? '';
  return h('div.day-column', { style: { height: px(hours * H) } },
    Array.from({ length: hours + 1 }, (_, i) => h('div.hour', { style: { top: px(i * H - 6) } },
      h('span', null, `${pad2((firstHour + i) % 24)}:00`), h('i'))),
    all.map(([goal, cat, start, end, current]) => {
      const height = Math.max(18, y(end) - y(start) - 2);
      return h('div.block', { class: current ? 'current' : '', style: { top: px(y(start) + 1), height: px(height), borderRadius: px(Math.min(7, Math.max(4, height * 0.2))) } },
        h('b', null, `${topic(cat)} · ${goal}`), height > 36 && h('small', null, `${formatTime(start)} – ${formatTime(end)}`));
    }),
    h('div.now', { style: { top: px(y(now) - 8) } }, formatTime(now)));
}
