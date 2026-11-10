// Geliştirme aracı (Windows): uygulamayı gerçek masaüstünde, gerçek fare hareketleriyle sınar; her adımda ekranın
// görüntüsünü ve ölçtüklerini HOURA_CHECK klasörüne yazar. Fareyi PowerShell üzerinden kendisi oynatır, bu yüzden
// çalışırken bilgisayara dokunulmamalıdır. Kurulum dosyasına girmez.
//   set HOURA_DB=%TEMP%\demo.sqlite & set HOURA_CHECK=C:\houra-test\check & electron . --hidden
const { BrowserWindow, desktopCapturer, screen, globalShortcut } = require('electron');
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const MOUSE = `Add-Type -Namespace W -Name M -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, System.UIntPtr e);';`;

module.exports = async (ctx) => {
  const { app, focus, store, widget, api, getTray, getSettings, showPanel, showNewSession, showStretch, setNudge, setSetting, pulseScreens } = ctx;
  const dir = process.env.HOURA_CHECK;
  fs.mkdirSync(dir, { recursive: true });
  const log = (...parts) => { const line = parts.map((p) => (typeof p === 'string' ? p : JSON.stringify(p))).join(' '); fs.appendFileSync(path.join(dir, 'check.log'), line + '\n'); };
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  const view = (name) => BrowserWindow.getAllWindows().filter((w) => !w.isDestroyed() && w.webContents.getURL().includes(`/${name}.html`));
  const display = screen.getPrimaryDisplay();
  const shot = async (name) => {
    const size = { width: Math.round(display.size.width * display.scaleFactor), height: Math.round(display.size.height * display.scaleFactor) };
    const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: size });
    fs.writeFileSync(path.join(dir, name + '.png'), sources[0].thumbnail.toPNG());
  };
  /** Fare komutları: "move x y", "down", "up", "sleep ms" (x ve y ekran noktası). */
  const mouse = (...steps) => {
    const script = MOUSE + steps.map((step) => {
      const [kind, a, b] = step.split(' ');
      // Gerçek girdi olayı üretilir (SetCursorPos yalnız imleci taşır, saydam pencerelerin fare kancasına ulaşmaz).
      // 0x8001: mutlak konuma taşı; konum ana ekranın 0–65535 aralığına ölçeklenir.
      if (kind === 'move') return `[W.M]::mouse_event(0x8001, ${Math.round(a * 65535 / (display.size.width - 1))}, ${Math.round(b * 65535 / (display.size.height - 1))}, 0, [System.UIntPtr]::Zero)`;
      if (kind === 'sleep') return `Start-Sleep -Milliseconds ${a}`;
      return `[W.M]::mouse_event(${kind === 'down' ? 2 : 4}, 0, 0, 0, [System.UIntPtr]::Zero)`;
    }).join('; ');
    // Tırnaklar komut satırında bozulmasın diye betik kodlanmış olarak verilir.
    // Ana süreç bu sırada çalışmayı sürdürmeli (imleci o izliyor), bu yüzden beklemeden başlatılır.
    return new Promise((done) => spawn('powershell', ['-NoProfile', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { windowsHide: true, stdio: 'ignore' })
      .on('exit', (code) => { if (code !== 0) log('fare hatası:', code); done(); }));
  };
  /** Bir pencere içindeki öğenin ekran üzerindeki merkezi. */
  const centre = async (win, selector) => {
    const r = await win.webContents.executeJavaScript(`(() => { const r = document.querySelector(${JSON.stringify(selector)})?.getBoundingClientRect(); return r && [r.x + r.width / 2, r.y + r.height / 2, r.width, r.height]; })()`);
    if (!r) return null;
    const b = win.getBounds();
    return { x: Math.round(b.x + r[0]), y: Math.round(b.y + r[1]) };
  };
  const errors = [];
  app.on('web-contents-created', (_e, contents) => contents.on('console-message', (event) => { if (event.level === 'error') errors.push(`${contents.getURL().split('/').pop()}: ${event.message}`); }));
  setTimeout(() => { log('ZAMAN AŞIMI'); app.exit(1); }, 150_000);

  try {
    log('sürümler', process.versions.electron, process.getSystemVersion(), 'ekranlar', screen.getAllDisplays().map((d) => ({ bounds: d.bounds, work: d.workArea, scale: d.scaleFactor })));
    log('tepsi', getTray().getBounds(), 'kısayol kayıtlı', globalShortcut.isRegistered('Control+Alt+N'), 'açılışta başlat', app.getLoginItemSettings());
    log('veri', store.path, 'dil', app.getPreferredSystemLanguages());

    showPanel();
    await wait(2500);
    await shot('1-panel');
    view('panel')[0].webContents.send('page', 'stats');
    await wait(1200);
    await shot('2-stats');
    view('panel')[0].close();
    await wait(500);

    const topic = store.categories()[0];
    setSetting('widgetLeft', false);
    api['settings.set']('widgetStyle', 'tag');
    focus.start({ topic, goal: 'Kaba kurgu', newTodos: [['Altyazıları yerleştir', 'Tek satır'], ['Sesi temizle', '']], work: 50, rest: 10 });
    focus.session.start -= 1234;
    await wait(2000);
    log('etiket penceresi', widget.win.getBounds(), 'görünür', widget.win.isVisible());
    await shot('3-tag');

    // Üzerine gelince ayrıntı paneli açılır, çekilince kapanır
    const tag = await centre(widget.win, '.tag');
    const b = widget.win.getBounds();
    await mouse(`move ${tag.x - 300} ${tag.y + 300}`, 'sleep 300', `move ${b.x + 10} ${b.y + 8}`);
    await wait(600);
    log('gölge payında fare tutuluyor mu (false beklenir)', widget.over, 'panel', widget.detailOpen);
    await mouse(`move ${tag.x - 4} ${tag.y}`, 'sleep 100', `move ${tag.x} ${tag.y}`);
    await wait(1500);
    log('etiketin üzerinde: fare tutuluyor (true beklenir)', widget.over, 'ayrıntı paneli açık (true beklenir)', widget.detailOpen, widget.detail.getBounds());
    await shot('4-detail');
    await mouse(`move ${tag.x - 700} ${tag.y + 300}`);
    await wait(1200);
    log('fare çekilince panel kapandı (false beklenir)', widget.detailOpen);

    // Sürükleyip bırakınca en yakın kenara yapışır
    const work = display.workArea;
    await mouse(`move ${tag.x} ${tag.y}`, 'sleep 150', 'down', 'sleep 100', `move ${tag.x - 40} ${tag.y + 20}`, 'sleep 80', `move ${tag.x - 400} ${tag.y + 100}`, 'sleep 80',
      `move ${work.x + 300} ${tag.y + 200}`, 'sleep 150', 'up');
    await wait(1200);
    log('sola sürüklendi: solda (true beklenir)', !!getSettings().widgetLeft, widget.win.getBounds(), 'tagY', getSettings().tagY);
    await shot('5-tag-left');
    await mouse(`move ${work.x + 700} ${work.y + 500}`);
    await wait(600);

    // İnce şerit: yalnız şeridin üzerine gelince açılır
    api['settings.set']('widgetStyle', 'strip');
    await wait(1800);
    const sb = widget.win.getBounds();
    await mouse(`move ${sb.x + 120} ${sb.y + 200}`);
    await wait(1000);
    log('şerit penceresi', sb, 'şeridin 120 nokta yanında panel (false beklenir)', widget.detailOpen);
    const track = await centre(widget.win, '.track');
    await mouse(`move ${track.x - 30} ${sb.y + 200}`, 'sleep 100', `move ${track.x + 3} ${sb.y + 210}`);
    await wait(1500);
    log('şeridin üzerinde panel (true beklenir)', widget.detailOpen);
    await shot('6-strip-detail');
    await mouse(`move ${work.x + 900} ${work.y + 500}`);
    await wait(1000);

    // Kapsül: duraklat düğmesi tıklanır
    api['settings.set']('widgetStyle', 'capsule');
    await wait(1800);
    const pause = await centre(widget.win, '.pause');
    await mouse(`move ${pause.x - 3} ${pause.y}`, 'sleep 150', `move ${pause.x} ${pause.y}`, 'sleep 250', 'down', 'sleep 60', 'up');
    await wait(900);
    log('kapsül: fare tutuluyor', widget.over, 'düğme', pause, widget.win.getBounds());
    log('kapsülde duraklat tıklandı: evre (paused beklenir)', focus.phase);
    await shot('7-capsule-paused');
    focus.resume();
    await mouse(`move ${work.x + 900} ${work.y + 600}`);
    for (const style of ['card', 'ring']) { api['settings.set']('widgetStyle', style); await wait(1500); await shot('8-' + style); }

    // Mola hatırlatması: ekran nabzı ve mola sorusu
    pulseScreens(); setNudge(true);
    await wait(450);
    await shot('9-pulse');
    await wait(1500);
    await shot('9-nudge');
    const keep = await centre(widget.win, '.btn.secondary');
    await mouse(`move ${keep.x - 3} ${keep.y}`, 'sleep 150', `move ${keep.x} ${keep.y}`, 'sleep 250', 'down', 'sleep 60', 'up');
    await wait(800);
    log('Devam et tıklandı: soru kapandı (false beklenir)', widget.nudging);

    // Mola ekranı ve acil durum
    focus.finish();
    await wait(3000);
    const rest = view('rest');
    log('mola pencereleri', rest.map((w) => ({ bounds: w.getBounds(), visible: w.isVisible(), focused: w.isFocused(), top: w.isAlwaysOnTop() })));
    await shot('10-rest');
    const main = rest.find((w) => w.webContents.getURL().includes('content'));
    const toggle = await centre(main, '.stretch-toggle');
    await mouse(`move ${toggle.x} ${toggle.y}`, 'sleep 200', 'down', 'sleep 60', 'up');
    await wait(2000);
    await shot('11-rest-stretching');
    const emergency = await centre(main, '.emergency');
    await mouse(`move ${emergency.x} ${emergency.y}`, 'sleep 200', 'down', 'sleep 1800', 'up');
    await wait(1500);
    log('acil durum basılı tutuldu: mola penceresi kaldı mı (0 beklenir)', view('rest').length, 'evre (rest beklenir)', focus.phase, 'kayıt', store.lastSession().emergency);
    await shot('12-after-emergency');
    focus.endRest(false);
    await wait(2000);
    log('mola bitti: yeni oturum penceresi', view('newsession').map((w) => ({ bounds: w.getBounds(), visible: w.isVisible(), focused: w.isFocused() })));
    await shot('13-newsession');
    view('newsession').forEach((w) => w.destroy());
    showStretch();
    await wait(2500);
    await shot('14-stretch');
    log('hatalar', errors.length ? errors : 'yok');
    log('BİTTİ');
  } catch (error) {
    log('HATA', error.stack);
  }
  app.exit(0);
};
