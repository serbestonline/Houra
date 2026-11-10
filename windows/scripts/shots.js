// Geliştirme aracı: her pencereyi örnek veriyle kurar ve görüntüsünü HOURA_SHOTS klasörüne PNG olarak yazar.
//   HOURA_DB=/tmp/demo.sqlite npx electron . --demo
//   HOURA_DB=/tmp/demo.sqlite HOURA_SHOTS=/tmp/shots npx electron . --hidden
// Pencereler ekranda gösterilmez (HOURA_SHOTS_VISIBLE=1 ile gösterilir). Kurulum dosyasına girmez.
const { BrowserWindow } = require('electron');
const fs = require('node:fs');
const path = require('node:path');

module.exports = async ({ app, focus, store, widget, api, showPanel, showNewSession, showStretch, hoverWidget, setNudge, setSetting, buildWidget }) => {
  const dir = process.env.HOURA_SHOTS;
  fs.mkdirSync(dir, { recursive: true });
  if (process.env.HOURA_SHOTS_VISIBLE !== '1') for (const method of ['show', 'showInactive', 'focus', 'moveTop']) BrowserWindow.prototype[method] = function () {};
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  const view = (name) => BrowserWindow.getAllWindows().filter((w) => w.webContents.getURL().includes(`/${name}.html`));
  const shot = async (win, name) => {
    const image = await win.webContents.capturePage();
    fs.writeFileSync(path.join(dir, name + '.png'), image.toPNG());
    console.log('görüntü:', name, image.getSize());
  };
  const run = (win, code) => win.webContents.executeJavaScript(code);
  const errors = [];
  app.on('web-contents-created', (_e, contents) => contents.on('console-message', (event) => { if (event.level === 'error' || event.level === 'warning') errors.push(`${contents.getURL().split('/').pop()}: ${event.message}`); }));

  showPanel();
  await wait(1500);
  const panel = view('panel')[0];
  for (const page of ['today', 'stats', 'sessions', 'categories', 'settings']) {
    panel.webContents.send('page', page);
    await wait(700);
    await shot(panel, 'panel-' + page);
  }
  panel.webContents.send('page', 'stats');
  await wait(500);
  for (const [name, code] of [
    ['stats-month-flow', "stats.chart = 1; setPeriod('month', nowSec()); render()"],
    ['stats-month-calendar', 'stats.chart = 0; render()'],
    ['stats-month-timemap', 'stats.chart = 2; render()'],
    ['stats-year', "stats.chart = 0; setPeriod('year', nowSec()); render()"],
    ['stats-drawer', "setPeriod('week', nowSec()); stats.openDay = startOfDay(nowSec() - 86400); stats.picking = { from: stats.from, to: stats.to }; render()"],
  ]) { await run(panel, code); await wait(700); await shot(panel, name); }
  await run(panel, 'stats.openDay = null; stats.picking = null; 0');
  panel.webContents.send('page', 'categories');
  await wait(400);
  for (const tab of [0, 1, 2]) { await run(panel, `picker = { id: ${store.categories()[0].id}, tab: ${tab}, query: '' }; render()`); await wait(500); await shot(panel, 'picker-' + tab); }
  await run(panel, 'picker = null; 0');
  panel.webContents.send('page', 'today');

  store.addTodo(new Date().toISOString().slice(0, 10), 'Bekleyen görev', 'ayrıntı');
  showNewSession();
  await wait(1200);
  await shot(view('newsession')[0], 'newsession');

  const topic = store.categories()[0];
  focus.start({ topic, goal: 'Kaba kurgu', newTodos: [['Altyazıları yerleştir', 'Tek satır'], ['Sesi temizle', '']], work: 50, rest: 10 });
  focus.session.start -= 1234;   // oturum yirmi dakika önce başlamış gibi
  for (const [style, left] of [['tag', false], ['tag', true], ['strip', false], ['strip', true], ['capsule', false], ['card', false], ['ring', false]]) {
    setSetting('widgetLeft', left);
    api['settings.set']('widgetStyle', style);
    await wait(900);
    const name = `${style}${left ? '-left' : ''}`;
    await shot(widget.win, 'widget-' + name);
    if (left) continue;
    hoverWidget(true);
    for (let i = 0; i < 100 && !widget.detailOpen; i++) await wait(20);
    clearInterval(widget.watchTimer);   // fare yok; kendiliğinden kapanmasın
    await wait(600);
    console.log('ayrıntı paneli:', name, JSON.stringify(widget.detail.getBounds()), 'görünüm:', JSON.stringify(widget.win.getBounds()));
    await shot(widget.detail, 'detail-' + name);
  }
  setNudge(true);
  await wait(500);
  await shot(widget.win, 'widget-nudge');
  await shot(view('panel')[0], 'panel-today-running');

  focus.finish();
  await wait(2500);
  const rest = view('rest');
  for (const [i, win] of rest.entries()) await shot(win, 'rest-' + i);
  const main = rest.find((w) => w.webContents.getURL().includes('content'));
  await run(main, "document.querySelector('.stretch-toggle').click()");
  await wait(1500);
  await shot(main, 'rest-stretching');
  showStretch();
  await wait(1500);
  await shot(view('rest').find((w) => w.webContents.getURL().includes('stretch=')), 'stretch-window');
  focus.endRest(false);
  await wait(800);
  console.log('uyarılar:', errors.length ? errors.join('\n') : 'yok');
  app.exit(0);
};
