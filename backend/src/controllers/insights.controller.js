const entryRepository = require('../repositories/entry.repository');
const httpError = require('../utils/httpError');

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

const SYSTEM_PROMPT = `你是「小U」，知读App的AI阅读伙伴。

你的任务是基于用户的阅读记录，回答他们关于自己阅读历程的洞察问题。

规则：
1. 仔细分析提供的阅读记录——划线、想法、小U解释，从中发现模式、主题和变化
2. 回答要具体，引用书名和具体段落作为例证
3. 语气温暖有洞察力，像一位了解你阅读习惯的朋友在帮你回顾
4. 如果记录不足以得出有意义的结论，诚实指出并鼓励用户多留下痕迹
5. 用中文回答，控制在 400 字以内`;

const questions = {
  recent_focus: '我最近在关注什么？',
  freedom_books: '我在哪些书里反复提到"自由"？',
  weekly_summary: '本周阅读摘要',
  top_highlight_themes: '我最常划线的主题',
  touching_recently: '最近哪些内容最触动我？',
};

async function answerQuestion(req, res, next) {
  try {
    const questionId = req.params.questionId;
    const question = questions[questionId];
    if (!question) {
      throw httpError(400, '未知的洞察问题');
    }

    if (!DEEPSEEK_API_KEY) {
      throw httpError(500, '未配置 DEEPSEEK_API_KEY 环境变量');
    }

    // 获取用户最近 500 条阅读记录
    const entries = await entryRepository.listEntries(req.user.id, { limit: 500 });
    const context = buildContext(entries);

    const messages = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'system', content: `以下是用户的阅读记录，请基于这些内容回答问题：\n\n${context}` },
      { role: 'user', content: question },
    ];

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
        max_tokens: 800,
        stream: false,
      }),
    });

    if (!response.ok) {
      const errText = await response.text().catch(() => '');
      throw httpError(502, `AI 服务异常 (${response.status}): ${errText.slice(0, 100)}`);
    }

    const data = await response.json();
    const answer =
      data.choices?.[0]?.message?.content || '小U暂时无法回答这个问题，请稍后再试。';

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

function buildContext(entries) {
  if (!entries || entries.length === 0) {
    return '用户还没有任何阅读记录。鼓励用户多划线、写想法、使用小U解释，积累后再来回顾。';
  }

  const lines = entries.slice(0, 500).map((entry, i) => {
    const book = entry.book_title || '未知书籍';
    const text = entry.original_text || entry.user_input || entry.ai_explanation || '';
    const source = sourceLabel(entry.source);
    const tags = tagsOf(entry).join('、');
    return `${i + 1}. [${source}]《${book}》${tags ? ` 🏷${tags}` : ''}\n   ${text.slice(0, 200)}`;
  });

  return `共 ${entries.length} 条记录（展示最近 ${Math.min(entries.length, 500)} 条）：\n\n${lines.join('\n\n')}`;
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

module.exports = { answerQuestion };
