// İstatistik sayfasının verisi: dönemdeki oturumlar, toplamlar, en iyi gün, saatlere dağılım.
const U = require('../shared/util');

function statsData(store, from, to, filter = null) {
  const start = U.startOfDay(from), end = U.addDays(U.startOfDay(to), 1);
  const n = U.daysBetween(start, end);
  const days = Array.from({ length: n }, (_, i) => U.addDays(start, i));
  const mine = (s) => filter == null || s.categoryID === filter;
  const all = store.sessions(start, end).filter((s) => s.end != null);
  // Filtreden bağımsız kategori toplamları (liste her zaman bütün kategorileri gösterir).
  const allTotalsByTopic = {};
  for (const s of all) allTotalsByTopic[s.categoryID] = (allTotalsByTopic[s.categoryID] ?? 0) + U.sessionMinutes(s);
  const sessions = all.filter(mine);
  const total = U.sum(sessions, U.sessionMinutes);
  const previousTotal = U.sum(store.sessions(U.addDays(start, -n), start).filter(mine), U.sessionMinutes);
  const elapsedDays = Math.max(1, Math.min(n, U.daysBetween(start, U.nowSec()) + 1));

  let tasks = 0, tasksDone = 0;
  const byDay = {}, hourMinutes = Array(24).fill(0);
  for (const s of sessions) {
    const todos = store.sessionTodos(s.id);
    tasks += todos.length; tasksDone += todos.filter((t) => t.state === 2).length;
    const day = U.startOfDay(s.start);
    byDay[day] = (byDay[day] ?? 0) + U.sessionMinutes(s);
    for (let m = s.start; m < s.start + s.focusSeconds; m += 60) hourMinutes[new Date(m * 1000).getHours()] += 1;
  }
  const best = Object.entries(byDay).sort((a, b) => b[1] - a[1])[0];
  const peak = Math.max(...hourMinutes);
  return {
    days, sessions, filter, total, previousTotal, elapsedDays, tasks, tasksDone, allTotalsByTopic, hourMinutes,
    topics: Object.fromEntries(store.categories().map((t) => [t.id, t])),
    bestDay: best ? { day: Number(best[0]), minutes: best[1] } : null,
    peakHour: peak === 0 ? null : hourMinutes.indexOf(peak),
  };
}

module.exports = { statsData };
