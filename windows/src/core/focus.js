// Oturum motoru: odak, duraklatma, mola. Bütün pencereler bu tek kaynağı izler.
const U = require('../shared/util');

/** Serbest oturum: sayaç ileri akar, süre dolmaz; her bu kadar saniyede bir mola hatırlatılır. */
const FREE_NUDGE_SECONDS = 50 * 60;

class Focus {
  /** hooks: onChange, onRestStart, onRestEnd(early), onBreakNudge, onEmergency; now saniye döndürür (testte sahte saat). */
  constructor(store, hooks = {}, now = U.nowSec) {
    this.store = store;
    this.hooks = { onChange() {}, onRestStart() {}, onRestEnd() {}, onBreakNudge() {}, onEmergency() {}, ...hooks };
    this.clockNow = now;
    this.reset();
    this.closeAbandoned();
  }

  reset() {
    this.phase = 'idle'; this.session = null; this.topic = null; this.todos = []; this.note = '';
    this.pausedAt = null; this.pausedTotal = 0; this.restEnd = null; this.nudges = 0;
  }

  // Okuma

  /** Ritmi 0 dakika olan oturum serbesttir. */
  get isFree() { return this.session?.workMinutes === 0; }
  get workSeconds() { return this.isFree ? FREE_NUDGE_SECONDS : (this.session?.workMinutes ?? 50) * 60; }
  get restSeconds() { return (this.session?.restMinutes ?? 10) * 60; }
  get elapsed() { return this.session ? Math.max(0, (this.pausedAt ?? this.clockNow()) - this.session.start - this.pausedTotal) : 0; }
  get remaining() { return Math.max(0, this.workSeconds - Math.floor(this.elapsed)); }
  /** Ekranda yazan süre: serbestte geçen, değilse kalan. */
  get clock() { return this.isFree ? Math.floor(this.elapsed) : this.remaining; }
  get progress() { return Math.min(1, this.elapsed / this.workSeconds); }
  get restRemaining() { return Math.max(0, Math.ceil((this.restEnd ?? this.clockNow()) - this.clockNow())); }
  get plannedEnd() { return this.isFree || !this.session ? null : this.session.start + this.workSeconds + this.pausedTotal; }
  get activeTodo() { return this.todos.find((t) => t.state === 1) ?? null; }
  get focusSeconds() { return this.isFree ? Math.floor(this.elapsed) : Math.min(this.workSeconds, Math.floor(this.elapsed)); }

  /** Pencerelere giden anlık görüntü. */
  snapshot() {
    return {
      phase: this.phase, session: this.session, topic: this.topic, todos: this.todos, note: this.note, now: this.clockNow(),
      isFree: this.isFree, elapsed: this.elapsed, remaining: this.remaining, clock: this.clock, progress: this.progress,
      restRemaining: this.restRemaining, restSeconds: this.restSeconds, plannedEnd: this.plannedEnd,
      // Küçük görünümlerde yazan: o an yapılan görev, yoksa oturumun hedefi.
      headline: this.activeTodo?.title ?? this.session?.goal ?? '',
    };
  }

  // Yazma

  start({ topic, goal = '', todoIDs = [], newTodos = [], work, rest }) {
    if (this.phase !== 'idle') this.stop();
    const at = this.clockNow();
    const id = this.store.startSession(topic.id, goal || topic.name, work, rest, at);
    const ids = [...todoIDs, ...newTodos.map(([title, detail]) => this.store.addTodo(U.dayKey(at), title, detail))];
    ids.forEach((todo, i) => { this.store.attachTodo(todo, id); this.store.setTodoState(todo, i === 0 ? 1 : 0); });
    this.reset();
    this.topic = topic;
    this.session = this.store.sessionByID(id);
    this.todos = this.store.sessionTodos(id);
    this.phase = 'focus';
    this.hooks.onChange();
  }

  pause() {
    if (this.phase !== 'focus') return;
    this.pausedAt = this.clockNow(); this.phase = 'paused'; this.hooks.onChange();
  }

  resume() {
    if (this.phase !== 'paused') return;
    this.pausedTotal += this.clockNow() - this.pausedAt; this.pausedAt = null; this.phase = 'focus'; this.hooks.onChange();
  }

  /** Oturumu bitirir ve molaya geçer (süre dolunca ya da Bitir'e basınca). */
  finish() {
    if (!this.session || (this.phase !== 'focus' && this.phase !== 'paused')) return;
    if (this.phase === 'paused') this.resume();
    this.store.finishSession(this.session.id, this.clockNow(), this.focusSeconds);
    this.restEnd = this.clockNow() + this.restSeconds;
    this.phase = 'rest';
    this.hooks.onChange();
    this.hooks.onRestStart();
  }

  /** Molayı bitirir. */
  endRest(emergency = false) {
    if (this.phase !== 'rest') return;
    if (emergency) this.store.markEmergency(this.session.id);
    this.reset();
    this.hooks.onChange();
    this.hooks.onRestEnd(emergency);
  }

  /** Acil durum: mola sürer ama ekran bırakılır; kayda işlenir, tepsi menüsünden molaya dönülebilir. */
  emergencyExit() {
    if (this.phase !== 'rest') return;
    this.store.markEmergency(this.session.id);
    this.hooks.onEmergency();
  }

  /** Molasız tamamen durdurur (yeni oturum eskisinin üstüne başlarken). */
  stop() {
    if (this.session && (this.phase === 'focus' || this.phase === 'paused')) this.store.finishSession(this.session.id, this.clockNow(), this.focusSeconds);
    this.reset();
    this.hooks.onChange();
  }

  /** Süren oturumun kategorisini ve hedefini düzeltir. */
  retag(topic, goal) {
    if (!this.session) return;
    this.session = { ...this.session, categoryID: topic.id, goal: goal || topic.name };
    this.topic = topic;
    this.store.updateSession(this.session.id, topic.id, this.session.goal, this.note);
    this.hooks.onChange();
  }

  setNote(text) {
    this.note = text;
    if (this.session) this.store.setNote(this.session.id, text);
  }

  /** 🤓 → 🙂‍↔️ → 🥳 → 🤓. Aynı anda tek görev "yapılıyor" olabilir. */
  setTodo(id, state) {
    if (state === 1) this.todos.filter((t) => t.state === 1 && t.id !== id).forEach((t) => this.store.setTodoState(t.id, 0));
    this.store.setTodoState(id, state);
    this.todos = this.session ? this.store.sessionTodos(this.session.id) : [];
    this.hooks.onChange();
  }

  tick() {
    if (this.phase === 'focus' && !this.isFree && this.remaining === 0) this.finish();
    if (this.phase === 'focus' && this.isFree) {
      const mark = Math.floor(this.elapsed / FREE_NUDGE_SECONDS);
      if (mark > this.nudges) { this.nudges = mark; this.hooks.onBreakNudge(); }
      // Uygulama kapanırsa geçen süre kaybolmasın diye dakikada bir kaydedilir.
      if (Math.floor(this.elapsed) % 60 === 0) this.store.setFocus(this.session.id, this.elapsed);
    }
    if (this.phase === 'rest' && this.restRemaining === 0) this.endRest(false);
  }

  /** Uygulama oturum sürerken kapandıysa: yarım kalan oturum planlanan süreyle kapatılır. */
  closeAbandoned() {
    const now = this.clockNow();
    for (const s of this.store.sessions(now - 3 * 86400).filter((x) => x.end == null)) {
      const planned = s.workMinutes === 0 ? s.focusSeconds : s.workMinutes * 60;   // serbest: son kaydedilen süre
      const end = Math.min(now, s.start + planned);
      this.store.finishSession(s.id, end, end - s.start);
    }
  }
}

module.exports = { Focus, FREE_NUDGE_SECONDS };
