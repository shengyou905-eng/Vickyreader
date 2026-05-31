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
  return (await getUserInsight(userId)) || refreshUserInsight(userId);
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

function buildInsightCache(entries = [], authorizedFreeNotes = []) {
  const recentFocus = {
    7: buildWindowInsight(entries, 7),
    30: buildWindowInsight(entries, 30),
  };
  const longTermTopics = topKeys(countTags(entries), 6);
  const weeklySummary = buildWeeklySummary(recentFocus[7]);
  const highValueQuestions = buildHighValueQuestions(entries, recentFocus, longTermTopics);
  const deepReflection = buildDeepReflection({
    recentFocus,
    longTermTopics,
    authorizedFreeNotes,
  });
  return {
    recentFocus,
    weeklySummary,
    longTermTopics,
    highValueQuestions,
    recentEntries: entries.slice(0, 30),
    deepReflection,
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
    summary: buildFocusSummary(visible.length, topTags, topBooks),
  };
}

function buildFocusSummary(entryCount, topTags, topBooks) {
  if (entryCount === 0) {
    return '最近还没有新的阅读痕迹。继续读一点，小U会在这里安静地替你留意。';
  }
  if (topTags.length >= 2) {
    return `你最近反复停留在「${topTags[0]}」与「${topTags[1]}」附近。它们似乎正在慢慢靠近同一个问题。`;
  }
  if (topTags.length === 1) {
    return `你最近常常回到「${topTags[0]}」。有些问题还没有答案，但已经值得被看见。`;
  }
  if (topBooks.length > 0) {
    return `你最近在《${topBooks[0]}》里停留得更多。那些留下来的句子，正在逐渐显出方向。`;
  }
  return `最近留下了 ${entryCount} 条阅读痕迹。小U会慢慢替你聚拢它们。`;
}

function buildWeeklySummary(weekly) {
  if (weekly.entry_count === 0) {
    return '这一周还很安静。没有关系，阅读不是一场需要赶进度的事。';
  }
  if (weekly.top_tags.length > 0) {
    return `这一周，你留下了 ${weekly.entry_count} 条阅读痕迹。比起追逐结论，你更像是在「${weekly.top_tags.slice(0, 2).join('」与「')}」附近反复停留。`;
  }
  if (weekly.top_books.length > 0) {
    return `这一周，你留下了 ${weekly.entry_count} 条阅读痕迹。许多停留发生在《${weekly.top_books[0]}》里。`;
  }
  return `这一周，你留下了 ${weekly.entry_count} 条阅读痕迹。它们还很零散，但已经开始形成自己的纹理。`;
}

function buildHighValueQuestions(entries, recentFocus, longTermTopics) {
  const questions = [
    {
      id: 'recent_focus',
      title: '我最近在反复停留什么？',
      answer: recentFocus[7].summary,
    },
  ];
  const topic = recentFocus[30].top_tags[0] || longTermTopics[0];
  if (topic) {
    questions.push({
      id: 'recurring_topic',
      title: `我在哪些书里反复提到「${topic}」？`,
      answer: buildTopicAnswer(entries, topic),
    });
  } else {
    questions.push({
      id: 'recurring_book',
      title: '最近哪本书让我停留得更久？',
      answer: buildBookAnswer(recentFocus[30]),
    });
  }
  questions.push(
    {
      id: 'weekly_summary',
      title: '这一周，我留下了什么？',
      answer: buildWeeklySummary(recentFocus[7]),
    },
    {
      id: 'top_highlight_themes',
      title: '我最常划线的主题是什么？',
      answer: buildHighlightThemeAnswer(entries),
    },
    {
      id: 'touching_recently',
      title: '最近哪些内容让我停了下来？',
      answer: buildTouchingAnswer(entries),
    },
  );
  return questions;
}

function buildTopicAnswer(entries, topic) {
  const related = entries.filter((entry) => tagsOf(entry).includes(topic));
  const books = topKeys(countBy(related, (entry) => clean(entry.book_title)), 3);
  if (books.length === 0) {
    return `「${topic}」已经出现过几次，但它还没有稳定地落在某一本书里。再读一阵，也许会慢慢看见它的来源。`;
  }
  return `你在 ${books.map((book) => `《${book}》`).join('、')} 里都停留在「${topic}」附近。它不是一次偶然的划线，更像是一个反复回来的问题。`;
}

function buildBookAnswer(insight) {
  if (insight.top_books.length === 0) {
    return '最近的痕迹还比较零散。再留下一些划线和想法，小U会替你看见反复回来的地方。';
  }
  return `最近你在《${insight.top_books[0]}》里停留得更久。与其说是读得更多，不如说是有些句子更容易让你慢下来。`;
}

function buildHighlightThemeAnswer(entries) {
  const highlightEntries = entries.filter((entry) => entry.source === 'highlight');
  const themes = topKeys(countTags(highlightEntries), 4);
  if (themes.length === 0) {
    return '目前的划线还没有形成稳定主题。先不用急着归纳，继续留下真正让你停住的句子。';
  }
  return `你的划线常常落在「${themes.join('」「')}」附近。它们也许不是分开的兴趣，而是同一个问题的不同侧面。`;
}

function buildTouchingAnswer(entries) {
  const recent = entries.find((entry) => {
    return clean(entry.user_input) || clean(entry.original_text) || clean(entry.ai_explanation);
  });
  if (!recent) {
    return '最近还没有足够清晰的阅读停留。等你留下几处真正想回看的句子，小U会在这里替你收好。';
  }
  const text = clean(recent.user_input) || clean(recent.original_text) || clean(recent.ai_explanation);
  const excerpt = text.length > 90 ? `${text.slice(0, 90)}……` : text;
  const book = clean(recent.book_title);
  return `${book ? `在《${book}》里，` : ''}你最近曾在这句话附近停下来：\n\n“${excerpt}”`;
}

function buildDeepReflection({ recentFocus, longTermTopics, authorizedFreeNotes }) {
  const topics = longTermTopics.slice(0, 3);
  if (topics.length === 0) {
    return '现在还不必急着给自己的阅读命名。\n\n继续留下真正让你停住的地方。时间久一点，问题会自己浮出来。';
  }
  const noteSentence = authorizedFreeNotes.length > 0
    ? `\n\n你还主动交来了 ${authorizedFreeNotes.length} 条私人片段${buildPrivateHint(authorizedFreeNotes)}。它们会被谨慎地放在阅读痕迹旁边，而不是混成同一种记录。`
    : '';
  const recent = recentFocus[30].top_tags.slice(0, 2).join('」与「');
  return `你似乎并不只是在关注「${recent || topics[0]}」。\n\n你反复回到的，也许是「${topics.join('、')}」之间那条还没有完全说清的线。${noteSentence}`;
}

function buildPrivateHint(notes) {
  const hints = notes
    .map((note) => clean(note.title) || clean(note.content).slice(0, 12))
    .filter(Boolean)
    .slice(0, 2);
  return hints.length > 0 ? `，其中有「${hints.join('」「')}」` : '';
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

module.exports = {
  getUserInsight,
  getOrCreateUserInsight,
  refreshUserInsight,
  isStale,
};
