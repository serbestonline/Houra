// İstatistik sayfası: dönem (hafta, ay, yıl ya da takvimden aralık), özet metrikler, üç grafik türü
// (takvim, akış, zaman haritası), kategori dağılımı ve verimli saatler. Uygulamada rengin kullanıldığı tek yer.
const ACCENT = '#3d8cff';   // filtre yokken kullanılan vurgu
const stats = { period: 'week', from: mondayOf(nowSec()), to: addDays(mondayOf(nowSec()), 6), filter: null, hover: null, chart: 0,
  openDay: null, drawerShown: false, picking: null };
const tint = (hex, opacity) => `color-mix(in srgb, ${hex} ${Math.round(opacity * 100)}%, transparent)`;
const parseDay = (key) => { const [y, m, d] = key.split('-').map(Number); return new Date(y, m - 1, d).getTime() / 1000; };

function setPeriod(period, anchor) {
  const d = new Date(anchor * 1000), at = (y, m, day) => new Date(y, m, day).getTime() / 1000;
  stats.period = period;
  if (period === 'week') { stats.from = mondayOf(anchor); stats.to = addDays(stats.from, 6); }
  if (period === 'month') { stats.from = at(d.getFullYear(), d.getMonth(), 1); stats.to = at(d.getFullYear(), d.getMonth() + 1, 0); }
  if (period === 'year') { stats.from = at(d.getFullYear(), 0, 1); stats.to = at(d.getFullYear(), 11, 31); }
}

function stepPeriod(dir) {
  const d = new Date(stats.from * 1000);
  if (stats.period === 'week') setPeriod('week', addDays(stats.from, 7 * dir));
  else if (stats.period === 'month') setPeriod('month', addMonths(stats.from, dir));
  else if (stats.period === 'year') setPeriod('year', new Date(d.getFullYear() + dir, 0, 1).getTime() / 1000);
  else { const n = (daysBetween(stats.from, stats.to) + 1) * dir; stats.from = addDays(stats.from, n); stats.to = addDays(stats.to, n); }
  render();
}

function rangeLabel() {
  const sameYear = new Date(stats.from * 1000).getFullYear() === new Date(stats.to * 1000).getFullYear();
  return `${formatDate(stats.from, sameYear ? 'dMMM' : 'dMMMyyyy')} – ${formatDate(stats.to, 'dMMMyyyy')}`;
}

async function statsPage() {
  const v = stats, now = nowSec();
  const data = await call('stats', v.from, v.to, v.filter);
  const drawer = v.openDay == null ? null : await call('sessions', v.openDay, addDays(v.openDay, 1));
  const accent = data.topics[v.filter]?.color ?? ACCENT;
  // Günlere göre dizin
  const byDay = new Map();
  for (const s of data.sessions) { const day = startOfDay(s.start); byDay.set(day, [...(byDay.get(day) ?? []), s]); }
  const view = {
    data, accent, on: (day) => byDay.get(day) ?? [],
    minutes: (day, topic) => sum((byDay.get(day) ?? []).filter((s) => topic == null || s.categoryID === topic), sessionMinutes),
    topics: Object.values(data.topics).sort((a, b) => a.id - b.id).filter((t) => v.filter == null || t.id === v.filter),
    open: (day) => { v.openDay = day; render(); },
  };

  const isNow = v.from <= now && now < addDays(v.to, 1);
  const title = { week: isNow ? T('Bu hafta', 'This week') : rangeLabel(), month: isNow ? T('Bu ay', 'This month') : formatDate(v.from, 'MMMMyyyy'),
    year: isNow ? T('Bu yıl', 'This year') : formatDate(v.from, 'yyyy'), custom: T(`${data.days.length} gün`, `${data.days.length} days`) }[v.period];
  const periods = ['week', 'month', 'year'];
  const controls = h('div.row.gap10.period', null,
    segmented([T('Hafta', 'Week'), T('Ay', 'Month'), T('Yıl', 'Year')], periods.indexOf(v.period), (i) => { setPeriod(periods[i], nowSec()); render(); }),
    h('div.stepper', null,
      h('button.arrow', { onclick: () => stepPeriod(-1) }, glyph('left', 12, 1.8)),
      h('button.range', { onclick: (e) => { e.stopPropagation(); v.picking = v.picking ? null : { from: v.from, to: v.to }; render(); } }, glyph('calendar'), rangeLabel()),
      h('button.arrow', { onclick: () => stepPeriod(1) }, glyph('right', 12, 1.8))),
    v.picking && rangePicker());

  const section = (name, hint, trailing, content) => h('section', null,
    h('div.row.section-head', null, eyebrow(name), h('div.spacer'), hint && h('small.faint', null, hint), trailing), content);
  const filterTopic = data.topics[v.filter];
  const node = h('div.stats', null, scroll(
    pageHeader(T('İstatistik', 'Statistics'), title, controls),
    filterTopic && h('button.only', { style: { background: tint(filterTopic.color, 0.14), boxShadow: `inset 0 0 0 1px ${tint(filterTopic.color, 0.55)}` },
      onclick: () => { v.filter = null; render(); } }, swatch(filterTopic, 16), T(`Yalnız ${filterTopic.name}`, `Only ${filterTopic.name}`), glyph('x', 10, 2)),
    metrics(view),
    section(T('Zamana göre', 'Over time'), '',
      segmented([T('1 · Takvim', '1 · Calendar'), T('2 · Akış', '2 · Flow'), T('3 · Zaman haritası', '3 · Time map')], v.chart, (i) => { v.chart = i; render(); }),
      [calendarChart, flowChart, timeMap][v.chart](view)),
    section(T('Kategoriler', 'Categories'), T('Üzerine gel: grafikte öne çıkar · Tıkla: sayfayı filtrele', 'Hover: highlight in chart · Click: filter the page'), null, categoryList(view)),
    section(T('Gün içinde en verimli saatler', 'Most productive hours'),
      data.peakHour == null ? '' : T(`en yoğun saat ${pad2(data.peakHour)}:00`, `busiest hour ${pad2(data.peakHour)}:00`), null, hoursStrip(view))),
  drawer && dayDrawer(v.openDay, drawer, data.topics));
  v.drawerShown = !!drawer;
  return node;
}

/** Kategori satırının üzerine gelince o kategori grafikte öne çıkar; sayfa yeniden kurulmaz. */
function highlight(id) {
  stats.hover = id;
  for (const el of document.querySelectorAll('[data-topic]')) el.style.opacity = id == null || Number(el.dataset.topic) === id ? 1 : el.dataset.dim;
}

function metrics({ data, open }) {
  const change = data.previousTotal > 0 ? Math.round((data.total - data.previousTotal) / data.previousTotal * 100) : null;
  const metric = (name, value, detail, action) => h(action ? 'button.metric' : 'div.metric', { onclick: action }, eyebrow(name), h('div.value', null, value), h('div.detail', null, detail));
  const share = data.tasks > 0 ? Math.floor(data.tasksDone * 100 / data.tasks) : 0;
  return h('div.metrics', null,
    metric(T('Toplam odak', 'Total focus'), formatMinutes(data.total), change == null ? T('önceki dönemde kayıt yok', 'no data in previous period')
      : [h('span', { class: change >= 0 ? 'up' : 'down' }, change >= 0 ? '↑ ' + percent(change) : '↓ ' + percent(-change)), T(' önceki döneme göre', ' vs previous period')]),
    h('i'),
    metric(T('Günlük ortalama', 'Daily average'), formatMinutes(Math.floor(data.total / Math.max(1, data.elapsedDays))), T(`${data.sessions.length} oturum`, `${data.sessions.length} sessions`)),
    h('i'),
    metric(T('Görev', 'Tasks'), `${data.tasksDone} / ${data.tasks}`, T(`tamamlandı · %${share}`, `done · ${share}%`)),
    h('i'),
    metric(T('En iyi gün', 'Best day'), data.bestDay ? formatMinutes(data.bestDay.minutes) : '—',
      data.bestDay ? formatDate(data.bestDay.day, 'dMMMMEEEE') + ' ›' : T('kayıt yok', 'no data'), data.bestDay && (() => open(data.bestDay.day))));
}

// MARK: 1 · Takvim

function calendarChart(view) {
  const { data, accent, minutes, on, open, topics } = view, days = data.days, first = mondayOf(days[0]), last = days.at(-1);
  const max = Math.max(1, ...days.map((d) => minutes(d)));
  const inRange = (d) => d >= days[0] && d <= last;
  const weeks = Math.ceil((daysBetween(first, last) + 1) / 7);
  if (days.length <= 42) {
    return h('div.calendar', null,
      Array.from({ length: 7 }, (_, i) => h('div.weekday', null, formatDate(addDays(first, i), 'EEE'))),
      Array.from({ length: weeks * 7 }, (_, i) => {
        const d = addDays(first, i), m = inRange(d) ? minutes(d) : 0;
        return h('button.day-cell', { class: (isToday(d) ? 'today ' : '') + (inRange(d) ? '' : 'out'), disabled: !inRange(d),
          style: { background: m > 0 ? tint(accent, 0.1 + m / max * 0.6) : 'rgba(255,255,255,.03)' },
          title: inRange(d) ? `${formatDate(d, 'dMMMMEEEE')} · ${formatMinutes(m)} · ${on(d).length} ${T('oturum', 'sessions')}` : '', onclick: () => open(d) },
          h('span.number', { class: d > nowSec() ? 'faint' : '' }, new Date(d * 1000).getDate()),
          h('div.spacer'),
          m > 0 && h('span.amount', null, formatMinutesShort(m)),
          // Günün kategori dağılımını gösteren ince çizgi
          h('div.mix', null, topics.map((t) => { const part = minutes(d, t.id); return part > 0 && h('i', { style: { background: t.color, flexGrow: part } }); })));
      }));
  }
  return h('div', null,
    h('div.year', null, Array.from({ length: weeks }, (_, w) => h('div', null, Array.from({ length: 7 }, (_, i) => {
      const d = addDays(first, w * 7 + i), m = inRange(d) ? minutes(d) : 0;
      return h('button', { disabled: !inRange(d), style: { background: m > 0 ? tint(accent, 0.1 + m / max * 0.75) : 'rgba(255,255,255,.04)', opacity: inRange(d) ? 1 : 0 },
        title: inRange(d) ? `${formatDate(d, 'dMMMMEEEE')} · ${formatMinutes(m)}` : '', onclick: () => open(d) });
    })))),
    h('div.legend', null, T('az', 'less'), [0.1, 0.3, 0.5, 0.75].map((o) => h('i', { style: { background: tint(accent, o) } })), T('çok', 'more')));
}

// MARK: 2 · Akış

function flowChart({ data, minutes, topics, open }) {
  const days = data.days, daily = days.length <= 62, W = 1000, H = 230;
  const buckets = daily ? days.map((d) => [d]) : Array.from({ length: Math.ceil(days.length / 7) }, (_, i) => days.slice(i * 7, i * 7 + 7));
  const past = Math.max(1, buckets.filter((b) => b[0] <= nowSec()).length);
  const values = buckets.slice(0, past).map((b) => topics.map((t) => sum(b, (d) => minutes(d, t.id))));
  const maxTotal = Math.max(1, ...values.map((v) => sum(v, (x) => x)));
  const x = (i) => (buckets.length === 1 ? W / 2 : 8 + i * (W - 16) / (buckets.length - 1));
  const y = (v) => H - v / maxTotal * (H - 16);
  // İki çizgi arasında kalan, yumuşak geçişli alan
  const curve = (pts) => pts.slice(1).map((b, i) => { const a = pts[i], cx = (a[0] + b[0]) / 2; return `C${cx} ${a[1]} ${cx} ${b[1]} ${b[0]} ${b[1]}`; }).join('');
  const layers = topics.map((t, j) => {
    const stack = (n) => values.map((v, i) => [x(i), y(sum(v.slice(0, n), (q) => q))]);
    const top = stack(j + 1), bottom = stack(j).reverse();
    return svg('path', { d: `M${top[0][0]} ${top[0][1]}${curve(top)}L${bottom[0][0]} ${bottom[0][1]}${curve(bottom)}Z`, fill: t.color, 'fill-opacity': 0.85,
      'data-topic': t.id, 'data-dim': 0.15, style: { opacity: stats.hover == null || stats.hover === t.id ? 1 : 0.15 } });
  });
  const line = h('div.flow-line'), tip = h('div.flow-tip');
  let index = null;
  const chart = h('div.flow', {
    onmousemove: (e) => {
      const box = chart.getBoundingClientRect(), w = box.width, px0 = e.clientX - box.left;
      index = clamp01(Math.round((px0 / w * W - 8) / (W - 16) * (buckets.length - 1)), buckets.length - 1);
      const shown = index < past;
      line.style.display = tip.style.display = shown ? 'block' : 'none';
      if (!shown) return;
      const at = x(index) / W * w, bucket = buckets[index], total = sum(values[index], (q) => q);
      line.style.left = px(at);
      tip.style.left = px(Math.min(at + 12, w - 220));
      tip.replaceChildren(
        h('b', null, bucket.length === 1 ? formatDate(bucket[0], 'dMMMMEEEE') : T(`${formatDate(bucket[0], 'dMMMM')} haftası`, `Week of ${formatDate(bucket[0], 'dMMMM')}`)),
        h('div', null, T(`Toplam ${formatMinutes(total)}`, `Total ${formatMinutes(total)}`)), h('hr'),
        topics.map((t, j) => h('div.row.gap6', null, h('i.bullet', { style: { background: t.color } }), `${t.name} · ${formatMinutes(values[index][j])}`)));
    },
    onmouseleave: () => { index = null; line.style.display = tip.style.display = 'none'; },
    onclick: () => { if (daily && index != null && index < past) open(buckets[index][0]); },
  }, svg('svg', { viewBox: `0 0 ${W} ${H}`, preserveAspectRatio: 'none' }, layers), line, tip);
  const step = Math.max(1, Math.ceil(buckets.length / 10));
  return h('div', null, chart, h('div.axis', null, buckets.filter((_, i) => i % step === 0).map((b) => h('span', null, formatDate(b[0], 'dMMM')))));
}
const clamp01 = (i, max) => Math.min(Math.max(0, i), max);

// MARK: 3 · Zaman haritası

function timeMap({ data, minutes, on, open }) {
  const days = data.days, shown = days.length > 31 ? days.slice(-31) : days, A = 6, B = 24;
  const at = (hours) => (hours - A) / (B - A) * 100 + '%';
  return h('div.timemap', null,
    days.length > 31 && h('small.faint', null, T('Aralığın son 31 günü gösteriliyor.', 'Showing the last 31 days of the range.')),
    h('div.tm-row.tm-head', null, h('span.label'), h('div.tm-hours', null, [6, 9, 12, 15, 18, 21, 24].map((hr) => h('span', { style: { left: at(hr) } }, `${pad2(hr % 24)}:00`))), h('span.total')),
    shown.map((d) => h('button.tm-row', { class: isToday(d) ? 'today' : '', onclick: () => open(d) },
      h('span.label', null, formatDate(d, 'EEEd')),
      h('div.track', null, on(d).map((s) => {
        const topic = data.topics[s.categoryID];
        return h('i', { style: { left: at(hourOfDay(s.start)), width: `max(2px, ${s.focusSeconds / 3600 / (B - A) * 100}%)`, background: topic?.color ?? '#888888',
          opacity: stats.hover == null || stats.hover === s.categoryID ? 1 : 0.12 }, 'data-topic': s.categoryID, 'data-dim': 0.12,
          title: `${topic?.name ?? ''} · ${formatTime(s.start)} – ${formatTime(s.end)} · ${formatMinutes(sessionMinutes(s))}` });
      })),
      h('span.total', null, on(d).length ? formatMinutesShort(minutes(d)) : ''))));
}

// MARK: Kategoriler ve saatler

function categoryList({ data }) {
  const all = data.allTotalsByTopic, values = Object.values(all), total = Math.max(1, sum(values, (x) => x)), top = Math.max(1, ...values);
  return h('div.cat-list', { onmouseleave: () => highlight(null) }, Object.values(data.topics).sort((a, b) => a.id - b.id).map((t) => {
    const m = all[t.id] ?? 0;
    return h('button.cat-line', { class: stats.filter == null || stats.filter === t.id ? '' : 'dim', onmouseenter: () => highlight(t.id),
      onclick: () => { stats.filter = stats.filter === t.id ? null : t.id; render(); } },
      h('div.row.gap8', null, swatch(t, 18), h('b', null, t.name), h('div.spacer'), h('span.share', null, percent(Math.floor(m * 100 / total))), h('span.time', null, formatMinutes(m))),
      h('div.bar', null, h('i', { style: { width: m / top * 100 + '%', background: t.color } })));
  }));
}

function hoursStrip({ data, accent }) {
  const max = Math.max(1, ...data.hourMinutes);
  return h('div', null,
    h('div.hours', null, data.hourMinutes.map((m, hr) => h('i', { style: { background: tint(accent, 0.06 + m / max * 0.9) },
      title: `${pad2(hr)}:00 – ${pad2((hr + 1) % 24)}:00 · ${formatMinutes(m)}` }))),
    h('div.axis', null, ['00', '06', '12', '18', '23'].map((t) => h('span', null, t))));
}

// MARK: Gün ayrıntısı

function dayDrawer(day, list, topics) {
  const total = sum(list, sessionMinutes), close = () => { stats.openDay = null; render(); };
  const byTopic = Object.entries(Object.groupBy(list, (s) => s.categoryID)).map(([id, items]) => [topics[id], sum(items, sessionMinutes)]).sort((a, b) => b[1] - a[1]);
  const colour = (t) => t?.color ?? '#888888';
  return h('aside.drawer', { class: stats.drawerShown ? '' : 'slide' }, h('div.scroll', null,
    h('div.row', null, eyebrow(formatDate(day, 'yyyy')), h('div.spacer'), h('button.close', { onclick: close }, glyph('x', 11, 2))),
    h('h2', null, formatDate(day, 'dMMMMEEEE')),
    h('p.muted', null, total > 0 ? T(`${formatMinutes(total)} odak`, `${formatMinutes(total)} focused`) : T('Bu gün oturum yok', 'No sessions this day')),
    total > 0 && h('div.split', null, byTopic.map(([t, v]) => h('i', { style: { background: colour(t), flexGrow: v } }))),
    total > 0 && h('div.split-legend', null, byTopic.map(([t, v]) => t && h('div.row.gap8', null, swatch(t, 14), `${t.name} · ${formatMinutes(v)}`))),
    h('div.drawer-list', null, list.map((s) => {
      const done = s.todos.filter((t) => t.state === 2).length;
      return h('div.item', null, h('i.bullet', { style: { background: colour(topics[s.categoryID]) } }),
        h('div.text', null, h('b', null, `${topics[s.categoryID]?.name ?? ''} · ${s.goal}`),
          h('small', null, `${formatTime(s.start)} – ${formatTime(s.end)} · ${rhythm(s)}` + (s.todos.length ? T(` · ${done}/${s.todos.length} görev 🥳`, ` · ${done}/${s.todos.length} tasks 🥳`) : ''))),
        h('span.minutes', null, formatMinutes(sessionMinutes(s))));
    })),
    total > 0 && button('secondary', T('Oturumlar sayfasında aç', 'Open in Sessions'), () => { stats.openDay = null; go('sessions'); })));
}

// MARK: Tarih aralığı

function rangePicker() {
  const p = stats.picking, today = startOfDay(nowSec());
  const date = (key) => h('input.date', { type: 'date', value: dayKey(p[key]), min: key === 'to' ? dayKey(p.from) : null, max: key === 'from' ? dayKey(p.to) : null,
    onchange: (e) => { if (e.target.value) { p[key] = parseDay(e.target.value); render(); } } });
  const n = daysBetween(p.from, p.to) + 1;
  return h('div.popover.range-picker', { onclick: (e) => e.stopPropagation() },
    h('div.row.gap6', null, [7, 30, 90].map((days) => button('secondary', T(`Son ${days} gün`, `Last ${days} days`), () => { p.to = today; p.from = addDays(today, -(days - 1)); render(); }))),
    h('div.row.gap16', null, h('label', null, eyebrow(T('Başlangıç', 'From')), date('from')), h('label', null, eyebrow(T('Bitiş', 'To')), date('to'))),
    h('div.row', null, h('span.muted', null, T(`${n} gün`, `${n} days`)), h('div.spacer'),
      h('div', { style: { width: '110px' } }, button('primary', T('Uygula', 'Apply'), () => { stats.from = p.from; stats.to = p.to; stats.period = 'custom'; stats.picking = null; render(); }))));
}
document.addEventListener('click', () => { if (stats.picking) { stats.picking = null; render(); } });
