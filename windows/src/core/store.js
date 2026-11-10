// Yerel kayıt: %APPDATA%\Houra\houra.sqlite. Şema macOS sürümüyle aynıdır; dosya iki sürüm arasında taşınabilir.
const { DatabaseSync } = require('node:sqlite');

const SESSION_COLS = 'id, category_id, goal, work_min, rest_min, start, end, focus_sec, note, emergency';
const TODO_COLS = 'id, day, title, detail, state, session_id';

class Store {
  /** onChange: veri her değiştiğinde çağrılır (pencereler yeniden okur). */
  constructor(file, { defaultCategory = 'General', onChange = () => {} } = {}) {
    this.path = file;
    this.onChange = onChange;
    this.db = new DatabaseSync(file);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL,
          emoji TEXT, icon TEXT, position INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS todos (id INTEGER PRIMARY KEY, day TEXT NOT NULL, title TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '',
          state INTEGER NOT NULL DEFAULT 0, session_id INTEGER, position INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS sessions (id INTEGER PRIMARY KEY, category_id INTEGER NOT NULL, goal TEXT NOT NULL,
          work_min INTEGER NOT NULL, rest_min INTEGER NOT NULL, start REAL NOT NULL, end REAL, focus_sec INTEGER NOT NULL DEFAULT 0,
          note TEXT NOT NULL DEFAULT '', emergency INTEGER NOT NULL DEFAULT 0);
      CREATE INDEX IF NOT EXISTS todos_day ON todos(day);
      CREATE INDEX IF NOT EXISTS sessions_start ON sessions(start);`);
    if (!this.all('PRAGMA table_info(categories)').some((c) => c.name === 'icon_color')) this.db.exec('ALTER TABLE categories ADD COLUMN icon_color TEXT');
    if (this.categories().length === 0) this.addCategory({ name: defaultCategory, color: '#4c8df0' });
  }

  close() { this.db.close(); }
  all(sql, ...values) { return this.db.prepare(sql).all(...values); }
  run(sql, ...values) { return Number(this.db.prepare(sql).run(...values).lastInsertRowid); }

  // Kategoriler

  categories() {
    return this.all('SELECT id, name, color, emoji, icon, icon_color FROM categories ORDER BY position, id')
      .map((r) => ({ id: r.id, name: r.name, color: r.color, emoji: r.emoji, icon: r.icon, iconColor: r.icon_color }));
  }

  addCategory({ name, color, emoji = null, icon = null }) {
    const id = this.run('INSERT INTO categories (name, color, emoji, icon, position) VALUES (?, ?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM categories))',
      name, color, emoji, icon);
    this.onChange();
    return id;
  }

  updateCategory(c) {
    this.run('UPDATE categories SET name = ?, color = ?, emoji = ?, icon = ?, icon_color = ? WHERE id = ?',
      c.name, c.color, c.emoji ?? null, c.icon ?? null, c.iconColor ?? null, c.id);
    this.onChange();
  }

  deleteCategory(id) { this.run('DELETE FROM categories WHERE id = ?', id); this.onChange(); }

  // Yapılacaklar

  todo(r) { return { id: r.id, day: r.day, title: r.title, detail: r.detail, state: r.state, sessionID: r.session_id }; }
  todos(day) { return this.all(`SELECT ${TODO_COLS} FROM todos WHERE day = ? ORDER BY position, id`, day).map(this.todo); }
  sessionTodos(session) { return this.all(`SELECT ${TODO_COLS} FROM todos WHERE session_id = ? ORDER BY position, id`, session).map(this.todo); }

  addTodo(day, title, detail = '') {
    const id = this.run('INSERT INTO todos (day, title, detail, position) VALUES (?, ?, ?, (SELECT IFNULL(MAX(position), 0) + 1 FROM todos WHERE day = ?))',
      day, title, detail, day);
    this.onChange();
    return id;
  }

  setTodoState(id, state) { this.run('UPDATE todos SET state = ? WHERE id = ?', state, id); this.onChange(); }
  attachTodo(id, session) { this.run('UPDATE todos SET session_id = ? WHERE id = ?', session, id); this.onChange(); }
  deleteTodo(id) { this.run('DELETE FROM todos WHERE id = ?', id); this.onChange(); }

  // Oturumlar

  session(r) {
    return { id: r.id, categoryID: r.category_id, goal: r.goal, workMinutes: r.work_min, restMinutes: r.rest_min, start: r.start,
      end: r.end, focusSeconds: r.focus_sec, note: r.note, emergency: r.emergency !== 0 };
  }

  startSession(category, goal, work, rest, at = Date.now() / 1000) {
    const id = this.run('INSERT INTO sessions (category_id, goal, work_min, rest_min, start) VALUES (?, ?, ?, ?, ?)', category, goal, work, rest, at);
    this.onChange();
    return id;
  }

  finishSession(id, end, focusSeconds) { this.run('UPDATE sessions SET end = ?, focus_sec = ? WHERE id = ?', end, Math.floor(focusSeconds), id); this.onChange(); }
  setFocus(id, seconds) { this.run('UPDATE sessions SET focus_sec = ? WHERE id = ?', Math.floor(seconds), id); }
  setNote(id, note) { this.run('UPDATE sessions SET note = ? WHERE id = ?', note, id); }

  /** Yanlış açılmış oturumun kategorisini, hedefini ve notunu sonradan düzeltir. */
  updateSession(id, category, goal, note) {
    this.run('UPDATE sessions SET category_id = ?, goal = ?, note = ? WHERE id = ?', category, goal, note, id);
    this.onChange();
  }

  /** Oturumu siler; bağlı görevler günün listesinde kalır, yalnız oturumdan ayrılır. */
  deleteSession(id) {
    this.run('UPDATE todos SET session_id = NULL WHERE session_id = ?', id);
    this.run('DELETE FROM sessions WHERE id = ?', id);
    this.onChange();
  }

  markEmergency(id) { this.run('UPDATE sessions SET emergency = 1 WHERE id = ?', id); this.onChange(); }

  /** [from, to) aralığında başlamış oturumlar, eskiden yeniye. */
  sessions(from = 0, to = Number.MAX_SAFE_INTEGER) {
    return this.all(`SELECT ${SESSION_COLS} FROM sessions WHERE start >= ? AND start < ? ORDER BY start`, from, to).map(this.session);
  }

  sessionByID(id) { return this.all(`SELECT ${SESSION_COLS} FROM sessions WHERE id = ?`, id).map(this.session)[0] ?? null; }
  lastSession() { return this.all(`SELECT ${SESSION_COLS} FROM sessions ORDER BY start DESC LIMIT 1`).map(this.session)[0] ?? null; }
}

module.exports = { Store };
