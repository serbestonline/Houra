// Oturum sürerken ekranda duran küçük görünümler: etiket, ince şerit, kapsül, kart, halka.
// Üzerine gelip bekleyince ayrıntı paneli açılır, fare çekilince kapanır. Basılı tutup çekince taşınır;
// etiket ve şerit bırakılınca en yakın kenara (sol ya da sağ) yapışır.
const root = document.getElementById('root');
let config = { style: 'tag', onLeft: false, detailOpen: false, nudging: false };
let state = null;

/** Saat 12'den başlayıp saat yönünde ilerleyen halka; ilerleme --p değişkeninden gelir. */
function ring(stroke) {
  const r = 50 - stroke / 2;
  return svg('svg', { viewBox: '0 0 100 100', class: 'ring' },
    svg('circle', { cx: 50, cy: 50, r, class: 'back', 'stroke-width': stroke }),
    svg('circle', { cx: 50, cy: 50, r, class: 'front', 'stroke-width': stroke, pathLength: 1, transform: 'rotate(-90 50 50)' }));
}
const groupName = () => h('div.group', null, h('span', { 'data-swatch': '' }), h('span', { 'data-topic-name': '' }));
const clock = () => h('div.clock', { 'data-clock': '' });
const headline = () => h('div.headline', { 'data-headline': '' });
const grip = () => h('i.grip');

const views = {
  // Etiket: kenara yapışık, grup adı, görev ve süre; altta ince ilerleme
  tag: () => h('div.tag.hit', null, !config.onLeft && grip(), h('div.text', null, groupName(), headline()), clock(), config.onLeft && grip(), h('i.progress')),
  // İnce şerit: ekran kenarında, aşağıdan dolar; etiketi dolumun tepesinde
  strip: () => [h('div.track.hit'), h('div.fill'), h('div.label.hit', null, clock(), headline())],
  // Kapsül: başlık ve kategori, süre, halkalı duraklat düğmesi
  capsule: () => h('div.capsule.hit', null,
    h('div.text', null, headline(), h('div.group.plain', null, h('span', { 'data-swatch': '' }), h('span', { 'data-topic-goal': '' }))),
    clock(),
    h('button.pause', { onclick: () => call(state.phase === 'paused' ? 'focus.resume' : 'focus.pause') }, ring(5.4), h('span', { 'data-pause': '' }))),
  // Kart: büyük halka ve süre, altında görev
  card: () => h('div.cardview.hit', null, h('div.dial', null, ring(3.3), clock()), headline()),
  // Halka: içinde süre
  ring: () => h('div.ringview.hit', null, ring(3.75), clock()),
  none: () => null,
};

// Mola sorusu: serbest oturumda 50 dakika dolunca her görünüm buna döner
const nudge = () => h('div.nudge.hit', null,
  h('div.row', null, groupName(), h('div.spacer'), clock()),
  h('div.asked', { 'data-minutes': '' }),
  h('div.optional', null, T('Mola isteğe bağlı.', 'The break is optional.')),
  h('div.row.gap6', null, button('secondary', T('Devam et', 'Keep going'), () => call('widget.endNudge')), button('primary', T('Mola ver', 'Take a break'), () => call('focus.finish'))));

function render() {
  document.body.className = ['widget', 'style-' + config.style, config.onLeft ? 'left' : 'right', config.detailOpen && 'detail-open', config.nudging && 'nudging'].filter(Boolean).join(' ');
  root.replaceChildren(...[config.nudging ? nudge() : views[config.style]()].flat().filter(Boolean));
  update();
}

let shownTopic = '';
function update() {
  if (!state?.session) return;
  const put = (key, text) => root.querySelectorAll(`[data-${key}]`).forEach((el) => { if (el.textContent !== text) el.textContent = text; });
  document.body.style.setProperty('--p', state.progress);
  put('clock', formatClock(state.clock));
  put('headline', state.headline);
  put('topic-name', upper(state.topic?.name ?? ''));
  put('topic-goal', `${state.topic?.name ?? ''} · ${state.session.goal}`);
  put('minutes', T(`${Math.floor(state.elapsed / 60)} dakikadır çalışıyorsun`, `${Math.floor(state.elapsed / 60)} minutes in`));
  const topicKey = JSON.stringify(state.topic);
  root.querySelectorAll('[data-swatch]').forEach((el) => { if (state.topic && (shownTopic !== topicKey || !el.firstChild)) el.replaceChildren(swatch(state.topic, 9)); });
  shownTopic = topicKey;
  root.querySelectorAll('[data-pause]').forEach((el) => {
    const icon = state.phase === 'paused' ? 'play' : 'pause';
    if (el.dataset.pause !== icon) { el.dataset.pause = icon; el.replaceChildren(glyph(icon, 12)); }
  });
  reportRects();   // ince şeridin etiketi ilerledikçe yer değiştirir
}

// Saydam yerler tıklamayı alttaki pencereye bırakır; yalnız görünümün kendisi fareyi tutar.
// Görünümün pencere içindeki yeri ana sürece bildirilir, imleci o izler.
let sentRects = '', press = null, dragging = false, queued = false;
function reportRects() {
  const rects = [...root.querySelectorAll('.hit')].map((el) => { const r = el.getBoundingClientRect(); return [r.x, r.y, r.width, r.height].map(Math.round); });
  if (JSON.stringify(rects) === sentRects) return;
  sentRects = JSON.stringify(rects);
  call('widget.rects', rects);
}
addEventListener('resize', reportRects);

document.addEventListener('pointerdown', (e) => {
  if (e.button !== 0 || !e.target.closest('.hit') || e.target.closest('button')) return;
  press = { x: e.screenX, y: e.screenY };
  e.target.setPointerCapture(e.pointerId);
});
document.addEventListener('pointermove', (e) => {
  if (!press) return;
  if (!dragging && Math.hypot(e.screenX - press.x, e.screenY - press.y) < 3) return;
  dragging = true;
  if (queued) return;
  queued = true;
  requestAnimationFrame(() => { queued = false; if (dragging) call('widget.drag'); });
});
function release() {
  if (dragging) call('widget.drop');
  press = null; dragging = false;
}
document.addEventListener('pointerup', release);
document.addEventListener('pointercancel', release);

houra.on('widget', (c) => { config = c; render(); });
houra.on('state', (s) => { state = s; update(); });
(async () => {
  [config, state] = await Promise.all([call('widget.config'), call('state')]);
  render();
})();
