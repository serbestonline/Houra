// Haftalık görev dosyası (örneğin Obsidian'daki haftalık not). Yalnız okunur, hiçbir şey yazılmaz.
// Yol bir şablondur; her okumada bugünün tarihiyle çözülür, böylece hafta dönünce kendiliğinden yeni dosyaya geçer.
//   {YYYY} ISO hafta yılı · {WW} iki haneli ISO hafta · {W} hafta · {MM} ay · * herhangi bir klasör adı
// Örnek: C:\Users\ad\Obsidian\Kasa\AA Daily\* - {YYYY}\Hafta {WW}\Hafta {WW} - Yapılacaklar.md
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const U = require('../shared/util');

/** Şablonu verilen tarihe göre çözer ve var olan dosyayı bulur. Birden fazla eşleşme varsa en son değişeni. */
function file(template, at = U.nowSec()) {
  const { week, year } = U.isoWeek(at);
  let p = template.trim()
    .replaceAll('{YYYY}', String(year)).replaceAll('{WW}', U.pad2(week)).replaceAll('{W}', String(week))
    .replaceAll('{MM}', U.pad2(new Date(at * 1000).getMonth() + 1));
  if (p === '~' || p.startsWith('~/') || p.startsWith('~\\')) p = path.join(os.homedir(), p.slice(1));
  if (!path.isAbsolute(p)) return null;
  p = path.normalize(p);
  const root = path.parse(p).root;
  let candidates = [root];
  for (const part of p.slice(root.length).split(path.sep).filter(Boolean)) {
    const next = [];
    for (const base of candidates) {
      if (part.includes('*')) {
        const pattern = new RegExp('^' + part.split('*').map((x) => x.replace(/[.+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$');
        let names = [];
        try { names = fs.readdirSync(base); } catch { /* okunamayan klasör atlanır */ }
        next.push(...names.filter((n) => pattern.test(n)).map((n) => path.join(base, n)));
      } else if (fs.existsSync(path.join(base, part))) next.push(path.join(base, part));
    }
    candidates = next;
    if (candidates.length === 0) return null;
  }
  const modified = (f) => { try { return fs.statSync(f).mtimeMs; } catch { return 0; } };
  return candidates.reduce((best, f) => (modified(f) > modified(best) ? f : best));
}

/** "[[Kişi|Takma ad]]" → "Takma ad", "#etiket" ve "✅ tarih" atılır, "→ [[Düğüm]]" gibi son ekler kesilir. */
function clean(s) {
  let t = s;
  for (const cut of [' → ', ' ✅']) if (t.includes(cut)) t = t.slice(0, t.indexOf(cut));
  t = t.replace(/\[\[(.*?)\]\]/g, (_m, inner) => inner.split('|').filter(Boolean).pop() ?? inner);
  return t.split(' ').filter((w) => w && !(w.startsWith('#') && w.length > 1)).join(' ').trim();
}

/** Başlığı ya da etiketi kategori adıyla eşleştirir; büyük-küçük harf ve sondaki "s" önemsenmez (Maestrock ~ Maestrocks). */
function match(heading, tag, topics) {
  const norm = (s) => (s.toLocaleLowerCase('tr-TR').match(/[\p{L}\p{N}]/gu) ?? []).join('').replace(/s$/, '');
  for (const key of [heading, tag ?? '']) {
    if (!key) continue;
    const t = topics.find((x) => norm(x.name) === norm(key));
    if (t) return t.id;
  }
  return null;
}

/** Açık ve bekleyen görevler. Bitmiş, iptal ya da başka haftaya taşınmış görevler atlanır. */
function parse(text, topics) {
  const out = [];
  let heading = '', parent = null;
  text.split(/\r?\n/).forEach((raw, n) => {
    const line = raw.replaceAll('    ', '\t');
    if (line.startsWith('#')) { heading = line.replace(/^#+/, '').trim(); parent = null; return; }
    const indent = line.match(/^\t*/)[0].length;
    const body = line.slice(indent);
    if (!body.startsWith('- [') || body.length <= 5) {
      // "- 1.0" gibi görev olmayan üst madde, altındaki görevlerin grubudur
      if (indent === 0 && body.startsWith('- ')) parent = clean(body.slice(2));
      return;
    }
    const state = body[3], rest = body.slice(6), title = clean(rest);
    if (indent === 0) parent = title;
    if (!' w/'.includes(state) || rest.includes('→ Hafta') || !title) return;
    const tag = rest.split(' ').find((w) => w.startsWith('#'))?.slice(1);
    out.push({ id: n, title, detail: indent > 0 ? (parent ?? '') : '', heading, topicID: match(heading, tag, topics),
      waiting: state === 'w', depth: indent > 0 ? 1 : 0 });
  });
  return out;
}

/** { file, tasks }: dosya bulunamazsa file null olur. */
function load(template, topics) {
  const f = template.trim() ? file(template) : null;
  let tasks = [];
  if (f) { try { tasks = parse(fs.readFileSync(f, 'utf8'), topics); } catch { /* dosya o an okunamadı */ } }
  return { file: f, name: f ? path.basename(f, path.extname(f)) : '', tasks };
}

module.exports = { file, clean, match, parse, load };
