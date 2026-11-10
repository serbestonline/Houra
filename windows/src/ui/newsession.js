// Yeni oturum penceresi: kategori, hedef, bugünün listesinden görevler, yeni görev, ritim (25 + 5, 50 + 10 ya da serbest).
const root = document.getElementById('root');
let init, topicID, source = 0, work = 50;
const picked = [], pickedWeekly = [], extra = [];

const topic = () => init.topics.find((t) => t.id === topicID) ?? init.topics[0];
const toggle = (list, id) => { const i = list.indexOf(id); if (i < 0) list.push(id); else list.splice(i, 1); render(); };
const value = (keep) => root.querySelector(`[data-keep="${keep}"]`)?.value.trim() ?? '';

function addTask() {
  const title = value('new-title');
  if (!title) return;
  extra.push([title, value('new-detail')]);
  for (const keep of ['new-title', 'new-detail']) root.querySelector(`[data-keep="${keep}"]`).value = '';
  render();
}

function begin() {
  addTask();
  const fromWeek = init.weekly.filter((t) => pickedWeekly.includes(t.id)).map((t) => [t.title, t.detail]);
  call('newSession.begin', { topicID: topic().id, goal: value('goal'), todoIDs: picked, newTodos: [...fromWeek, ...extra], work });
}

function pickRow({ title, detail = '', selected, topic: mark, waiting, sub }, action) {
  const note = (waiting ? T('bekleniyor', 'waiting') + (detail ? ' · ' : '') : '') + detail;
  return h('button.pick-row', { class: (selected ? 'on ' : '') + (sub ? 'sub' : ''), onclick: action },
    h('i.box', null, selected && glyph('check', 12, 2.2)),
    h('div.text', null, h('div.title', null, title), note && h('div.sub-text', null, note)),
    mark && swatch(mark, 14));
}

function rhythmCard(big, unit, sub, value, icon) {
  return h('button.rhythm', { class: (work === value ? 'on ' : '') + (icon ? 'free' : ''), onclick: () => { work = value; render(); } },
    icon && glyph(icon, 17, 1.2),
    h('div', null, h('div.big', null, h('b', null, big), unit && h('span', null, unit)), h('div.sub-text', null, sub)));
}

function render(first = false) {
  const current = topic(), last = init.last, lastTopic = last && init.topics.find((t) => t.id === last.categoryID);
  const count = picked.length + pickedWeekly.length + extra.length;
  // Seçili kategorinin görevleri üstte; dosyadaki sıra korunur.
  const mine = init.weekly.filter((t) => t.topicID != null && t.topicID === current?.id);
  const weekly = [...mine, ...init.weekly.filter((t) => !mine.includes(t))];
  const startsSubgroup = (i) => weekly[i].depth > 0 && (i === 0 || (weekly[i - 1].depth === 0 ? weekly[i - 1].title : weekly[i - 1].detail) !== weekly[i].detail);

  mount(root, h('div.sheet', null,
    h('div.row', null, eyebrow(T('Yeni oturum', 'New session')), h('div.spacer'),
      lastTopic && h('button.repeat', { title: `${lastTopic.name} · ${last.goal} · ${rhythm(last)}`, onclick: () => call('newSession.begin', { repeat: true }) },
        glyph('repeat', 11, 1.8), T('Öncekini tekrarla', 'Repeat last'))),
    h('div.chips.nowrap.topics', null, init.topics.map((t) => chip(t.name, t, t.id === current?.id, () => { topicID = t.id; render(); }))),
    h('div.goal', null, field({ placeholder: T('Neye odaklanıyorsun?', 'What are you focusing on?'), size: 26, keep: 'goal', autofocus: first, onSubmit: begin })),

    (init.waiting.length > 0 || extra.length > 0 || init.weekly.length > 0) && [
      h('div.row.list-head', null,
        init.weekly.length === 0 ? eyebrow(T('Bugünün listesinden seç', "Pick from today's list"))
          : segmented([T('Bugünün listesi', "Today's list"), T('Haftanın listesi (Obsidian)', "This week's list (Obsidian)")], source, (i) => { source = i; render(); }),
        h('div.spacer'), count > 0 && h('span.note', null, T(`${count} görev seçildi`, `${count} tasks selected`))),
      h('div.pick-list', null,
        source === 0 && init.waiting.length === 0 && extra.length === 0 && h('div.empty', null, T('Bugünün listesinde bekleyen görev yok.', "Nothing waiting on today's list.")),
        source === 0 && init.waiting.map((todo) => pickRow({ title: todo.title, detail: todo.detail, selected: picked.includes(todo.id) }, () => toggle(picked, todo.id))),
        source === 1 && weekly.map((task, i) => [
          startsSubgroup(i) && h('div.subgroup', null, task.detail),
          pickRow({ title: task.title, detail: task.depth > 0 ? '' : task.detail, selected: pickedWeekly.includes(task.id), waiting: task.waiting, sub: task.depth > 0,
            topic: init.topics.find((t) => t.id === task.topicID) }, () => toggle(pickedWeekly, task.id)),
        ]),
        extra.map(([title, detail], i) => pickRow({ title, detail, selected: true }, () => { extra.splice(i, 1); render(); })))],

    h('div.section', null, eyebrow(T('Yeni görev', 'New task'))),
    field({ placeholder: T('Görev başlığı', 'Task title'), keep: 'new-title', onSubmit: addTask }),
    field({ placeholder: T('Açıklama (isteğe bağlı) · Enter ile ekle', 'Details (optional) · Enter to add'), size: 12, keep: 'new-detail', onSubmit: addTask }),

    h('div.section', null, eyebrow(T('Ritim', 'Rhythm'))),
    h('div.row.gap10.rhythms', null,
      rhythmCard('25', T('dk odak', 'min focus'), T('+ 5 dk mola', '+ 5 min break'), 25),
      rhythmCard('50', T('dk odak', 'min focus'), T('+ 10 dk mola', '+ 10 min break'), 50)),
    rhythmCard(T('Serbest', 'Free'), '', T('İleri sayar, 50. dakikada mola önerir', 'Counts up, suggests a break at 50 min'), 0, 'infinity'),

    h('div.row.gap8.actions', null,
      button('secondary', T('Vazgeç', 'Cancel'), () => call('window.close')),
      button('primary', work === 0 ? T('Başla · serbest', 'Start · free') : T(`Başla · ${work} dk`, `Start · ${work} min`), begin)),
    h('div.hint', null, T('Her yerden: ', 'From anywhere: ') + init.hotkey)));
  call('window.fit', root.firstChild.offsetHeight + 60);   // pencere, çevresindeki gölge payıyla içeriğin boyuna oturur
}

document.addEventListener('keydown', (e) => { if (e.key === 'Escape') call('window.close'); });

(async () => {
  init = await call('newSession.init');
  // Bugün sayfasında tıklanan haftalık görev: pencere onu seçili ve kategorisi ayarlı açılır.
  topicID = init.preselect?.topicID ?? init.lastTopic;
  if (init.preselect) pickedWeekly.push(init.preselect.id);
  if (init.preselect || (init.waiting.length === 0 && init.weekly.length > 0)) source = 1;
  work = init.work;
  render(true);
})();
