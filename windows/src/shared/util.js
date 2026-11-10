// Dil ve biçimlendirme. Hem ana süreçte (require) hem pencerelerde (script) kullanılır.
// Zamanlar her yerde saniye cinsinden Unix zamanıdır; veritabanı macOS sürümüyle aynı biçimdedir.
(function (root) {
  let turkish = false;
  const pad2 = (n) => String(n).padStart(2, '0');
  const date = (sec) => new Date(sec * 1000);
  const sec = (d) => d.getTime() / 1000;

  const TEMPLATES = {
    dMMMMEEEE: { day: 'numeric', month: 'long', weekday: 'long' },
    dMMMM: { day: 'numeric', month: 'long' },
    dMMM: { day: 'numeric', month: 'short' },
    dMMMyyyy: { day: 'numeric', month: 'short', year: 'numeric' },
    MMMMyyyy: { month: 'long', year: 'numeric' },
    yyyy: { year: 'numeric' },
    EEE: { weekday: 'short' },
    EEEd: { weekday: 'short', day: 'numeric' },
  };

  const U = {
    setTurkish(on) { turkish = !!on; },
    isTurkish: () => turkish,
    /** Metnin Türkçesi ve İngilizcesi yan yana yazılır; seçili dile göre biri döner. */
    T: (tr, en) => (turkish ? tr : en),
    locale: () => (turkish ? 'tr-TR' : 'en-US'),
    upper: (s) => s.toLocaleUpperCase(turkish ? 'tr-TR' : 'en-US'),
    pad2,
    nowSec: () => Date.now() / 1000,

    dayKey(s) { const d = date(s); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; },
    startOfDay(s) { const d = date(s); return sec(new Date(d.getFullYear(), d.getMonth(), d.getDate())); },
    /** Takvim günü ekler; yaz saati geçişinde gün 23 ya da 25 saat sürse de doğru günü verir. */
    addDays(s, n) { const d = date(s); return sec(new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes(), d.getSeconds())); },
    addMonths(s, n) { const d = date(s); return sec(new Date(d.getFullYear(), d.getMonth() + n, d.getDate())); },
    daysBetween(a, b) { return Math.round((U.startOfDay(b) - U.startOfDay(a)) / 86400); },
    mondayOf(s) { const d = date(U.startOfDay(s)); return U.addDays(sec(d), -((d.getDay() + 6) % 7)); },
    isToday: (s) => U.dayKey(s) === U.dayKey(U.nowSec()),
    /** ISO hafta numarası ve o haftanın yılı. */
    isoWeek(s) {
      const d = date(s), t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
      t.setUTCDate(t.getUTCDate() + 4 - (t.getUTCDay() || 7));
      const year = t.getUTCFullYear();
      return { year, week: Math.ceil(((t - Date.UTC(year, 0, 1)) / 86400000 + 1) / 7) };
    },
    /** Günün saati, ondalıklı (14:30 → 14.5); duvar saatini verir. */
    hourOfDay(s) { const d = date(s); return d.getHours() + d.getMinutes() / 60 + d.getSeconds() / 3600; },

    percent: (v) => (turkish ? `%${v}` : `${v}%`),
    /** 95 → "1 sa 35 dk" / "1 h 35 min" */
    formatMinutes(m) {
      const h = Math.floor(m / 60), r = m % 60;
      if (h === 0) return turkish ? `${r} dk` : `${r} min`;
      return turkish ? `${h} sa ${pad2(r)} dk` : `${h} h ${pad2(r)} min`;
    },
    /** 95 → "1s 35d" / "1h 35m" */
    formatMinutesShort(m) {
      const h = Math.floor(m / 60), r = m % 60;
      if (h === 0) return turkish ? `${r}d` : `${r}m`;
      return turkish ? `${h}s ${pad2(r)}d` : `${h}h ${pad2(r)}m`;
    },
    /** 2052 sn → "34:12" */
    formatClock(s) { s = Math.max(0, Math.floor(s)); return `${pad2(Math.floor(s / 60))}:${pad2(s % 60)}`; },
    formatTime(s) { const d = date(s); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`; },
    formatDate: (s, template) => new Intl.DateTimeFormat(U.locale(), TEMPLATES[template]).format(date(s)),

    /** Algılanan açıklık (CIE L*, 0 siyah – 100 beyaz). */
    lightness(hex) {
      const v = parseInt(String(hex).replace('#', ''), 16) || 0;
      const lin = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));
      const y = 0.2126 * lin(((v >> 16) & 255) / 255) + 0.7152 * lin(((v >> 8) & 255) / 255) + 0.0722 * lin((v & 255) / 255);
      return y > 0.008856 ? 116 * Math.cbrt(y) - 16 : 903.3 * y;
    },
    /** Kategori karesinin üstündeki simgenin rengi: açık zeminde siyah, koyu zeminde beyaz. */
    inkOn: (hex) => (U.lightness(hex) > 66 ? '#000000' : '#ffffff'),
    palette: ['#e5675c', '#e8894a', '#e6b450', '#dccf6e', '#93c46c', '#4fbf95', '#4bb3c9', '#4c8df0',
      '#6f7cf2', '#9a7bea', '#de7ab2', '#c98f73', '#a0a3ad', '#e9e9ee', '#3a3f4d'],

    todoEmoji: ['🤓', '🙂‍↔️', '🥳'],
    sessionMinutes: (s) => Math.floor(s.focusSeconds / 60),
    /** "50 + 10" ya da serbest oturum için "serbest". */
    rhythm: (s) => (s.workMinutes === 0 ? U.T('serbest', 'free') : `${s.workMinutes} + ${s.restMinutes}`),
    sum: (list, f) => list.reduce((a, x) => a + f(x), 0),
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = U;
  else Object.assign(root, U);
})(this);
