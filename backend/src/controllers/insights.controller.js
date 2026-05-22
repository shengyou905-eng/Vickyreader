const entryRepository = require('../repositories/entry.repository');
const httpError = require('../utils/httpError');

const questions = {
  recent_focus: '我最近在关注什么？',
  freedom_books: '我在哪些书里反复提到“自由”？',
  weekly_summary: '本周阅读摘要',
  top_highlight_themes: '我最常划线的主题',
  touching_recently: '最近哪些内容最触动我？',
};

const actionTags = new Set([
  '划线',
  '想法',
  'AI解释',
  'AI 解释',
  '手动',
  'highlight',
  'thought',
  'ai_explanation',
  'manual',
]);

async function answerQuestion(req, res, next) {
  try {
    const questionId = req.params.questionId;
    const question = questions[questionId];
    if (!question) {
      throw httpError(400, 'Unknown insight question');
    }

    const entries = await entryRepository.listEntries(req.user.id, { limit: 500 });
    const answer = buildAnswer(questionId, entries);

    return res.json({
      question_id: questionId,
      question,
      answer,
      generated_at: new Date().toISOString(),
    });
  } catch (error) {
    return next(error);
  }
}

function buildAnswer(questionId, entries) {
  if (questionId === 'recent_focus') return answerRecentFocus(entries);
  if (questionId === 'freedom_books') return answerFreedomBooks(entries);
  if (questionId === 'weekly_summary') return answerWeeklySummary(entries);
  if (questionId === 'top_highlight_themes') return answerTopHighlightThemes(entries);
  if (questionId === 'touching_recently') return answerTouchingRecently(entries);
  return '这个问题还没有准备好。';
}

function answerRecentFocus(entries) {
  const recent = entries.filter((entry) => isWithinDays(entry, 30));
  if (recent.length === 0) {
    return '最近还没有新的阅读痕迹。继续留下一点划线、想法或 AI 解释，小U会在这里帮你看见反复出现的问题。';
  }

  const topTags = topKeys(countTags(recent), 3);
  if (topTags.length > 0) {
    return `过去30天，你留下了 ${recent.length} 条记录。\n\n反复出现的主题是：${joinList(topTags)}。\n\n这些不像普通收藏，更像你最近一直在心里来回触碰的问题。`;
  }

  const topBooks = topKeys(countBooks(recent), 3);
  if (topBooks.length > 0) {
    return `过去30天，你留下了 ${recent.length} 条记录。\n\n你最常回到：${joinBookList(topBooks)}。\n\n这些书里的片段，正在慢慢形成你的近期思想底色。`;
  }

  return `过去30天，你留下了 ${recent.length} 条记录。现在主题还比较松散，但它们已经开始成为一份可以回看的思想底稿。`;
}

function answerFreedomBooks(entries) {
  const matched = entries.filter((entry) => entryMentions(entry, '自由'));
  if (matched.length === 0) {
    return '我还没有在你的记录里找到明确提到“自由”的条目。\n\n之后你在不同书里标记到这个词，小U会把它们收束到一起。';
  }

  const books = topEntries(countBooks(matched), 5);
  const bookLine = books.length > 0
    ? books.map(([book, count]) => `《${book}》${count}条`).join('、')
    : '未命名书籍';

  return `你一共在 ${matched.length} 条记录里提到“自由”。\n\n它们主要分布在：${bookLine}。\n\n这说明“自由”不是一个孤立词，而是你在不同文本里反复辨认的问题。`;
}

function answerWeeklySummary(entries) {
  const weekly = entries.filter((entry) => isWithinDays(entry, 7));
  if (weekly.length === 0) {
    return '这一周还没有新的阅读记录。\n\n等你留下几条划线或想法，小U会帮你把这一周读过、想过的东西轻轻拢起来。';
  }

  const tags = topKeys(countTags(weekly), 3);
  const books = topKeys(countBooks(weekly), 2);
  const source = topKeys(countSources(weekly), 1)[0];
  const lines = [`这一周你留下了 ${weekly.length} 条阅读痕迹。`];

  if (tags.length > 0) lines.push(`你反复碰到的主题是：${joinList(tags)}。`);
  if (books.length > 0) lines.push(`你主要回到：${joinBookList(books)}。`);
  if (source) lines.push(`最常见的记录方式是：${sourceLabel(source)}。`);

  lines.push('它们合在一起，不像任务清单，更像这一周思想经过的路线。');
  return lines.join('\n\n');
}

function answerTopHighlightThemes(entries) {
  const highlights = entries.filter((entry) => entry.source === 'highlight');
  if (highlights.length === 0) {
    return '目前还没有划线记录。\n\n等你开始划线，小U会从这些被你停下来的句子里，帮你看见最常回到的主题。';
  }

  const tags = topKeys(countTags(highlights), 5);
  if (tags.length > 0) {
    return `你目前一共留下了 ${highlights.length} 条划线。\n\n最常出现的主题是：${joinList(tags)}。\n\n这些是阅读时最容易让你停下来的地方。`;
  }

  const books = topKeys(countBooks(highlights), 3);
  if (books.length > 0) {
    return `你目前一共留下了 ${highlights.length} 条划线。\n\n它们主要集中在：${joinBookList(books)}。\n\n主题标签还不明显，但这些书已经显出你的注意力方向。`;
  }

  return `你目前一共留下了 ${highlights.length} 条划线。主题还没有聚拢，但这些停顿本身已经值得回看。`;
}

function answerTouchingRecently(entries) {
  const recent = entries
    .filter((entry) => isWithinDays(entry, 30))
    .filter((entry) => textOf(entry.user_input).length > 0 || entry.source === 'thought');
  const candidates = recent.length > 0 ? recent : entries.filter((entry) => isWithinDays(entry, 30));

  if (candidates.length === 0) {
    return '最近还没有足够的条目判断哪些内容最触动你。\n\n当你写下想法，小U会优先把这些带有情绪和判断的片段整理出来。';
  }

  const samples = candidates
    .slice()
    .sort((a, b) => scoreTouching(b) - scoreTouching(a))
    .slice(0, 3)
    .map((entry) => `- ${excerpt(entry.user_input || entry.original_text || entry.ai_explanation, 48)}`);

  return `最近比较触动你的，可能是这些片段：\n\n${samples.join('\n')}\n\n它们之所以被留下，大概不是因为“有用”，而是因为它们碰到了你正在想的事。`;
}

function countTags(entries) {
  const counts = new Map();
  for (const entry of entries) {
    for (const tag of tagsOf(entry)) {
      if (actionTags.has(tag)) continue;
      counts.set(tag, (counts.get(tag) || 0) + 1);
    }
  }
  return counts;
}

function countBooks(entries) {
  const counts = new Map();
  for (const entry of entries) {
    const title = textOf(entry.book_title) || '未命名书籍';
    counts.set(title, (counts.get(title) || 0) + 1);
  }
  return counts;
}

function countSources(entries) {
  const counts = new Map();
  for (const entry of entries) {
    const source = textOf(entry.source) || 'manual';
    counts.set(source, (counts.get(source) || 0) + 1);
  }
  return counts;
}

function topKeys(counts, limit) {
  return topEntries(counts, limit).map(([key]) => key);
}

function topEntries(counts, limit) {
  return [...counts.entries()]
    .sort((a, b) => {
      if (b[1] !== a[1]) return b[1] - a[1];
      return a[0].localeCompare(b[0], 'zh-Hans-CN');
    })
    .slice(0, limit);
}

function tagsOf(entry) {
  if (Array.isArray(entry.auto_tags)) {
    return entry.auto_tags.map((tag) => String(tag).trim()).filter(Boolean);
  }
  if (typeof entry.auto_tags === 'string' && entry.auto_tags.trim()) {
    return entry.auto_tags.split(',').map((tag) => tag.trim()).filter(Boolean);
  }
  return [];
}

function isWithinDays(entry, days) {
  const createdAt = new Date(entry.created_at);
  if (Number.isNaN(createdAt.getTime())) return false;
  return createdAt >= new Date(Date.now() - days * 24 * 60 * 60 * 1000);
}

function entryMentions(entry, keyword) {
  return [
    entry.original_text,
    entry.user_input,
    entry.ai_explanation,
    entry.auto_summary,
    tagsOf(entry).join(' '),
  ].some((value) => textOf(value).includes(keyword));
}

function scoreTouching(entry) {
  const noteLength = textOf(entry.user_input).length;
  const originalLength = textOf(entry.original_text).length;
  const sourceBoost = entry.source === 'thought' ? 40 : 0;
  return noteLength * 2 + Math.min(originalLength, 120) + sourceBoost;
}

function sourceLabel(source) {
  return {
    highlight: '划线',
    thought: '想法',
    ai_explanation: 'AI解释',
    manual: '手动记录',
  }[source] || source;
}

function joinList(items) {
  return items.map((item) => `“${item}”`).join('、');
}

function joinBookList(items) {
  return items.map((item) => `《${item}》`).join('、');
}

function excerpt(value, length) {
  const text = textOf(value).replace(/\s+/g, ' ');
  if (!text) return '（没有文字摘录）';
  return text.length > length ? `${text.slice(0, length)}…` : text;
}

function textOf(value) {
  return value == null ? '' : String(value).trim();
}

module.exports = {
  answerQuestion,
};
