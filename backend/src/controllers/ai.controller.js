const { query } = require('../config/db');
const entryRepository = require('../repositories/entry.repository');
const freeNoteRepository = require('../repositories/freeNote.repository');
const httpError = require('../utils/httpError');

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

const EXPLAIN_PROMPT = `你是「小U」，知读App的AI阅读伙伴。用户正在阅读一本书，选中了一段文字请你解释。

规则：
1. 根据上下文解释用户选中的文字。回答要简洁、准确、有深度
2. 如果涉及专有名词、典故、历史事件等，请提供背景知识
3. 用中文回答，控制在 200-400 字以内
4. 追问时继续保持解释者的角色，深入展开`;

const XIAOU_AGENT_PROMPT = `你是「小U」，知读 App 里的阅读 Agent。

你不是通用 ChatGPT，不是总结工具，不是心理测试，也不是阅读数据统计器。
你更像一个长期陪用户读书的人：记得用户在哪里停过，也能和用户直接说话。

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
7. 如果没有真正值得说的新联系，就直接说「我还没看见值得轻易说出口的东西」，不要为了回答而总结。
8. 数量只能作为辅助依据，不能成为回答主体。

禁止使用这些表达：
- 根据数据分析
- 你留下了多少条记录
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

async function explain(req, res, next) {
  try {
    const {
      selectedText,
      contextBefore,
      contextAfter,
      bookTitle,
      bookAuthor,
      message,
      history = [],
    } = req.body;

    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    const bookInfo = [
      bookTitle ? `《${bookTitle}》` : '',
      bookAuthor ? `作者：${bookAuthor}` : '',
    ]
      .filter(Boolean)
      .join('，');

    const systemContent = bookInfo
      ? `${EXPLAIN_PROMPT}\n\n当前书籍：${bookInfo}`
      : EXPLAIN_PROMPT;

    let messages;
    if (message && message.trim()) {
      // 追问模式：延续对话历史
      if (history.length === 0) {
        throw httpError(400, '追问模式下需要提供对话历史');
      }
      messages = [
        { role: 'system', content: systemContent },
        ...history.slice(-10).map((m) => ({ role: m.role, content: m.content })),
        { role: 'user', content: message.trim() },
      ];
    } else {
      // 首次解释模式
      if (!selectedText || !selectedText.trim()) {
        throw httpError(400, '选中文字不能为空');
      }
      const contextBlock = [
        contextBefore ? `上文：${contextBefore}` : '',
        `【选中文字】${selectedText}`,
        contextAfter ? `下文：${contextAfter}` : '',
      ]
        .filter(Boolean)
        .join('\n');

      messages = [
        { role: 'system', content: systemContent },
        ...history.slice(-10).map((m) => ({ role: m.role, content: m.content })),
        { role: 'user', content: `请结合上下文解释这段文字：\n\n${contextBlock}` },
      ];
    }

    await streamDeepSeek(req, res, messages, {
      status: '小U正在阅读这一段…',
    });
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function chat(req, res, next) {
  try {
    const { message, history = [] } = req.body;
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
      { role: 'system', content: XIAOU_AGENT_PROMPT },
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
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
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
        model: 'deepseek-chat',
        messages,
        temperature: 0.7,
        max_tokens: 1200,
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

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const data = line.slice(6).trim();
        if (data === '[DONE]') {
          if (canWrite(res)) res.write('data: [DONE]\n\n');
          continue;
        }
        try {
          const parsed = JSON.parse(data);
          const content = parsed.choices?.[0]?.delta?.content;
          if (content && canWrite(res)) {
            res.write(`data: ${JSON.stringify({ content })}\n\n`);
          }
        } catch (_) {
          // skip malformed chunks
        }
      }
    }

    if (canWrite(res)) res.end();
  } catch (error) {
    if (canWrite(res)) {
      const message = error.name === 'AbortError'
        ? '这段内容有些复杂，小U思考得久了一点。请稍后重试。'
        : '网络似乎有些慢，请稍后重试。';
      res.write(`data: ${JSON.stringify({ error: message })}\n\n`);
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

function normalizeChatHistory(history) {
  if (!Array.isArray(history)) return [];
  return history
    .slice(-10)
    .map((item) => ({
      role: item?.role === 'assistant' ? 'assistant' : 'user',
      content: String(item?.content || '').trim(),
    }))
    .filter((item) => item.content);
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

module.exports = { explain, chat };
