const { query } = require('../config/db');
const entryRepository = require('./entry.repository');
const freeNoteRepository = require('./freeNote.repository');

const actionTags = new Set([
  '划线',
  '想法',
  '小U解释',
  '手动',
  'highlight',
  'thought',
  'ai_explanation',
  'manual',
]);

async function getUserInsight(userId) {
  const result = await query(
    `SELECT *
     FROM user_insights
     WHERE user_id = $1`,
    [userId],
  );
  return result.rows[0] || null;
}

async function getOrCreateUserInsight(userId) {
  const insight = await getUserInsight(userId);
  if (!insight || isLegacyInsight(insight) || isStale(insight)) {
    return refreshUserInsight(userId);
  }
  return insight;
}

async function refreshUserInsight(userId) {
  const [entries, authorizedFreeNotes] = await Promise.all([
    entryRepository.listEntries(userId, { limit: 500 }),
    freeNoteRepository.listAuthorizedForXiaou(userId, { limit: 100 }),
  ]);
  const cache = buildInsightCache(entries, authorizedFreeNotes);
  const result = await query(
    `INSERT INTO user_insights (
       user_id,
       recent_focus,
       weekly_summary,
       long_term_topics,
       high_value_questions,
       recent_entries,
       deep_reflection,
       source_entry_count,
       authorized_note_count,
       refreshed_at,
       updated_at
     )
     VALUES ($1, $2::jsonb, $3, $4::jsonb, $5::jsonb, $6::jsonb, $7, $8, $9, now(), now())
     ON CONFLICT (user_id) DO UPDATE SET
       recent_focus = EXCLUDED.recent_focus,
       weekly_summary = EXCLUDED.weekly_summary,
       long_term_topics = EXCLUDED.long_term_topics,
       high_value_questions = EXCLUDED.high_value_questions,
       recent_entries = EXCLUDED.recent_entries,
       deep_reflection = EXCLUDED.deep_reflection,
       source_entry_count = EXCLUDED.source_entry_count,
       authorized_note_count = EXCLUDED.authorized_note_count,
       refreshed_at = now(),
       updated_at = now()
     RETURNING *`,
    [
      userId,
      JSON.stringify(cache.recentFocus),
      cache.weeklySummary,
      JSON.stringify(cache.longTermTopics),
      JSON.stringify(cache.highValueQuestions),
      JSON.stringify(cache.recentEntries),
      cache.deepReflection,
      entries.length,
      authorizedFreeNotes.length,
    ],
  );
  return result.rows[0];
}

function isStale(insight, maxAgeMs = 15 * 60 * 1000) {
  const refreshedAt = new Date(insight?.refreshed_at || 0).getTime();
  return !Number.isFinite(refreshedAt) || Date.now() - refreshedAt > maxAgeMs;
}

function isLegacyInsight(insight) {
  const questions = Array.isArray(insight?.high_value_questions)
    ? insight.high_value_questions
    : [];
  const hasLegacyQuestion = questions.some((question) => {
    const id = clean(question?.id);
    const title = clean(question?.title);
    return id === 'top_highlight_themes' ||
      title.includes('最常划线') ||
      title.includes('我最近在反复停留什么') ||
      title.includes('我在哪些书里反复提到') ||
      title.includes('这一周，我留下了什么');
  });
  if (hasLegacyQuestion) return true;

  const focus = insight?.recent_focus || {};
  const summaries = [
    focus?.['7']?.summary,
    focus?.['30']?.summary,
    insight?.weekly_summary,
    insight?.deep_reflection,
  ]
    .map(clean)
    .filter(Boolean);
  return summaries.some((summary) => (
    summary.includes('频繁记录') ||
    summary.includes('主要在回顾') ||
    (summary.includes('留下了') && summary.includes('条阅读痕迹')) ||
    summary.includes('最近还没有新的阅读痕迹') ||
    summary.includes('今天没有新的发现') ||
    summary.includes('这一周很安静') ||
    summary.includes('我看见你最近常常停在') ||
    summary.includes('我看见「') ||
    summary.includes('小U会先替你记住') ||
    summary.includes('这些内容之间有什么联系') ||
    summary.includes('它们可能在靠近什么问题') ||
    summary.includes('不急着给答案')
  ));
}

function buildInsightCache(entries = [], authorizedFreeNotes = []) {
  const recentFocus = {
    7: buildWindowInsight(entries, 7),
    30: buildWindowInsight(entries, 30),
  };
  const longTermTopics = topKeys(countTags(entries), 6);
  const activeDiscovery = buildActiveDiscovery(entries, authorizedFreeNotes);
  const highValueQuestions = [];
  return {
    recentFocus,
    weeklySummary: activeDiscovery,
    longTermTopics,
    highValueQuestions,
    recentEntries: entries.slice(0, 30),
    deepReflection: activeDiscovery,
  };
}

function buildWindowInsight(entries, days) {
  const since = Date.now() - days * 24 * 60 * 60 * 1000;
  const visible = entries.filter((entry) => {
    const createdAt = new Date(entry.created_at || 0).getTime();
    return Number.isFinite(createdAt) && createdAt >= since;
  });
  const topTags = topKeys(countTags(visible), 3);
  const topBooks = topKeys(countBy(visible, (entry) => clean(entry.book_title)), 2);
  const topSources = topKeys(countBy(visible, (entry) => clean(entry.source)), 1);
  return {
    days,
    entry_count: visible.length,
    top_tags: topTags,
    top_books: topBooks,
    top_source: topSources[0] || '',
    summary: '',
  };
}

function buildActiveDiscovery(entries = [], authorizedFreeNotes = []) {
  const normalized = entries
    .map((entry) => ({
      ...entry,
      createdAtMs: new Date(entry.created_at || 0).getTime(),
      bookTitle: clean(entry.book_title),
      originalText: normalizeText(entry.original_text),
      userInput: normalizeText(entry.user_input),
      tags: tagsOf(entry).filter((tag) => !actionTags.has(tag)),
    }))
    .filter((entry) => Number.isFinite(entry.createdAtMs))
    .sort((a, b) => b.createdAtMs - a.createdAtMs);

  if (normalized.length < 3) return '';

  const now = Date.now();
  const recentWindowMs = 14 * 24 * 60 * 60 * 1000;
  const freshWindowMs = 72 * 60 * 60 * 1000;
  const recent = normalized.filter((entry) => now - entry.createdAtMs <= recentWindowMs);
  if (recent.length < 2) return '';

  const repeatedText = findRepeatedText(recent, freshWindowMs, now);
  if (repeatedText) return repeatedText;

  const crossBookTheme = findCrossBookTheme(normalized, recent, freshWindowMs, now);
  if (crossBookTheme) return crossBookTheme;

  const shift = findInterestShift(normalized, recent, freshWindowMs, now);
  if (shift) return shift;

  if (authorizedFreeNotes.length > 0) {
    const freshAuthorized = authorizedFreeNotes.some((note) => {
      const grantedAt = new Date(note.granted_at || note.updated_at || note.created_at || 0).getTime();
      return Number.isFinite(grantedAt) && now - grantedAt <= freshWindowMs;
    });
    if (freshAuthorized && recent.length >= 2) {
      return '✦ 小U发现了一件事\n\n你最近把私人片段交给小U，同时阅读里也留下了新的停留。\n\n我还不能确定它们之间有没有真正的关系，所以先不替你下结论。之后如果它们继续靠近，我会再告诉你。';
    }
  }

  return '';
}

function findRepeatedText(recent, freshWindowMs, now) {
  const buckets = new Map();
  for (const entry of recent) {
    if (entry.originalText.length < 20) continue;
    const key = entry.originalText.slice(0, 90);
    const bucket = buckets.get(key) || [];
    bucket.push(entry);
    buckets.set(key, bucket);
  }
  for (const bucket of buckets.values()) {
    if (bucket.length < 2) continue;
    const latest = Math.max(...bucket.map((entry) => entry.createdAtMs));
    if (now - latest > freshWindowMs) continue;
    const books = unique(bucket.map((entry) => entry.bookTitle).filter(Boolean));
    const excerpt = clip(bucket[0].originalText, 54);
    const place = books.length > 0 ? `在《${books[0]}》里，` : '';
    return `✦ 小U发现了一件事\n\n${place}有一句话被你不止一次留下来：\n\n“${excerpt}”\n\n我还不知道它为什么让你停住，但它已经不像普通摘录。你可以问我：这句话和我之前的想法有什么关系？`;
  }
  return '';
}

function findCrossBookTheme(allEntries, recent, freshWindowMs, now) {
  const buckets = new Map();
  for (const entry of recent) {
    for (const tag of entry.tags) {
      const bucket = buckets.get(tag) || [];
      bucket.push(entry);
      buckets.set(tag, bucket);
    }
  }
  for (const [tag, bucket] of buckets.entries()) {
    if (bucket.length < 3) continue;
    const latest = Math.max(...bucket.map((entry) => entry.createdAtMs));
    if (now - latest > freshWindowMs) continue;
    const books = unique(bucket.map((entry) => entry.bookTitle).filter(Boolean));
    if (books.length < 2) continue;
    const olderCount = allEntries.filter((entry) => {
      return now - entry.createdAtMs > 14 * 24 * 60 * 60 * 1000 &&
        entry.tags.includes(tag);
    }).length;
    const lead = olderCount > 0
      ? `「${tag}」又回来了。`
      : `「${tag}」第一次在不同书里连了起来。`;
    return `✦ 小U发现了一件事\n\n${lead}\n\n它最近同时出现在 ${books.slice(0, 3).map((book) => `《${book}》`).join('、')} 里。\n\n我不确定它是不是一个稳定的问题，但它已经不只是某一本书里的词了。`;
  }
  return '';
}

function findInterestShift(allEntries, recent, freshWindowMs, now) {
  const latest = recent[0]?.createdAtMs || 0;
  if (now - latest > freshWindowMs) return '';
  const recentTags = topKeys(countTags(recent), 2);
  if (!recentTags.length) return '';
  const older = allEntries.filter((entry) => {
    const age = now - entry.createdAtMs;
    return age > 14 * 24 * 60 * 60 * 1000 && age <= 90 * 24 * 60 * 60 * 1000;
  });
  const olderTags = topKeys(countTags(older), 2);
  if (!olderTags.length) return '';
  const [recentTop] = recentTags;
  if (olderTags.includes(recentTop)) return '';
  const recentCount = recent.filter((entry) => entry.tags.includes(recentTop)).length;
  if (recentCount < 3) return '';
  return `✦ 小U发现了一件事\n\n最近的新停留开始偏向「${recentTop}」，而之前更常出现的是「${olderTags[0]}」。\n\n这不一定是转向，也可能只是一次短暂靠近。我会继续观察它会不会持续。`;
}

function countTags(entries) {
  const counts = {};
  for (const entry of entries) {
    for (const tag of tagsOf(entry)) {
      if (actionTags.has(tag)) continue;
      counts[tag] = (counts[tag] || 0) + 1;
    }
  }
  return counts;
}

function tagsOf(entry) {
  if (Array.isArray(entry.tags)) {
    return entry.tags.map(clean).filter(Boolean);
  }
  if (Array.isArray(entry.auto_tags)) {
    return entry.auto_tags.map(clean).filter(Boolean);
  }
  return clean(entry.auto_tags).split(',').map(clean).filter(Boolean);
}

function countBy(items, selector) {
  const counts = {};
  for (const item of items) {
    const key = selector(item);
    if (!key) continue;
    counts[key] = (counts[key] || 0) + 1;
  }
  return counts;
}

function topKeys(counts, limit) {
  return Object.entries(counts)
    .sort(([aKey, aCount], [bKey, bCount]) => bCount - aCount || aKey.localeCompare(bKey))
    .slice(0, limit)
    .map(([key]) => key);
}

function clean(value) {
  return String(value || '').trim();
}

function normalizeText(value) {
  return clean(value).replace(/\s+/g, ' ');
}

function unique(items) {
  return [...new Set(items)];
}

function clip(value, maxLength) {
  if (!value) return '';
  return value.length > maxLength ? `${value.slice(0, maxLength)}……` : value;
}

module.exports = {
  getUserInsight,
  getOrCreateUserInsight,
  refreshUserInsight,
  isStale,
};
