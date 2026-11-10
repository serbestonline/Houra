// Ekran görünümlerinin üzerine gelince açılan ayrıntı paneli: süre, yapılacaklar, notlar, bugünün akışı.
const root = document.getElementById('root');
let layout = { vertical: false, edgeLeft: null };   // ince şeridin çekmecesinde gün dikey çizelgeyle gösterilir
let state = null, today = [], cats = [], editing = false;

async function load() {
  const [s, sessions, categories] = await Promise.all([call('state'), call('sessions', startOfDay(nowSec())), call('categories')]);
  state = s; cats = categories;
  today = sessions.filter((x) => x.id !== s.session?.id);
}

const totalText = () => formatMinutes(sum(today, sessionMinutes) + Math.floor(state.elapsed / 60));

function render() {
  if (!state?.session) return;
  const s = state.session, paused = state.phase === 'paused', topics = Object.fromEntries(cats.map((t) => [t.id, t]));
  const done = state.todos.filter((t) => t.state === 2).length;
  document.body.className = ['detail', layout.vertical && 'vertical', layout.edgeLeft === true && 'flat-left', layout.edgeLeft === false && 'flat-right',
    document.body.classList.contains('shown') && 'shown'].filter(Boolean).join(' ');
  mount(root, h('div.sheet', null, h('div.scroll', null, h('div.inner', null,
    h('div.row.gap8', null, h('div', { id: 'phase' }, eyebrow(paused ? T('Duraklatıldı', 'Paused') : T('Odak', 'Focus'))), h('div.spacer'),
      state.topic && h('span.topic-pill', null, swatch(state.topic, 14), state.topic.name),
      iconButton('pencil', () => { editing = !editing; render(); }, T('Kategoriyi ve hedefi düzelt', 'Fix category and goal'), editing ? 'active' : '')),
    editing ? h('div.edit', null, sessionEditor(s, cats, { showsNote: false, done: () => { editing = false; render(); } })) : h('div.goal', null, s.goal),
    h('div.big-clock', { id: 'clock' }, formatClock(state.clock)),
    h('div.times', null, state.plannedEnd
      ? `${formatTime(s.start)} → ${formatTime(state.plannedEnd)} · ${T(`${s.workMinutes} dk`, `${s.workMinutes} min`)}`
      : T(`Başlangıç ${formatTime(s.start)} · serbest · 50. dakikada mola hatırlatılır`, `Started ${formatTime(s.start)} · free · break reminder at 50 min`)),
    h('div.progress-line', null, h('i', { id: 'progress', style: { width: `max(4px, ${state.progress * 100}%)` } })),
    h('div.row.gap8.actions', null,
      button('secondary', paused ? T('Devam et', 'Resume') : T('Duraklat', 'Pause'), () => call(paused ? 'focus.resume' : 'focus.pause')),
      button('primary', T('Bitir', 'Finish'), () => call('focus.finish'))),

    h('hr'),
    h('div.row', null, eyebrow(T('Yapılacaklar', 'To-do')), h('div.spacer'), state.todos.length > 0 && h('span.note', null, `${done}/${state.todos.length}`)),
    state.todos.length === 0 ? h('div.empty', null, T('Bu oturum için liste yok.', 'No list for this session.'))
      : h('div.todo-list', null, state.todos.map((todo) => h('div.todo-row', { class: ['', 'doing', 'done'][todo.state] },
        h('button.state-btn', { title: T('Durumu değiştir', 'Change state'), onclick: () => call('focus.setTodo', todo.id, (todo.state + 1) % 3) }, todoEmoji[todo.state]),
        h('div.text', { onclick: () => { if (todo.state !== 2) call('focus.setTodo', todo.id, 1); } }, h('div.title', null, todo.title), todo.detail && h('div.sub', null, todo.detail))))),

    h('hr'),
    eyebrow(T('Notlar', 'Notes')),
    h('div.notes-wrap', null, notesEditor(state.note, (text) => { state.note = text; call('focus.setNote', text); }, 'note')),

    h('hr'),
    eyebrow(T('Bugün', 'Today')),
    h('div.row.today-total', null, h('span', { id: 'total' }, totalText()), h('div.spacer'), h('span.note', null, T(`${today.length + 1} oturum`, `${today.length + 1} sessions`))),
    layout.vertical ? h('div.day-wrap', null, dayColumn(today, topics, state)) : dayStrip(),
    h('div.next', null, h('span.muted', null, T('Sırada', 'Up next')), ' ', T(`${state.restSeconds / 60} dakika mola`, `${state.restSeconds / 60} minute break`))))));
}

/** Günün yatay şeridi: biten oturumlar, şimdiki oturum ve şu an. 08–20'yi gösterir;
 *  gün daha erken başlar ya da geç uzarsa çizelge o saatlere genişler. */
function dayStrip() {
  const now = nowSec(), hours = [...today.flatMap((s) => [hourOfDay(s.start), hourOfDay(s.end)]), hourOfDay(state.session.start), hourOfDay(now)];
  const from = Math.min(8, Math.floor(Math.min(...hours)));
  const span = Math.ceil((Math.max(20, Math.ceil(Math.max(...hours))) - from) / 4) * 4;   // dört eşit aralık, tam saatlerde
  const x = (t) => (hourOfDay(t) - from) / span * 100;
  // Süresiyle orantılı çubuk; ardışık oturumlar arasında bir nokta boşluk kalır.
  const bar = (a, b, current) => h('i', { class: current ? 'current' : '', style: { left: x(a) + '%', width: `max(2px, calc(${x(b) - x(a)}% - 1px))` } });
  return h('div.day-strip', null,
    h('div.lane', null, today.map((s) => bar(s.start, s.end)), bar(state.session.start, now, true), h('b', { style: { left: x(now) + '%' } })),
    h('div.axis', null, [0, 1, 2, 3, 4].map((i) => h('span', null, pad2((from + span / 4 * i) % 24)))));
}

/** Her yarım saniyede yalnız akan değerler değişir; yazı alanları yerinde kalır. */
function tick() {
  const set = (id, text) => { const el = document.getElementById(id); if (el && el.textContent !== text) el.textContent = text; };
  set('clock', formatClock(state.clock));
  set('total', totalText());
  const bar = document.getElementById('progress');
  if (bar) bar.style.width = `max(4px, ${state.progress * 100}%)`;
}

// Not yazılırken fare panelin dışına çıksa da panel kapanmaz.
document.addEventListener('focusin', (e) => { if (e.target.matches('input, textarea')) call('detail.typing', true); });
document.addEventListener('focusout', () => call('detail.typing', false));

houra.on('prepare', async (next) => {
  layout = next; editing = false;
  await load();
  render();
  requestAnimationFrame(() => {
    call('detail.ready', root.querySelector('.inner').offsetHeight + 2);
    document.body.classList.add('shown');
  });
});
houra.on('hide', () => document.body.classList.remove('shown'));
houra.on('state', (s) => {
  const shape = (x) => JSON.stringify([x?.phase, x?.session?.goal, x?.topic, x?.todos]);
  const structural = shape(s) !== shape(state);
  state = { ...s, note: state?.note ?? s.note };   // yazılmakta olan not gecikmiş bir olayla geri alınmasın
  if (structural) render(); else tick();
});
houra.on('store', async () => { await load(); render(); });
setInterval(() => { if (document.body.classList.contains('shown')) render(); }, 30_000);   // şu an çizgisi ilerlesin
