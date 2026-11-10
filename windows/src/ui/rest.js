// Mola ekranı: bütün ekranları kaplayan, siyah-beyaz ışıkların aktığı sahne. Yalnız 1,5 sn basılı tutulan
// "Acil durum" ile erken dönülür; süre bitince kendiliğinden kapanır ve yeni oturum sorulur.
// Aynı sayfa ?stretch=1 ile moladan bağımsız esneme penceresi olur; içeriksiz açılınca yalnız ışıklar görünür (öteki ekranlar).
const root = document.getElementById('root');
const groups = stretchGroups();
let stretching = false, group = 0, index = 0;

/** Siyah zeminde yavaşça akan üç gri-beyaz ışık. Yarı çözünürlükte çizilir; yumuşak geçişlerde fark görünmez. */
function driftingLights(canvas) {
  const ctx = canvas.getContext('2d');
  const lights = [[1.0, 0.16, 0.42, 0.071, 0.0], [0.6, 0.22, 0.52, 0.055, 2.1], [0.85, 0.12, 0.34, 0.09, 4.0]];   // açıklık, saydamlık, yarıçap, hız, faz
  const glow = (x, y, r, inner, outer) => {
    const g = ctx.createRadialGradient(x, y, inner, x, y, r);
    g.addColorStop(0, outer[0]); g.addColorStop(1, outer[1]);
    ctx.fillStyle = g; ctx.fillRect(0, 0, canvas.width, canvas.height);
  };
  (function frame() {
    const w = canvas.width = Math.ceil(innerWidth / 2), ht = canvas.height = Math.ceil(innerHeight / 2), span = Math.max(w, ht), t = Date.now() / 1000;
    ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, ht);
    ctx.globalCompositeOperation = 'screen';
    for (const [v, a, r0, sp, ph] of lights) {
      const c = Math.round(v * 255);
      glow(w * (0.5 + 0.42 * Math.sin(t * sp * 2 * Math.PI + ph)), ht * (0.5 + 0.38 * Math.cos(t * sp * 1.7 * Math.PI + ph * 1.3)),
        span * r0 * (1 + 0.15 * Math.sin(t * sp * 3 + ph)), 0, [`rgba(${c},${c},${c},${a})`, `rgba(${c},${c},${c},0)`]);
    }
    ctx.globalCompositeOperation = 'source-over';
    glow(w / 2, ht * 0.45, span * 0.8, span * 0.25, ['rgba(0,0,0,0)', 'rgba(0,0,0,.7)']);
    requestAnimationFrame(frame);
  })();
}

/** Mola ekranının sol yarısı ve esneme penceresi. Sayaç ve set takibi yok: her hareketin önerilen set ve
 *  tekrar sayısı yazar, oklarla hareketler arasında geçilir. */
function stretchGuide() {
  const moves = groups[group].moves, count = moves.length, i = ((index % count) + count) % count, move = moves[i];
  const go = (n) => { index = n; drawGuide(); };
  return h('div.guide', null,
    segmented(groups.map((g) => g.name), group, (g) => { group = g; go(0); }),
    h('img.clip', { src: `${houra.boot.stretchDir}/${move.id}.gif`, alt: '' }),   // yeni öğe: animasyon hareketin başından oynar
    h('div.count', null, eyebrow(`${i + 1} / ${count}`)),
    h('h2', null, move.name),
    h('div.dose', null, T(`Önerilen: ${move.sets} set × ${move.dose}`, `Suggested: ${move.sets} sets × ${move.dose}`)),
    h('p', null, move.hint),
    h('div.row.gap18.steps', null, h('button.step', { onclick: () => go(i - 1) }, glyph('left', 12, 1.8)), h('button.step', { onclick: () => go(i + 1) }, glyph('right', 12, 1.8))));
}
function drawGuide() { document.getElementById('guide').replaceChildren(stretchGuide()); }

function restScreen() {
  // Esneme açılınca hareket solda belirir, zamanlayıcı sağa kayar.
  const toggle = h('button.stretch-toggle', { onclick: () => {
    stretching = !stretching;
    document.body.classList.toggle('stretching', stretching);
    toggle.lastChild.textContent = stretching ? T('Hareketleri kapat', 'Hide stretches') : T('Esneme hareketleri', 'Stretches');
    if (stretching) { group = 0; index = 0; drawGuide(); }
  } }, glyph('stretch', 14), h('span', null, T('Esneme hareketleri', 'Stretches')));

  // 1,5 saniye basılı tutulunca ekran bırakılır.
  let timer = null;
  const emergency = h('button.emergency', {
    onpointerdown: () => { emergency.classList.add('holding'); timer = setTimeout(() => { emergency.classList.remove('holding'); call('focus.emergencyExit'); }, 1500); },
  }, h('i'), h('span', null, T('Acil durum', 'Emergency')));
  const letGo = () => { clearTimeout(timer); emergency.classList.remove('holding'); };
  for (const event of ['pointerup', 'pointerleave', 'pointercancel']) emergency.addEventListener(event, letGo);

  return [
    h('div.stage', null,
      h('div.side', { id: 'guide' }),
      h('div.timer', null, h('div.timer-inner', null,
        h('div.reveal', null, eyebrow(T('Mola', 'Break'))),
        h('h1.reveal', null, T('Kalk, biraz uzaklaş.', 'Stand up, step away.')),
        h('p.reveal', null, T('Su iç, pencereden dışarı bak, birkaç adım at. Ekran seni bekler.', 'Drink some water, look out the window, take a few steps. The screen will wait.')),
        h('div.rest-clock.reveal', { id: 'clock' }),
        h('div.reveal', null, toggle)))),
    emergency];
}

const canvas = h('canvas.lights');
root.append(canvas);
driftingLights(canvas);
if (query.get('stretch')) {
  document.body.classList.add('stretch-window');
  root.append(h('div.drag-strip'), h('div.stage', null, h('div.side', { id: 'guide' })));
  drawGuide();
} else if (query.get('content')) {
  root.append(...restScreen());
  const show = (s) => { document.getElementById('clock').textContent = formatClock(s.restRemaining); };
  houra.on('state', show);
  call('state').then(show);
}
requestAnimationFrame(() => document.body.classList.add('shown'));
houra.on('fadeout', () => document.body.classList.remove('shown'));
