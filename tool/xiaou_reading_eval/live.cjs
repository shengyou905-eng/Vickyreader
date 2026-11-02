const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const https = require('node:https');
const http = require('node:http');
const crypto = require('node:crypto');
const { performance } = require('node:perf_hooks');
const { buildReadingMessages, verifyDirectQuotes, PROMPT_VERSION } = require('../../backend/src/services/readingInterpretation');
const { explanationEvidence, normalizeHistory } = require('../../backend/src/services/aiProtocol');
const suite = require('./cases.v1.json');

const ROOT = path.resolve(__dirname, '../..');
const OUTPUT = path.join(ROOT, 'artifacts/xiaou-reading-eval/p0b-stage3-20261019');
const OLD_SOURCE = 'D:/Zhidu-private-backups/reader-pre-isolation-20261018-01/restore-check/backend/src/controllers/ai.controller.js';
const OLD_HASH = '1f1cb12266a6c800610f7222922fc25492ca57cb8caba34b398746f5f112e41e';
const ENDPOINT = 'https://api.deepseek.com/v1/chat/completions';
const MODEL = 'deepseek-v4-flash';
const IDS = ['AUTO-01', 'PLAIN-02', 'STRUCTURE-02', 'CONCEPT-04', 'ARGUMENT-04'];
const LANGUAGE = { role: 'system', content: '使用自然中文回答。保留必要的原文引用，不使用 Markdown 标记，除非用户明确要求 Markdown。' };
const PRICING = { currency: 'CNY', inputMiss: 2, inputHit: 0.04, output: 8,
  basis: 'official peak rates per million tokens; not an account debit',
  url: 'https://api-docs.deepseek.com/zh-cn/quick_start/pricing/', checkedDate: '2026-10-19' };
const fail = code => Object.assign(new Error(code), { code });
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

function recoverLegacy() {
  const source = fs.readFileSync(OLD_SOURCE, 'utf8');
  if (hash(source) !== OLD_HASH) throw fail('OLD_SOURCE_HASH_MISMATCH');
  const base = source.match(/const EXPLAIN_BASE_PROMPT = (`[\s\S]*?`);/)?.[0];
  const modes = source.match(/const EXPLAIN_MODE_PROMPTS = (\{[\s\S]*?\r?\n\});/)?.[0];
  if (!base || !modes) throw fail('OLD_PROMPTS_NOT_FOUND');
  // Evaluate only two literal declarations from the hash-verified snapshot, never the controller.
  return vm.runInNewContext(`${base}\n${modes}\n({base:EXPLAIN_BASE_PROMPT,modes:EXPLAIN_MODE_PROMPTS})`, {}, { timeout: 1000 });
}

function legacyMessages(body, legacy) {
  const bookInfo = [body.bookTitle ? `《${body.bookTitle}》` : '', body.bookAuthor ? `作者：${body.bookAuthor}` : '', body.chapterTitle ? `章节：${body.chapterTitle}` : ''].filter(Boolean).join('，');
  const follow = Boolean(body.message?.trim());
  const instruction = [legacy.modes[body.mode], follow ? '当前任务：回应追问。首轮原文始终是证据，首轮AI解释和历史回答不是原文事实。保留原解读模式的分析方法，但不必重复全部栏目。' : ''].filter(Boolean).join('\n');
  const system = [legacy.base, instruction, bookInfo ? `当前阅读位置：${bookInfo}` : ''].filter(Boolean).join('\n\n');
  const context = [body.contextBefore ? `【前文】\n${body.contextBefore}` : '', body.paragraph ? `【所在段落】\n${body.paragraph}` : '', `【选中文字】${body.selectedText}`, body.contextAfter ? `【后文】\n${body.contextAfter}` : ''].filter(Boolean).join('\n');
  return [{ role: 'system', content: system }, ...(follow
    ? [{ role: 'user', content: explanationEvidence(body) }, ...normalizeHistory(body.history), { role: 'user', content: body.message.trim() }]
    : [{ role: 'user', content: `请按照「${body.mode}」方式解读，并结合上下文说明：\n\n${context}` }])];
}

function makePlan() {
  const legacy = recoverLegacy();
  const tasks = [];
  for (const id of IDS) {
    const item = suite.cases.find(row => row.id === id);
    if (!item) throw fail('CASE_MISSING');
    const pairs = [{ turn: 'initial', body: item.request }];
    if (id === 'ARGUMENT-04') pairs.push({ turn: 'controlled-correction-1', body: {
      ...item.request, initialAnswer: item.seed_answer, message: item.follow_ups[0].question,
      history: [{ role: 'user', content: `「${item.request.selectedText}」\n论证脉络` }, { role: 'assistant', content: item.seed_answer }],
    } });
    for (const pair of pairs) {
      const variants = crypto.randomInt(2) ? ['legacy', 'current'] : ['current', 'legacy'];
      for (const [index, variant] of variants.entries()) {
        const reading = buildReadingMessages(pair.body);
        const messages = [LANGUAGE, ...(variant === 'current' ? reading.messages : legacyMessages(pair.body, legacy))];
        const bytes = Buffer.byteLength(JSON.stringify(messages));
        if (bytes > 16000 || messages.length > 30) throw fail('INPUT_RESERVATION_EXCEEDED');
        const payload = { model: MODEL, messages, temperature: 0.3, thinking: { type: 'disabled' },
          max_tokens: ['structure', 'argument'].includes(item.mode) ? 1800 : 1400,
          stream: true, stream_options: { include_usage: true } };
        const inputReservation = bytes + 8192;
        tasks.push({ id: `${id}-${pair.turn}-${index ? 'B' : 'A'}`, caseId: id, turn: pair.turn,
          variant, body: pair.body, payload, material: reading.material,
          requestHash: hash(JSON.stringify(payload)), inputReservation,
          reserveCny: (inputReservation * PRICING.inputMiss + payload.max_tokens * PRICING.output) / 1e6 });
      }
    }
  }
  assertPlan(tasks);
  return { tasks, maxCalls: 12, budgetCny: 2, noRetries: true, model: MODEL, promptVersion: PROMPT_VERSION,
    oldSourceHash: OLD_HASH, currentPromptHash: hash(fs.readFileSync(path.join(ROOT, 'backend/src/services/readingInterpretation.js'))),
    suiteHash: hash(fs.readFileSync(path.join(__dirname, 'cases.v1.json'))),
    rubricHash: hash(fs.readFileSync(path.join(__dirname, 'rubric.v1.json'))),
    pricing: PRICING, reservedCny: tasks.reduce((sum, task) => sum + Math.round(task.reserveCny * 1e9), 0) / 1e9 };
}

function assertPlan(tasks) {
  if (tasks.length !== 12 || new Set(tasks.map(row => row.id)).size !== 12) throw fail('CALL_LIMIT');
  if (tasks.some(row => row.reserveCny < 0 || !Number.isFinite(row.reserveCny)) || tasks.reduce((sum, row) => sum + row.reserveCny, 0) > 2) throw fail('BUDGET_LIMIT');
  for (const task of tasks) {
    if (task.payload.model !== MODEL || task.payload.thinking.type !== 'disabled' || task.payload.max_tokens > 1800) throw fail('PARAMETER_MISMATCH');
  }
}

function usageCost(usage) {
  const valid = value => Number.isSafeInteger(value) && value >= 0;
  if (!usage || !['prompt_tokens', 'prompt_cache_hit_tokens', 'prompt_cache_miss_tokens', 'completion_tokens'].every(key => valid(usage[key]))) return null;
  if (usage.prompt_tokens !== usage.prompt_cache_hit_tokens + usage.prompt_cache_miss_tokens) return null;
  return (usage.prompt_cache_miss_tokens * PRICING.inputMiss + usage.prompt_cache_hit_tokens * PRICING.inputHit + usage.completion_tokens * PRICING.output) / 1e6;
}

function selectUsage(raw) {
  if (!raw || typeof raw !== 'object') return null;
  return Object.fromEntries(['prompt_tokens', 'prompt_cache_hit_tokens', 'prompt_cache_miss_tokens', 'completion_tokens', 'total_tokens'].map(key => [key, Number.isSafeInteger(raw[key]) && raw[key] >= 0 ? raw[key] : null]).concat([
    ['reasoning_tokens', Number.isSafeInteger(raw.completion_tokens_details?.reasoning_tokens) ? raw.completion_tokens_details.reasoning_tokens : null],
  ]));
}

async function sendSse(payload, key, endpoint = ENDPOINT) {
  if (endpoint !== ENDPOINT && !/^http:\/\/127\.0\.0\.1:\d+\/$/.test(endpoint)) throw fail('ENDPOINT_NOT_ALLOWED');
  const started = performance.now();
  const result = { startedAt: new Date().toISOString(), requestedModel: payload.model, returnedModel: null,
    answer: '', usage: null, finishReason: null, done: false, ttftMs: null, elapsedMs: null,
    httpStatus: null, error: null, unexpectedReasoning: false };
  const request = endpoint.startsWith('https:') ? https.request : http.request;
  try {
    await new Promise((resolve, reject) => {
      const req = request(endpoint, { method: 'POST', headers: { 'content-type': 'application/json',
        accept: 'text/event-stream', authorization: `Bearer ${key}`, connection: 'close' } }, async res => {
        result.httpStatus = res.statusCode;
        if (res.statusCode !== 200) { res.resume(); reject(fail('HTTP_ERROR')); return; }
        const decoder = new TextDecoder('utf-8', { fatal: true });
        let buffer = '';
        let received = 0;
        const line = text => {
          if (!text.startsWith('data:') || result.done) return;
          const data = text.slice(5).trim();
          if (data === '[DONE]') { result.done = true; return; }
          const event = JSON.parse(data);
          if (event.error) throw fail('UPSTREAM_ERROR');
          if (typeof event.model === 'string') result.returnedModel = event.model;
          if (event.usage) result.usage = selectUsage(event.usage);
          const choice = event.choices?.[0];
          if (choice?.finish_reason != null) result.finishReason = choice.finish_reason;
          if (choice?.delta?.reasoning_content) result.unexpectedReasoning = true;
          const content = choice?.delta?.content;
          if (content != null && typeof content !== 'string') throw fail('INVALID_CONTENT');
          if (content) {
            result.ttftMs ??= Math.round(performance.now() - started);
            result.answer += content;
          }
        };
        try {
          for await (const chunk of res) {
            received += chunk.length;
            if (received > 1048576) throw fail('RESPONSE_TOO_LARGE');
            buffer += decoder.decode(chunk, { stream: true });
            let end;
            while ((end = buffer.indexOf('\n')) >= 0) {
              line(buffer.slice(0, end).replace(/\r$/, ''));
              buffer = buffer.slice(end + 1);
            }
          }
          buffer += decoder.decode();
          if (buffer.trim()) line(buffer.trim());
          resolve();
        } catch (error) { res.destroy(); reject(error); }
      });
      const timeout = setTimeout(() => req.destroy(fail('REQUEST_TIMEOUT')), 120000);
      req.on('close', () => clearTimeout(timeout));
      req.on('error', reject);
      req.end(JSON.stringify(payload));
    });
  } catch (error) {
    result.error = ['HTTP_ERROR', 'UPSTREAM_ERROR', 'REQUEST_TIMEOUT', 'RESPONSE_TOO_LARGE', 'INVALID_CONTENT'].includes(error.code) ? error.code : 'TRANSPORT_OR_PARSE_ERROR';
  }
  result.elapsedMs = Math.round(performance.now() - started);
  result.status = !result.error && result.done && result.finishReason === 'stop' && result.answer.trim() ? 'completed' : 'incomplete';
  return result;
}

function redact(value, key) {
  if (typeof value === 'string') return value.split(key).join('[REDACTED_SECRET]');
  if (Array.isArray(value)) return value.map(item => redact(item, key));
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([name, item]) => [name, redact(item, key)]));
  return value;
}

function save(directory, name, value) {
  fs.writeFileSync(path.join(directory, name), JSON.stringify(value, null, 2));
}

async function runBatch(plan, key, directory = OUTPUT, transport = sendSse) {
  assertPlan(plan.tasks);
  if (typeof key !== 'string' || key.trim().length < 20) throw fail('CREDENTIAL_MISSING_OR_TOO_SHORT');
  key = key.trim();
  fs.mkdirSync(directory, { recursive: true });
  const lock = fs.openSync(path.join(directory, 'execution.lock'), 'wx');
  fs.writeSync(lock, 'Single batch. Never remove to retry a paid request.\n');
  fs.fsyncSync(lock); fs.closeSync(lock);
  const { tasks, ...summary } = plan;
  save(directory, 'plan.json', { ...summary, reservationNote: 'UTF-8 message bytes + 8192 framing allowance; conservative reservation, not measured tokenizer output.',
    items: tasks.map(task => ({ id: task.id, caseId: task.caseId, turn: task.turn, reserveCny: task.reserveCny, requestHash: task.requestHash, outputCap: task.payload.max_tokens })) });
  save(directory, 'unblinding.json', tasks.map(task => ({ id: task.id, variant: task.variant })));
  const records = [];
  let reserved = 0;
  let stopReason = null;
  for (const task of tasks) {
    if (records.length >= 12 || reserved + task.reserveCny > 2) { stopReason = 'ADMISSION_LIMIT'; break; }
    const attempt = records.length + 1;
    const marker = fs.openSync(path.join(directory, `attempt-${String(attempt).padStart(2, '0')}.reserved.json`), 'wx');
    fs.writeSync(marker, JSON.stringify({ id: task.id, reserveCny: task.reserveCny }));
    fs.fsyncSync(marker); fs.closeSync(marker);
    reserved += task.reserveCny;
    let result;
    try { result = await transport(task.payload, key); }
    catch {
      result = { answer: '', usage: null, status: 'incomplete', error: 'TRANSPORT_FAILED',
        returnedModel: null, finishReason: null, done: false, elapsedMs: null, ttftMs: null };
    }
    const secretEchoed = JSON.stringify(result).includes(key);
    const clean = redact(result, key);
    let quoteCheck = 'passed';
    try { verifyDirectQuotes(clean.answer, task.material); } catch { quoteCheck = 'failed'; }
    const record = { id: task.id, caseId: task.caseId, turn: task.turn, ...clean,
      calculatedPeakCostCny: usageCost(clean.usage), actualAccountDebitCny: null,
      explicitQuoteCheck: quoteCheck, secretRedacted: secretEchoed };
    records.push(record);
    save(directory, 'responses.json', records);
    const usage = clean.usage;
    if (secretEchoed) stopReason = 'SECRET_ECHO_REDACTED';
    else if (clean.status !== 'completed') stopReason = 'UPSTREAM_NOT_COMPLETED';
    else if (record.calculatedPeakCostCny == null) stopReason = 'USAGE_OR_CACHE_BREAKDOWN_UNKNOWN';
    else if (clean.unexpectedReasoning) stopReason = 'UNEXPECTED_THINKING_MODE';
    else if (usage.prompt_tokens > task.inputReservation || usage.completion_tokens > task.payload.max_tokens || record.calculatedPeakCostCny > task.reserveCny) stopReason = 'RESERVATION_MISMATCH';
    if (stopReason) break;
  }
  const result = { callsAttempted: records.length, completed: records.filter(row => row.status === 'completed').length,
    reservedCny: reserved, calculatedPeakTotalCny: records.every(row => row.calculatedPeakCostCny != null) ? records.reduce((sum, row) => sum + row.calculatedPeakCostCny, 0) : null,
    actualAccountDebitCny: null, stopReason, noRetries: true };
  save(directory, 'summary.json', result);
  const blind = ['# 小U匿名回答复核', '', '请先评分，再打开 unblinding.json。A/B 每组独立随机，不代表固定新旧版本。',
    '所有材料为合成文本。纠错组使用固定的故意错误历史，不表示真实首轮回答犯过该错误。', ''];
  for (const task of tasks) {
    const record = records.find(row => row.id === task.id);
    blind.push(`## ${task.id}`, '', `原文：${task.body.selectedText}`, `前文：${task.body.contextBefore || '无'}`,
      `当前问题：${task.body.message || '按指定模式解读原文'}`, `模式：${suite.cases.find(row => row.id === task.caseId).mode}`);
    if (task.turn !== 'initial') blind.push(`固定错误历史：${task.body.initialAnswer}`);
    blind.push('', record ? record.answer || '（没有收到回答文本）' : '（未调用）', '', `完成状态：${record?.status || 'not_attempted'}`, '',
      '人工评分：正确性 __/4；证据 __/4；模式 __/4；可读性 __/4；边界 __/4；关键错误：____', '');
  }
  fs.writeFileSync(path.join(directory, 'blind-review.md'), redact(blind.join('\n'), key));
  return result;
}

module.exports = { makePlan, assertPlan, usageCost, selectUsage, sendSse, runBatch, OUTPUT };

if (require.main === module) {
  (async () => {
    const plan = makePlan();
    if (process.argv.length === 2 || process.argv[2] === '--plan') {
      console.log(JSON.stringify({ plannedCalls: plan.tasks.length, noRetries: true, model: plan.model,
        reservedCny: plan.reservedCny, maxBudgetCny: 2, oldSourceHash: plan.oldSourceHash }, null, 2));
      return;
    }
    if (process.argv.length !== 3 || process.argv[2] !== '--execute') throw fail('INVALID_ARGUMENTS');
    const result = await runBatch(plan, process.env.DEEPSEEK_API_KEY);
    console.log(JSON.stringify({ ...result, output: OUTPUT }, null, 2));
    if (result.stopReason) process.exitCode = 2;
  })().catch(error => {
    const code = /^[A-Z_]+$/.test(error.code || '') ? error.code : error.code === 'EEXIST' ? 'BATCH_ALREADY_LOCKED_NO_RETRY' : 'RUNNER_ERROR';
    console.error(JSON.stringify({ error: code, noRetry: true }));
    process.exitCode = 1;
  });
}
