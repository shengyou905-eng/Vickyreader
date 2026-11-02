const { TextDecoder } = require('node:util');

function inputError(message, status = 400) {
  return Object.assign(new Error(message), { status, statusCode: status });
}

function validateAiInput(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw inputError('AI request must be an object');
  }
  const limits = {
    message: 8000, selectedText: 12000, paragraph: 8000,
    contextBefore: 4000, contextAfter: 4000, pageText: 8000,
    chapterText: 24000, bookTitle: 500, bookAuthor: 300,
    chapterTitle: 500, mode: 32, scope: 32, initialAnswer: 12000,
    initialQuestion: 8000, current_book_id: 300, current_book_title: 500,
  };
  for (const [field, limit] of Object.entries(limits)) {
    if (body[field] == null) continue;
    if (typeof body[field] !== 'string') throw inputError(`Invalid ${field}`);
    if (body[field].length > limit) throw inputError(`${field} exceeds input budget`, 413);
  }
  if (JSON.stringify(body).length > 160000) throw inputError('AI input exceeds budget', 413);
  normalizeHistory(body.history);
}

function normalizeHistory(history) {
  if (history == null) return [];
  if (!Array.isArray(history) || history.length > 200) throw inputError('Invalid history');
  for (const item of history) {
    if (!item || !['user', 'assistant'].includes(item.role) || typeof item.content !== 'string') {
      throw inputError('History only accepts user and assistant text');
    }
    if (item.content.length > 16000) throw inputError('History message exceeds budget', 413);
  }
  let remaining = 32000;
  const result = [];
  for (const item of history.slice(-24).reverse()) {
    const content = item.content.trim();
    if (!content) continue;
    if (content.length > remaining) break;
    result.unshift({ role: item.role, content });
    remaining -= content.length;
  }
  return result;
}

// The evidence is separate from the rolling conversation window.
function explanationEvidence(body) {
  return [
    body.contextBefore ? `【前文】\n${body.contextBefore}` : '',
    body.paragraph ? `【所在段落】\n${body.paragraph}` : '',
    body.selectedText ? `【首轮原文】\n${body.selectedText}` : '',
    body.contextAfter ? `【后文】\n${body.contextAfter}` : '',
    body.initialQuestion ? `【首轮问题】\n${body.initialQuestion}` : '',
    body.initialAnswer ? `【首轮AI解释，不是原文证据】\n${body.initialAnswer}` : '',
  ].filter(Boolean).join('\n\n');
}

async function* readCompletion(body) {
  const reader = body.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let buffer = '';
  let finishReason;
  let hasContent = false;
  try {
    while (true) {
      const { done, value } = await reader.read();
      buffer += done ? decoder.decode() : decoder.decode(value, { stream: true });
      if (buffer.length > 256000) throw new Error('AI stream frame exceeds budget');
      const lines = buffer.split('\n');
      buffer = done ? '' : lines.pop();
      for (const line of lines) {
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (data === '[DONE]') {
          if (finishReason !== 'stop' || !hasContent) throw new Error('AI response incomplete');
          return;
        }
        const event = JSON.parse(data);
        if (event.error) throw new Error('AI upstream error');
        const choice = event.choices?.[0];
        if (!choice) continue;
        if (choice.finish_reason != null) {
          finishReason = choice.finish_reason;
          if (finishReason !== 'stop') throw new Error('AI response truncated or rejected');
        }
        const content = choice.delta?.content;
        if (content != null && typeof content !== 'string') throw new Error('Invalid AI content');
        if (content) {
          hasContent = true;
          yield content;
        }
      }
      if (done) throw new Error('AI stream disconnected before completion');
    }
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

module.exports = { validateAiInput, normalizeHistory, explanationEvidence, readCompletion };
