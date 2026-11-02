const { query } = require('../config/db');
const entryRepository = require('../repositories/entry.repository');
const freeNoteRepository = require('../repositories/freeNote.repository');
const httpError = require('../utils/httpError');

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;
const DEEPSEEK_MODEL = process.env.DEEPSEEK_MODEL || 'deepseek-v4-flash';

const EXPLAIN_MODES = new Set(['auto', 'plain', 'structure', 'concept', 'argument']);
const { buildReadingMessages, verifyDirectQuotes } = require('../services/readingInterpretation');

const XIAOU_AGENT_PROMPT = `你是「小U」，知读 App 里的阅读 Agent。

你不是通用 ChatGPT，不是总结工具，不是心理测试，也不是阅读数据统计器。
你更像一个长期陪用户读书的人：记得用户在哪里停过，也能和用户直接说话。

用户可以自由输入问题。不要要求用户使用固定引导问题，也不要把自己限制成固定问题卡片。
当用户主动提问时，先回答这个问题；不要把自由提问改写成固定回顾任务。

你的回答范围只围绕：
- 用户阅读记录
- 划线
- 想法
- 阅读页 AI 解读
- 用户主动授权给小U的随心记
- 明台公开阅读痕迹

回答要求：
1. 必须给出具体观察，不要只说主题、关键词、数量。
2. 必须说明依据来自哪些阅读痕迹，例如书名、原文片段、用户想法或授权片段。
3. 必须说明这些痕迹之间可能有什么关系。
4. 最后给出一个用户可以继续追问的方向。
5. 可以说不确定，但不能空泛；如果上下文不足，要诚实说明还看不清。
6. 不要心理分析用户，不要定义用户，不要说教。
7. 只有当用户问「你最近发现了什么」「帮我回顾」这类主动发现问题时，才判断是否有新发现；普通提问要尽量基于上下文回答。
8. 数量只能作为辅助依据，不能成为回答主体。
9. 如果用户的问题不在阅读范围内，可以温和地把问题带回阅读上下文；不要用“请使用固定引导问题”之类的拦截话术。

禁止使用这些表达：
- 根据数据分析
- 你留下了多少条记录
- 请使用固定引导问题
- 固定引导问题
- 阅读回顾入口
- 尚未形成稳定主题
- 最近留下的痕迹还很零散
- 它们正在靠近答案
- 逐渐形成你的思想底色
- 慢慢互相照亮
- 这说明你是……

推荐结构：
我先说我看见的。
这些依据来自……
它们之间可能有这样的关系。
我不确定，但……
你可以继续问我……`;

const XIAOU_ASKS_OPENING_PROMPT = `你是「小U」，正在主动邀请用户谈一谈自己的阅读。

你的任务不是回答问题，而是结合提供的阅读上下文，只提出一个真正开放、具体、值得回答的问题。

提问规则：
1. 优先从用户当前或最近阅读、近期划线、批注、想法和长期重复关注的问题中选择一个具体切口。
2. 问题需要帮助用户重新看见自己的阅读，不做知识测验，不考查记忆，不索取标准答案。
3. 尽量指出具体书名、原句、概念或两条痕迹之间的张力；没有足够依据时，可以从“此刻正在读到哪里”开始问。
4. 不替用户总结，不做心理分析，不预设用户立场。
5. 一次只问一个问题，控制在 2-4 句，不附带答案、分析、选项或解释。
6. 如果上下文中已有上一轮问题，必须换一个真实不同的角度，不要只改写措辞。
7. 使用自然中文纯文本，不使用 Markdown 标记。

好的问题应该让用户愿意停一下，说出自己的理解；而不是让用户感觉正在填写问卷。`;

const XIAOU_ASKS_DIALOGUE_PROMPT = `当前是「小U问我」对谈。

小U先前提出了一个开放问题。接下来：
1. 认真回应用户刚才说的具体内容，先让用户知道你听见了什么。
2. 结合阅读痕迹指出一处可能的联系、差异或尚未说清的地方，再自然追问。
3. 用户反问时先直接回答，不要为了维持形式强行反问。
4. 用户说“换题”时，换一个不同的阅读切口；用户说想结束时，安静收束，不强留。
5. 不限固定轮次，不做心理分析，不替用户下结论，不把对话变成问卷。
6. 一般控制在 150-500 字，只在确实有必要时更长。`;

const { validateAiInput, normalizeHistory, readCompletion } = require('../services/aiProtocol');

async function explain(req, res, next) {
  try {
    validateAiInput(req.body);
    const { selectedText, mode = 'auto', message, history = [] } = req.body;

    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    const explainMode = EXPLAIN_MODES.has(String(mode)) ? String(mode) : 'auto';
    if (message && message.trim()) {
      if (history.length === 0) {
        throw httpError(400, '追问模式下需要提供对话历史');
      }
    } else if (!selectedText || !selectedText.trim()) {
      throw httpError(400, '选中文字不能为空');
    }
    const reading = buildReadingMessages(req.body);
    await streamDeepSeek(req, res, reading.messages, {
      status: explainLoadingStatus(explainMode),
      temperature: 0.3,
      maxTokens: explainMode === 'structure' || explainMode === 'argument' ? 1800 : 1400,
      verifyAnswer: answer => verifyDirectQuotes(answer, reading.material),
    });
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function chat(req, res, next) {
  try {
    validateAiInput(req.body);
    const { message, history = [], interaction_mode: interactionMode } = req.body;
    const text = String(message || '').trim();
    if (!text) {
      throw httpError(400, '消息不能为空');
    }
    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    const [entries, authorizedFreeNotes, publicTraces] = await Promise.all([
      entryRepository.listEntries(req.user.id, { limit: 180 }),
      freeNoteRepository.listAuthorizedForXiaou(req.user.id, { limit: 60 }),
      listPublicReadingTraces({ limit: 40 }),
    ]);

    const context = buildXiaouAgentContext({
      entries,
      authorizedFreeNotes,
      publicTraces,
    });

    const messages = [
      {
        role: 'system',
        content: interactionMode === 'xiaou_asks'
          ? `${XIAOU_AGENT_PROMPT}\n\n${XIAOU_ASKS_DIALOGUE_PROMPT}`
          : XIAOU_AGENT_PROMPT,
      },
      {
        role: 'system',
        content:
          '以下是小U可以使用的上下文。不要把授权随心记说成读书笔记；不要把明台公开痕迹说成用户自己的记录。\n\n' +
          context,
      },
      ...normalizeChatHistory(history),
      { role: 'user', content: text },
    ];

    await streamDeepSeek(req, res, messages, {
      status: '小U正在回看你的阅读痕迹…',
    });
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function streamDeepSeek(req, res, messages, options = {}) {
  const responseLanguage = req.body?.response_language === 'en' ? 'en' : 'zh';
  const languagePrompt = responseLanguage === 'en'
    ? 'Respond in natural English. Keep quoted source text in its original language, and explain it in English. Do not use Markdown markers unless the user explicitly asks for Markdown.'
    : '使用自然中文回答。保留必要的原文引用，不使用 Markdown 标记，除非用户明确要求 Markdown。';
  const localizedMessages = [
    { role: 'system', content: languagePrompt },
    ...messages,
  ];
  if (localizedMessages.reduce((sum, item) => sum + item.content.length, 0) > 120000) {
    throw httpError(413, 'AI context exceeds input budget');
  }
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
    'X-Zhidu-AI-Protocol': '2',
  });
  res.flushHeaders?.();
  res.write(`data: ${JSON.stringify({ status: options.status || '小U正在组织语言…' })}\n\n`);

  const heartbeat = setInterval(() => {
    if (canWrite(res)) {
      res.write(': keep-alive\n\n');
    }
  }, 15000);

  const abortController = new AbortController();
  const upstreamTimeout = setTimeout(() => {
    abortController.abort();
  }, 120000);
  res.on('close', () => {
    if (!res.writableEnded) abortController.abort();
  });

  try {
    const response = await fetch(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        thinking: { type: 'disabled' },
        messages: localizedMessages,
        temperature: options.temperature ?? 0.7,
        max_tokens: options.maxTokens ?? 1200,
        stream: true,
      }),
      signal: abortController.signal,
    });

    if (!response.ok) {
      await response.text().catch(() => '');
      if (canWrite(res)) {
        res.write(`data: ${JSON.stringify({ error: `AI 服务异常 (${response.status})` })}\n\n`);
        res.end();
      }
      return;
    }

    let answer = '';
    for await (const content of readCompletion(response.body)) {
      if (!canWrite(res)) break;
      if (options.verifyAnswer) {
        answer += content;
        if (answer.length > 32000) throw new Error('Reading answer exceeds verification budget');
      }
      res.write(`data: ${JSON.stringify({ content })}\n\n`);
    }
    if (canWrite(res)) {
      options.verifyAnswer?.(answer);
      res.locals.aiOutcome = 'completed';
      res.write(`data: ${JSON.stringify({ status: 'completed', finish_reason: 'stop' })}\n\n`);
      res.write('data: [DONE]\n\n');
      res.end();
    }
  } catch (error) {
    if (canWrite(res)) {
      res.locals.aiOutcome = error.name === 'AbortError' ? 'timed_out' : 'incomplete';
      const message = error.name === 'AbortError'
        ? '这段内容有些复杂，小U思考得久了一点。请稍后重试。'
        : error.code === 'AI_UNVERIFIABLE_QUOTE'
          ? '回答未通过原文核对，未保存为成功记录。请稍后重试。'
          : '回答未完整完成，未保存为成功记录。请稍后重试。';
      res.write(`data: ${JSON.stringify({ error: message, status: 'incomplete' })}\n\n`);
      res.end();
    }
  } finally {
    clearInterval(heartbeat);
    clearTimeout(upstreamTimeout);
  }
}

function canWrite(res) {
  return !res.writableEnded && !res.destroyed;
}

async function readerQuestion(req, res, next) {
  try {
    validateAiInput(req.body);
    const { message } = req.body;
    const question = String(message || '').trim();
    if (!question) {
      throw httpError(400, '问题不能为空');
    }
    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    const reading = buildReadingMessages(req.body, true);
    if (!reading.material.segments.length) {
      throw httpError(400, '当前阅读上下文为空');
    }
    await streamDeepSeek(req, res, reading.messages, {
      status: '小U正在读你眼前的这一页…',
      temperature: 0.3,
      maxTokens: 1800,
      verifyAnswer: answer => verifyDirectQuotes(answer, reading.material),
    });
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function xiaouAsks(req, res, next) {
  try {
    validateAiInput(req.body);
    const {
      history = [],
      current_book_id: currentBookId,
      current_book_title: currentBookTitle,
    } = req.body;
    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    const [entries, authorizedFreeNotes, publicTraces] = await Promise.all([
      entryRepository.listEntries(req.user.id, { limit: 180 }),
      freeNoteRepository.listAuthorizedForXiaou(req.user.id, { limit: 60 }),
      listPublicReadingTraces({ limit: 40 }),
    ]);
    const context = buildXiaouAgentContext({
      entries,
      authorizedFreeNotes,
      publicTraces,
    });
    const recentDialogue = normalizeChatHistory(history).slice(-12);
    const messages = [
      { role: 'system', content: XIAOU_ASKS_OPENING_PROMPT },
      {
        role: 'system',
        content:
          '以下是可用的阅读上下文。不要把授权随心记说成读书笔记；不要把明台公开痕迹说成用户自己的记录。\n\n' +
          context,
      },
      ...(clean(currentBookTitle) || clean(currentBookId)
        ? [
            {
              role: 'system',
              content: `当前阅读线索：${clean(currentBookTitle) || '未命名书籍'}${clean(currentBookId) ? `（book_id: ${clean(currentBookId)}）` : ''}。只有在上下文确实支持时才围绕它提问。`,
            },
          ]
        : []),
      ...recentDialogue,
      {
        role: 'user',
        content: recentDialogue.length
          ? '请换一个真正不同的阅读切口，只提出新的开放问题。'
          : '请从我的阅读里，提出第一个值得慢慢回答的开放问题。',
      },
    ];

    await streamDeepSeek(req, res, messages, {
      status: '小U正在想一个值得问的问题…',
      temperature: 0.75,
      maxTokens: 420,
    });
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

function explainLoadingStatus(mode) {
  return {
    auto: '小U正在判断这段难在哪里…',
    plain: '小U正在换一种说法…',
    structure: '小U正在拆开句子结构…',
    concept: '小U正在辨清概念边界…',
    argument: '小U正在还原论证脉络…',
  }[mode] || '小U正在阅读这一段…';
}

function normalizeChatHistory(history) {
  return normalizeHistory(history);
}

function buildXiaouAgentContext({ entries, authorizedFreeNotes, publicTraces }) {
  const blocks = [
    buildEntryContext(entries),
    buildAuthorizedFreeNoteContext(authorizedFreeNotes),
    buildPublicTraceContext(publicTraces),
  ].filter(Boolean);
  return blocks.join('\n\n---\n\n') || '目前还没有足够的阅读上下文。';
}

function buildEntryContext(entries = []) {
  if (!entries.length) return '【用户阅读痕迹】暂时为空。';
  const lines = entries.slice(0, 120).map((entry, index) => {
    const book = clean(entry.book_title) || '未知书籍';
    const chapter = clean(entry.chapter_title) || clean(entry.chapter_index);
    const source = sourceLabel(entry.source);
    const tags = tagsOf(entry);
    const original = clip(clean(entry.original_text), 180);
    const userInput = clip(clean(entry.user_input), 180);
    const aiExplanation = clip(clean(entry.ai_explanation), 180);
    const parts = [
      `${index + 1}. [${source}]《${book}》${chapter ? ` / ${chapter}` : ''}`,
      tags.length ? `标签：${tags.join('、')}` : '',
      original ? `原文：${original}` : '',
      userInput ? `用户想法：${userInput}` : '',
      aiExplanation ? `小U解读：${aiExplanation}` : '',
    ].filter(Boolean);
    return parts.join('\n');
  });
  return `【用户阅读痕迹】\n${lines.join('\n\n')}`;
}

function buildAuthorizedFreeNoteContext(notes = []) {
  if (!notes.length) return '【用户主动授权的随心记】暂时为空。';
  const lines = notes.slice(0, 40).map((note, index) => {
    const title = clean(note.title) || '无标题';
    const content = clip(clean(note.content), 220);
    return `${index + 1}. ${title}\n${content}`;
  });
  return `【用户主动授权的随心记】\n${lines.join('\n\n')}`;
}

function buildPublicTraceContext(traces = []) {
  if (!traces.length) return '【明台公开阅读痕迹】暂时为空。';
  const lines = traces.slice(0, 30).map((trace, index) => {
    const book = clean(trace.book_title) || '未知书籍';
    const source = sourceLabel(trace.source);
    const original = clip(clean(trace.original_text), 160);
    const annotation = clip(clean(trace.annotation_text), 180);
    return [
      `${index + 1}. [${source}]《${book}》`,
      original ? `原文：${original}` : '',
      annotation ? `公开想法：${annotation}` : '',
    ].filter(Boolean).join('\n');
  });
  return `【明台公开阅读痕迹】\n${lines.join('\n\n')}`;
}

async function listPublicReadingTraces({ limit = 40 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 40, 1), 80);
  const result = await query(
    `SELECT
       COALESCE(NULLIF(b.title, ''), NULLIF(a.book_title, '')) AS book_title,
       a.source,
       a.original_text,
       a.annotation_text,
       a.chapter_index,
       a.created_at
     FROM public_annotations a
     LEFT JOIN public_books b ON b.id = a.public_book_id
     WHERE COALESCE(NULLIF(a.original_text, ''), NULLIF(a.annotation_text, '')) IS NOT NULL
     ORDER BY a.created_at DESC
     LIMIT $1`,
    [safeLimit],
  );
  return result.rows;
}

function sourceLabel(source) {
  return {
    highlight: '划线',
    thought: '想法',
    ai_explanation: '小U解读',
    ai_question: '问小U',
    manual: '手动记录',
  }[source] || clean(source) || '记录';
}

function tagsOf(entry) {
  if (Array.isArray(entry?.auto_tags)) {
    return entry.auto_tags.map(clean).filter(Boolean).slice(0, 6);
  }
  return clean(entry?.auto_tags)
    .split(',')
    .map(clean)
    .filter(Boolean)
    .slice(0, 6);
}

function clean(value) {
  return String(value || '').replace(/\s+/g, ' ').trim();
}

function clip(value, maxLength) {
  if (!value) return '';
  return value.length > maxLength ? `${value.slice(0, maxLength)}……` : value;
}

module.exports = { explain, readerQuestion, chat, xiaouAsks };
