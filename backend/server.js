require('dotenv').config();
const express = require('express');
const cors = require('cors');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

// ---- Config (env vars) ----
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET;
const NODE_ENV = process.env.NODE_ENV || 'development';
const DATA_DIR = path.join(__dirname, 'data');

if (!JWT_SECRET) {
  console.error('FATAL: JWT_SECRET env var is required in all environments');
  process.exit(1);
}
const SECRET = JWT_SECRET;

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

// ---- Simple JSON DB (single-writer, file-per-table) ----
// For production multi-process, swap this with better-sqlite3 or PostgreSQL.

const DB = {
  _tables: {},
  _getFile(name) {
    const safe = name.replace(/[^a-zA-Z0-9_]/g, '_');
    return path.join(DATA_DIR, `${safe}.json`);
  },
  read(name) {
    const fp = DB._getFile(name);
    try { DB._tables[name] = JSON.parse(fs.readFileSync(fp, 'utf8')); }
    catch { DB._tables[name] = []; }
    return DB._tables[name];
  },
  write(name, data) {
    DB._tables[name] = data;
    fs.writeFileSync(DB._getFile(name), JSON.stringify(data, null, 2));
  },
};

let _idCounter = Date.now();
function genId() { return String(++_idCounter); }

// ---- AI Cache (in-memory, TTL 1h) ----
const aiCache = new Map();
const CACHE_TTL = 3600_000; // 1 hour
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of aiCache) { if (now - v.time > CACHE_TTL) aiCache.delete(k); }
}, 300_000);

function cacheKey(text, bookTitle) {
  return crypto.createHash('md5').update(`${text}|${bookTitle}`).digest('hex');
}

// ---- Text chunking ----
function chunkText(text, chunkSize = 500, overlap = 100) {
  const chunks = [];
  const paragraphs = text.split(/\n\n+/).filter(p => p.trim().length > 0);
  let current = '';
  for (const para of paragraphs) {
    if (current.length + para.length > chunkSize && current.length > 0) {
      chunks.push(current.trim());
      current = current.slice(-overlap) + '\n\n' + para;
    } else {
      current += (current ? '\n\n' : '') + para;
    }
  }
  if (current.trim()) chunks.push(current.trim());
  return chunks;
}

// ---- Auth middleware ----
function auth(req, res, next) {
  const h = req.headers.authorization;
  if (!h || !h.startsWith('Bearer ')) return res.status(401).json({ error: '未登录' });
  try { req.user = jwt.verify(h.split(' ')[1], SECRET); next(); }
  catch { res.status(401).json({ error: '登录已过期' }); }
}

const app = express();

// ---- Middleware ----
const allowedOrigins = process.env.CORS_ORIGINS
  ? process.env.CORS_ORIGINS.split(',').map(s => s.trim())
  : ['app://.', 'http://localhost:*', 'https://localhost:*'];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (mobile apps, curl, etc.)
    if (!origin) return callback(null, true);
    // Check against allowed patterns
    const allowed = allowedOrigins.some(pattern => {
      const regex = new RegExp('^' + pattern.replace(/\*/g, '.*').replace(/\./g, '\\.') + '$');
      return regex.test(origin);
    });
    if (allowed) return callback(null, true);
    callback(new Error('Not allowed by CORS'));
  }
}));
app.use(express.json({ limit: '10mb' }));
app.use(morgan(NODE_ENV === 'production' ? 'combined' : 'dev'));

// Rate limits
const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 20, message: { error: '请求太频繁，请稍后再试' } });
const apiLimiter = rateLimit({ windowMs: 60 * 1000, max: 60, message: { error: '请求太频繁' } });
app.use('/api/register', authLimiter);
app.use('/api/login', authLimiter);
app.use('/api/classes', apiLimiter);
app.use('/api/user_entries', apiLimiter);

// ---- Health ----
app.get('/api/health', (req, res) => res.json({ status: 'ok', env: NODE_ENV }));

// ---- Auth ----

app.post('/api/register', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: '邮箱和密码不能为空' });
  if (password.length < 6) return res.status(400).json({ error: '密码至少6位' });

  const users = DB.read('_users');
  if (users.find(u => u.email === email)) return res.status(409).json({ error: '该邮箱已注册' });

  const user = { id: genId(), email, password: bcrypt.hashSync(password, 10), created_at: new Date().toISOString() };
  users.push(user);
  DB.write('_users', users);

  const token = jwt.sign({ userId: user.id, email }, SECRET, { expiresIn: '30d' });
  res.status(201).json({ objectId: user.id, email, sessionToken: token, createdAt: user.created_at });
});

app.post('/api/login', (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: '邮箱和密码不能为空' });

  const user = (DB.read('_users')).find(u => u.email === email);
  if (!user || !bcrypt.compareSync(password, user.password)) {
    return res.status(401).json({ error: '邮箱或密码错误' });
  }
  const token = jwt.sign({ userId: user.id, email }, SECRET, { expiresIn: '30d' });
  res.json({ objectId: user.id, email, sessionToken: token });
});

// ---- Data CRUD (user-scoped) ----

function getTable(name) {
  const rows = DB.read(name);
  return { rows, name };
}

const USER_ENTRY_SOURCES = new Set(['highlight', 'thought', 'ai_explanation', 'manual']);

function normalizeTags(input) {
  if (Array.isArray(input)) {
    return [...new Set(input.map(v => String(v).trim()).filter(Boolean))];
  }
  if (typeof input !== 'string' || !input.trim()) return [];
  const raw = input.trim();
  try {
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed)) return normalizeTags(parsed);
  } catch {}
  return [...new Set(raw
    .split(',')
    .map(v => v.trim().replace(/^["'\[]+|["'\]]+$/g, ''))
    .filter(Boolean))];
}

function normalizeUserEntry(body, userId, existing = {}) {
  const now = new Date().toISOString();
  const source = USER_ENTRY_SOURCES.has(body.source) ? body.source : 'manual';
  const createdAt = body.created_at || body.createdAt || existing.created_at || now;

  return {
    ...existing,
    local_id: body.local_id || body.id || existing.local_id || genId(),
    user_id: userId,
    source,
    book_id: body.book_id || existing.book_id || '',
    book_title: body.book_title || existing.book_title || '',
    chapter_index: body.chapter_index || existing.chapter_index || '',
    chapter_title: body.chapter_title || existing.chapter_title || '',
    original_text: body.original_text || existing.original_text || '',
    user_input: body.user_input || existing.user_input || '',
    ai_explanation: body.ai_explanation || existing.ai_explanation || '',
    auto_tags: normalizeTags(body.auto_tags ?? existing.auto_tags),
    auto_summary: body.auto_summary || existing.auto_summary || '',
    metadata_json: body.metadata_json || existing.metadata_json || '',
    embedding: body.embedding || existing.embedding || '',
    created_at: createdAt,
    updatedAt: now,
  };
}

function matchesUserEntryFilters(row, query) {
  if (query.book_id && row.book_id !== query.book_id) return false;
  if (query.source && row.source !== query.source) return false;
  if (query.tag && !normalizeTags(row.auto_tags).includes(query.tag)) return false;

  const createdAt = row.created_at || row.createdAt || '';
  if (query.created_at && !createdAt.startsWith(query.created_at)) return false;
  if (query.created_at_from && createdAt < query.created_at_from) return false;
  if (query.created_at_to && createdAt > query.created_at_to) return false;
  return true;
}

// POST /api/user_entries — create one automatically captured reading entry.
app.post('/api/user_entries', auth, (req, res) => {
  const { rows, name } = getTable('user_entries');
  const entry = {
    objectId: genId(),
    ...normalizeUserEntry(req.body || {}, req.user.userId),
  };
  rows.push(entry);
  DB.write(name, rows);
  res.status(201).json(entry);
});

// GET /api/user_entries — list reading entries with MVP filters.
// Filters: book_id, source, tag, created_at, created_at_from, created_at_to, limit.
app.get('/api/user_entries', auth, (req, res) => {
  const { rows } = getTable('user_entries');
  let results = rows
    .filter(r => r.user_id === req.user.userId)
    .filter(r => matchesUserEntryFilters(r, req.query));

  results.sort((a, b) =>
    String(b.created_at || b.createdAt || '').localeCompare(String(a.created_at || a.createdAt || '')));

  const limit = parseInt(req.query.limit);
  if (limit > 0) results = results.slice(0, limit);

  res.json({ results });
});

// GET /api/classes/:table — auto-filtered by user
app.get('/api/classes/:table', auth, (req, res) => {
  const { rows } = getTable(req.params.table);
  let results = rows.filter(r => r.user_id === req.user.userId);

  if (req.query.where) {
    try {
      const w = JSON.parse(req.query.where);
      results = results.filter(r => {
        for (const [k, v] of Object.entries(w)) {
          const rv = r[k];
          if (typeof v === 'object' && v.$gt) { if (!(rv > v.$gt)) return false; }
          else if (typeof v === 'object' && v.$gte) { if (!(rv >= v.$gte)) return false; }
          else if (String(rv) !== String(v)) return false;
        }
        return true;
      });
    } catch {}
  }

  if (req.query.order) {
    const col = req.query.order.replace(/[^a-zA-Z0-9_]/g, '');
    results.sort((a, b) => String(a[col] || '').localeCompare(String(b[col] || '')));
  }

  const limit = parseInt(req.query.limit);
  if (limit > 0) results = results.slice(0, limit);

  res.json({ results });
});

// POST /api/classes/:table — auto-inject user_id
app.post('/api/classes/:table', auth, (req, res) => {
  const { rows, name } = getTable(req.params.table);
  const { objectId, createdAt, updatedAt, ...data } = req.body;
  const now = new Date().toISOString();
  const record = { objectId: genId(), ...data, user_id: req.user.userId, createdAt: createdAt || now, updatedAt: now };
  rows.push(record);
  DB.write(name, rows);
  res.status(201).json(record);
});

// GET /api/classes/:table/:id — ownership check
app.get('/api/classes/:table/:id', auth, (req, res) => {
  const { rows } = getTable(req.params.table);
  const r = rows.find(x => x.objectId === req.params.id);
  if (!r) return res.status(404).json({ error: '记录不存在' });
  if (r.user_id !== req.user.userId) return res.status(403).json({ error: '无权访问' });
  res.json(r);
});

// PUT /api/classes/:table/:id — ownership check
app.put('/api/classes/:table/:id', auth, (req, res) => {
  const { rows, name } = getTable(req.params.table);
  const idx = rows.findIndex(x => x.objectId === req.params.id);
  if (idx === -1) return res.status(404).json({ error: '记录不存在' });
  if (rows[idx].user_id !== req.user.userId) return res.status(403).json({ error: '无权修改' });
  const { objectId, createdAt, updatedAt, user_id, ...data } = req.body;
  rows[idx] = { ...rows[idx], ...data, updatedAt: new Date().toISOString() };
  DB.write(name, rows);
  res.json(rows[idx]);
});

// DELETE /api/classes/:table/:id — ownership check
app.delete('/api/classes/:table/:id', auth, (req, res) => {
  const { rows, name } = getTable(req.params.table);
  const idx = rows.findIndex(x => x.objectId === req.params.id);
  if (idx === -1) return res.status(404).json({ error: '记录不存在' });
  if (rows[idx].user_id !== req.user.userId) return res.status(403).json({ error: '无权删除' });
  rows.splice(idx, 1);
  DB.write(name, rows);
  res.json({ msg: 'ok' });
});

// ---- Text Chunking API ----
app.post('/api/chunk', auth, (req, res) => {
  const { text, chunkSize, overlap } = req.body;
  if (!text) return res.status(400).json({ error: 'text is required' });
  const chunks = chunkText(text, chunkSize || 500, overlap || 100);
  res.json({ chunks, count: chunks.length });
});

// ---- AI Cache API ----
app.get('/api/cache', auth, (req, res) => {
  const { text, bookTitle } = req.query;
  if (!text) return res.status(400).json({ error: 'text is required' });
  const key = cacheKey(text, bookTitle || '');
  const entry = aiCache.get(key);
  res.json({ hit: !!entry, result: entry?.result || null });
});

app.post('/api/cache', auth, (req, res) => {
  const { text, bookTitle, result } = req.body;
  if (!text || !result) return res.status(400).json({ error: 'text and result are required' });
  const key = cacheKey(text, bookTitle || '');
  aiCache.set(key, { result, time: Date.now() });
  res.json({ cached: true });
});

// ---- Error handler ----
app.use((err, req, res, _next) => {
  console.error(`[ERROR] ${err.message}`, err.stack);
  res.status(500).json({ error: NODE_ENV === 'production' ? '服务器错误' : err.message });
});

// ---- Start ----
if (NODE_ENV !== 'test') {
  app.listen(PORT, () => {
    console.log(`[${NODE_ENV}] Reader backend :${PORT}`);
    console.log(`Data: ${DATA_DIR}`);
  });
}

module.exports = app;
