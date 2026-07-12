const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;
const DEEPSEEK_MODEL = process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash';

const USER_AGENT = 'ZhiDuReader/1.0 (public reading library)';

async function buildBookIntroduction({ title, author, description, chapters }) {
  const cleanTitle = clean(title);
  const cleanAuthor = clean(author);
  const metadataDescription = cleanDescription(description);
  const chapterExcerpt = chapterExcerptForGuide(chapters);
  const known = knownBookIntroduction(cleanTitle, cleanAuthor);

  const authoritative = await findAuthoritativeDescription({
    title: cleanTitle,
    author: cleanAuthor,
  });

  const sourceText =
    metadataDescription ||
    authoritative.description ||
    known.description ||
    chapterExcerpt;
  const sourceName = metadataDescription
    ? 'metadata_description'
    : authoritative.source ||
      (known.description
        ? 'known_book_profile'
        : chapterExcerpt
          ? 'chapter_excerpt'
          : 'title_author');

  const guide = await generateGuide({
    title: cleanTitle,
    author: cleanAuthor,
    text: sourceText || [cleanTitle, cleanAuthor].filter(Boolean).join(' '),
    source: sourceName,
    known,
  });

  return {
    description: sourceText || known.description || '',
    authoritative_description: authoritative.description || '',
    authoritative_description_source: authoritative.source || '',
    authoritative_description_url: authoritative.url || '',
    one_line_summary: guide.one_line_summary,
    one_line_summary_source: guide.source,
    encounter_summary: guide.encounter_summary,
    expanded_guide: guide.expanded_guide,
    why_worth_reading: '',
    reading_themes: guide.reading_themes,
  };
}

async function findAuthoritativeDescription({ title, author }) {
  if (!title) return emptyAuthority();

  const openLibrary = await fromOpenLibrary(title, author);
  if (openLibrary.description) return openLibrary;

  const wikipediaZh = await fromWikipedia('zh', title, author);
  if (wikipediaZh.description) return wikipediaZh;

  const wikipediaEn = await fromWikipedia('en', title, author);
  if (wikipediaEn.description) return wikipediaEn;

  return emptyAuthority();
}

async function fromOpenLibrary(title, author) {
  try {
    const params = new URLSearchParams({
      title,
      limit: '3',
      fields: 'key,title,author_name,first_sentence',
    });
    if (author && author !== '佚名') params.set('author', author);
    const search = await fetchJson(`https://openlibrary.org/search.json?${params}`);
    const docs = Array.isArray(search?.docs) ? search.docs : [];
    const doc = docs.find((item) => item?.key) || docs[0];
    if (!doc?.key) return emptyAuthority();

    const work = await fetchJson(`https://openlibrary.org${doc.key}.json`);
    const description = cleanDescription(
      descriptionValue(work?.description) ||
        descriptionValue(work?.first_sentence) ||
        descriptionValue(doc.first_sentence),
    );
    if (!description) return emptyAuthority();
    return {
      description,
      source: 'open_library',
      url: `https://openlibrary.org${doc.key}`,
    };
  } catch (_) {
    return emptyAuthority();
  }
}

async function fromWikipedia(lang, title, author) {
  try {
    const searchTerm = [title, author && author !== '佚名' ? author : '']
      .filter(Boolean)
      .join(' ');
    const params = new URLSearchParams({
      action: 'query',
      list: 'search',
      srsearch: searchTerm,
      format: 'json',
      utf8: '1',
      srlimit: '1',
      origin: '*',
    });
    const search = await fetchJson(
      `https://${lang}.wikipedia.org/w/api.php?${params}`,
    );
    const pageTitle = search?.query?.search?.[0]?.title;
    if (!pageTitle) return emptyAuthority();

    const summary = await fetchJson(
      `https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(pageTitle)}`,
    );
    if (summary?.type === 'disambiguation') return emptyAuthority();
    const description = cleanDescription(summary?.extract);
    if (!description) return emptyAuthority();
    return {
      description,
      source: `wikipedia_${lang}`,
      url: summary?.content_urls?.desktop?.page ||
        `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(pageTitle)}`,
    };
  } catch (_) {
    return emptyAuthority();
  }
}

async function generateGuide({ title, author, text, source, known }) {
  const knownGuide = normalizeGuide(known, source || 'known_book_profile');
  if (knownGuide.one_line_summary && source === 'known_book_profile') {
    return knownGuide;
  }

  const cleaned = cleanDescription(text);
  if (DEEPSEEK_API_KEY && cleaned) {
    const aiGuide = await generateGuideWithAi({
      title,
      author,
      text: cleaned,
      source,
    });
    if (
      aiGuide.one_line_summary &&
      aiGuide.expanded_guide
    ) {
      return aiGuide;
    }
  }

  if (knownGuide.one_line_summary) return knownGuide;
  return heuristicGuide({ title, author, text: cleaned, source });
}

async function generateGuideWithAi({ title, author, text, source }) {
  try {
    const response = await fetchWithTimeout(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        thinking: { type: 'disabled' },
        temperature: 0.2,
        max_tokens: 520,
        messages: [
          {
            role: 'system',
            content:
              '你为安静阅读产品生成准确克制的书籍读前导览。必须基于给定资料，不虚构。像一位读过这本书的人轻轻介绍它。只输出 JSON。',
          },
          {
            role: 'user',
            content: [
              `书名：${title || '未知'}`,
              `作者：${author || '佚名'}`,
              `资料来源：${source || 'unknown'}`,
              `资料：${text.slice(0, 12000)}`,
              '请生成 JSON：',
              '{"one_line_summary":"60字以内，准确说明这本书讲什么","expanded_guide":"160到260字，可以包含内容简介、时代背景、阅读建议和核心问题；克制、具体、有阅读欲","reading_themes":["主题1","主题2","主题3","主题4","主题5","主题6"]}',
              '不要输出“为什么值得读”。不要写主题标签列表。不要写“暂无可靠简介”“等待补全”“围绕自身核心问题”“从正文和读者痕迹中进入”。',
            ].join('\n'),
          },
        ],
      }),
    }, 18000);

    if (!response.ok) return emptyGuide(source);
    const data = await response.json();
    const content = clean(data?.choices?.[0]?.message?.content || '');
    return normalizeGuide(parseJsonObject(content), `${source}_ai_generated`);
  } catch (_) {
    return emptyGuide(source);
  }
}

function heuristicGuide({ title, author, text, source }) {
  const sentences = firstSentences(text, 4);
  const oneLine =
    sentences[0] ||
    (title
      ? `《${title}》是一部需要从正文慢慢进入的作品。`
      : '这本书需要从正文慢慢进入。');
  const themes = inferThemes(`${title} ${author} ${text}`);
  return normalizeGuide(
    {
      one_line_summary: clampSentence(oneLine, 90),
      expanded_guide: expandedGuideFromSentences({
        title,
        sentences,
      }),
      reading_themes: themes,
    },
    source || 'chapter_excerpt_heuristic',
  );
}

function knownBookIntroduction(title, author) {
  const seed = `${title} ${author}`.toLowerCase();
  if (
    seed.includes('1984') ||
    seed.includes('nineteen eighty-four') ||
    seed.includes('一九八四')
  ) {
    return {
      one_line_summary:
        '《1984》是一部反乌托邦小说，讲述温斯顿在极权社会中试图守住记忆、真实与自由的故事。',
      expanded_guide:
        '这不是一部只关于监控的小说。奥威尔写的是一个连事实、语言和记忆都可能被改写的世界。读《1984》时，你会跟随温斯顿靠近恐惧、怀疑和反抗，也会看见一个人在被迫交出思想之前，如何试图守住真实。',
      reading_themes: ['权力', '监控', '真相', '语言', '自由', '记忆'],
      description:
        '《1984》是乔治·奥威尔的反乌托邦小说。故事发生在被“老大哥”和党全面监控的极权社会，主人公温斯顿试图在被改写的历史、语言和思想控制中守住个人记忆、真实与自由。',
    };
  }
  if (
    seed.includes('第二性') ||
    seed.includes('second sex') ||
    seed.includes('beauvoir') ||
    seed.includes('波伏瓦')
  ) {
    return {
      one_line_summary:
        '《第二性》分析女性如何在历史、社会与身体经验中被塑造成“第二性”。',
      expanded_guide:
        '波伏瓦并不只是讨论女性处境，她更在追问“女人”如何被历史、制度、身体经验和日常关系共同制造出来。进入《第二性》，你会不断看见个体如何被定义，又如何试图从这些定义里重新获得自由。',
      reading_themes: ['女性身份', '成为自己', '身体', '自由', '规训', '人与社会'],
      description:
        '《第二性》是西蒙娜·德·波伏瓦的重要著作，讨论女性处境、身体经验、历史结构与社会规训如何共同塑造“女人”这一身份。',
    };
  }
  if (
    seed.includes('纯粹理性批判') ||
    seed.includes('critique of pure reason') ||
    seed.includes('康德') ||
    seed.includes('kant')
  ) {
    return {
      one_line_summary:
        '《纯粹理性批判》追问人类认识如何可能，以及理性在经验之外能走多远。',
      expanded_guide:
        '康德在这本书里并不是简单给出一套知识理论，而是在重新划定理性能够合法行动的范围。读它时，你会进入经验如何成为可能、判断如何成立、形而上学为何总会越界这些问题。',
      reading_themes: ['理性', '经验', '认识边界', '主体', '判断', '形而上学'],
      description:
        '《纯粹理性批判》是康德的核心哲学著作，讨论先天知识、经验条件、认识能力与形而上学边界。',
    };
  }
  return emptyGuide('known_book_profile');
}

function normalizeGuide(value, source) {
  const oneLine = clean(value?.one_line_summary || value?.oneLine || '');
  const expanded = clean(
    value?.expanded_guide ||
      value?.expandedGuide ||
      value?.guide ||
      '',
  );
  const themes = normalizeThemes(value?.reading_themes || value?.themes);
  return {
    one_line_summary: rejectWeakText(oneLine) ? '' : clampSentence(oneLine, 110),
    encounter_summary: '',
    expanded_guide: rejectWeakText(expanded) ? '' : clampSentence(expanded, 360),
    reading_themes: themes,
    source: source || '',
    description: clean(value?.description || ''),
  };
}

function rejectWeakText(text) {
  return !text ||
    text.includes('暂无可靠简介') ||
    text.includes('等待补全') ||
    text.includes('围绕自身核心问题') ||
    text.includes('从正文和读者痕迹') ||
    text.includes('等待有人从第一页') ||
    text.includes('这本书刚来到明台');
}

function expandedGuideFromSentences({ title, sentences }) {
  const useful = sentences
    .map((item) => cleanDescription(item))
    .filter((item) => item.length > 8)
    .slice(0, 3);
  if (useful.length >= 2) {
    return clampSentence(useful.join(''), 300);
  }
  const intro = useful[0] || (title ? `《${title}》从正文展开它真正的问题。` : '');
  return clampSentence(intro, 260);
}

function parseJsonObject(content) {
  const raw = clean(content)
    .replace(/^```json/i, '')
    .replace(/^```/, '')
    .replace(/```$/, '')
    .trim();
  try {
    return JSON.parse(raw);
  } catch (_) {
    const match = raw.match(/\{[\s\S]*\}/);
    if (!match) return {};
    try {
      return JSON.parse(match[0]);
    } catch (_) {
      return {};
    }
  }
}

function chapterExcerptForGuide(chapters) {
  const list = Array.isArray(chapters) ? chapters : [];
  let combined = '';
  for (const chapter of list.slice(0, 5)) {
    const text = cleanDescription(
      chapter.plain_text || chapter.content_text || chapter.content || '',
    );
    if (!text) continue;
    combined = `${combined}\n\n${text}`.trim();
    if (combined.length >= 12000) break;
  }
  return combined.slice(0, 12000);
}

function firstSentences(text, limit = 3) {
  const value = cleanDescription(text);
  if (!value) return [];
  const matches = value.match(/[^。！？!?\.]+[。！？!?\.]?/g) || [value];
  return matches.map((item) => clean(item)).filter(Boolean).slice(0, limit);
}

function inferThemes(seedText) {
  const seed = clean(seedText).toLowerCase();
  const themes = [];
  const add = (theme) => {
    if (!themes.includes(theme)) themes.push(theme);
  };

  if (seed.includes('女性') || seed.includes('女人') || seed.includes('woman')) add('女性身份');
  if (seed.includes('自由') || seed.includes('freedom')) add('自由');
  if (seed.includes('权力') || seed.includes('power')) add('权力');
  if (seed.includes('语言') || seed.includes('language')) add('语言');
  if (seed.includes('记忆') || seed.includes('memory')) add('记忆');
  if (seed.includes('理性') || seed.includes('reason')) add('理性');
  if (seed.includes('经验') || seed.includes('experience')) add('经验');
  if (seed.includes('社会') || seed.includes('society')) add('人与社会');
  if (seed.includes('身体') || seed.includes('body')) add('身体');
  if (seed.includes('孤独') || seed.includes('loneliness')) add('孤独');
  if (seed.includes('历史') || seed.includes('history')) add('历史');
  if (seed.includes('真相') || seed.includes('truth')) add('真相');

  if (themes.length === 0) {
    add('人物处境');
    add('社会关系');
    add('自我理解');
  }
  return themes.slice(0, 6);
}

function normalizeThemes(value) {
  const raw = Array.isArray(value)
    ? value
    : typeof value === 'string'
      ? value.split(/[、,，/|]/)
      : [];
  return [...new Set(raw.map((item) => clean(item)).filter(Boolean))].slice(0, 6);
}

function emptyGuide(source) {
  return {
    one_line_summary: '',
    encounter_summary: '',
    expanded_guide: '',
    reading_themes: [],
    source: source || '',
    description: '',
  };
}

function clampSentence(text, maxLength) {
  const value = clean(text);
  if (value.length <= maxLength) return value;
  return `${value.slice(0, maxLength).trim()}...`;
}

function cleanDescription(value) {
  return clean(value)
    .replace(/\[[^\]]+\]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function descriptionValue(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'object' && value.value) return value.value;
  return '';
}

async function fetchJson(url) {
  const response = await fetchWithTimeout(url, {
    headers: {
      Accept: 'application/json',
      'User-Agent': USER_AGENT,
    },
  });
  if (!response.ok) return null;
  return response.json();
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 4500) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function clean(value) {
  return String(value || '').trim();
}

function emptyAuthority() {
  return { description: '', source: '', url: '' };
}

module.exports = {
  buildBookIntroduction,
};
