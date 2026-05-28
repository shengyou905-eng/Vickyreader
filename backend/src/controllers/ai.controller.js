const entryRepository = require('../repositories/entry.repository');
const httpError = require('../utils/httpError');

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

const EXPLAIN_PROMPT = `你是「小U」，知读App的AI阅读伙伴。用户正在阅读一本书，选中了一段文字请你解释。

规则：
1. 根据上下文解释用户选中的文字。回答要简洁、准确、有深度
2. 如果涉及专有名词、典故、历史事件等，请提供背景知识
3. 用中文回答，控制在 200-400 字以内
4. 追问时继续保持解释者的角色，深入展开`;

const SYSTEM_PROMPT = `你是「小U」，知读App的AI阅读伙伴。

你的知识来源是用户留下的阅读痕迹——他们读过的书、划过的线、写下的想法、问过的小U解释。
你不是通用AI助手，你是一个了解用户阅读历程的思考伙伴。

规则：
1. 回答要基于用户的阅读记录，引用具体的书名和段落
2. 语气温暖但不腻，像一位爱读书的朋友在和你聊天
3. 如果用户的记录不足以回答某个问题，诚实说明，不要编造
4. 回答控制在 300 字以内，除非用户明确要求更详细
5. 用中文回答`;

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

    await streamDeepSeek(req, res, messages);
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function chat(req, res, next) {
  try {
    const { message, history = [] } = req.body;
    if (!message || !message.trim()) {
      throw httpError(400, '消息不能为空');
    }

    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    // 获取用户最近 200 条阅读记录作为 context
    const entries = await entryRepository.listEntries(req.user.id, { limit: 200 });
    const context = buildContext(entries);

    // 构建消息
    const messages = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'system', content: `以下是用户近期的阅读记录，请基于这些内容回答问题：\n\n${context}` },
      ...history.slice(-10).map((m) => ({ role: m.role, content: m.content })),
      { role: 'user', content: message },
    ];

    await streamDeepSeek(req, res, messages);
  } catch (error) {
    if (!res.headersSent) return next(error);
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

async function streamDeepSeek(req, res, messages) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();
  res.write(`data: ${JSON.stringify({ status: '小U正在阅读这一段…' })}\n\n`);

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

function buildContext(entries) {
  if (!entries || entries.length === 0) {
    return '用户还没有任何阅读记录。';
  }

  const lines = entries.slice(0, 200).map((entry, i) => {
    const book = entry.book_title || '未知书籍';
    const text = entry.original_text || entry.user_input || entry.ai_explanation || '';
    const source = sourceLabel(entry.source);
    const tags = tagsOf(entry).join('、');
    return `${i + 1}. [${source}]《${book}》${tags ? ` 🏷${tags}` : ''}\n   ${text.slice(0, 200)}`;
  });

  return `共 ${entries.length} 条记录（展示最近 ${Math.min(entries.length, 200)} 条）：\n\n${lines.join('\n\n')}`;
}

function sourceLabel(source) {
  return {
    highlight: '划线',
    thought: '想法',
    ai_explanation: '小U解释',
    manual: '手动',
  }[source] || source;
}

function tagsOf(entry) {
  if (Array.isArray(entry.auto_tags)) return entry.auto_tags;
  if (typeof entry.auto_tags === 'string')
    return entry.auto_tags.split(',').map((t) => t.trim()).filter(Boolean);
  return [];
}

module.exports = { chat, explain };
