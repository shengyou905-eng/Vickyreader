const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { isDeepStrictEqual } = require('node:util');
const { buildReadingMessages, verifyDirectQuotes, PROMPT_VERSION } = require('../../backend/src/services/readingInterpretation');
const { sendSse, usageCost } = require('./live.cjs');
const ROOT = path.resolve(__dirname, '../..');
const PREVIOUS = path.join(ROOT, 'artifacts/xiaou-reading-eval/p0b-stage3-20261019');
const OUTPUT = path.join(ROOT, 'artifacts/xiaou-reading-eval/p0b-v3-retest-20261020');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const fail = code => Object.assign(new Error(code), { code });
const read = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const PRICING = { currency: 'CNY', inputMiss: 2, inputHit: 0.04, output: 8,
  checkedDate: '2026-10-20', basis: 'official peak rates per million tokens; account debit unknown',
  url: 'https://api-docs.deepseek.com/zh-cn/quick_start/pricing/' };

function makePlan() {
  const checks = [
    ['tool/xiaou_reading_eval/cases.v1.json', '61c6c0c84146fa9102bd5db223161059d3ee9df251b056858b7126d86e34b0d9'],
    ['tool/xiaou_reading_eval/rubric.v1.json', '45da3f3c2d8969ca2a643a42c058fdadfddd89b88a41ed053b5d089c5884e776'],
    ['backend/src/services/readingInterpretation.js', 'c2900e47bba556e4fd6b060f6cd7da538658a895bebf058912bfe54ea98a91a4'],
    ['artifacts/xiaou-reading-eval/p0b-stage3-20261019/responses.json', '2f103e9973a655c70d9de8e2a71ff51293a5bffbdd3f66a3cd1efcb2b298851f'],
  ];
  for (const [file, expected] of checks) {
    if (hash(fs.readFileSync(path.join(ROOT, file))) !== expected) throw fail('SOURCE_HASH_MISMATCH');
  }
  if (PROMPT_VERSION !== 'xiaou-reading-v3.20261019') throw fail('VERSION_MISMATCH');
  const suite = read(path.join(__dirname, 'cases.v1.json'));
  const previousPlan = read(path.join(PREVIOUS, 'plan.json'));
  if (previousPlan.promptVersion !== 'xiaou-reading-v2.20261019') throw fail('BASELINE_VERSION_MISMATCH');
  const previousAnswers = read(path.join(PREVIOUS, 'responses.json'));
  const mapping = read(path.join(PREVIOUS, 'unblinding.json'));
  const tasks = ['AUTO-01', 'PLAIN-02', 'ARGUMENT-04'].map(caseId => {
    const item = suite.cases.find(row => row.id === caseId);
    const correction = caseId === 'ARGUMENT-04';
    const turn = correction ? 'controlled-correction-1' : 'initial';
    const body = correction ? { ...item.request, initialAnswer: item.seed_answer,
      message: item.follow_ups[0].question,
      history: [{ role: 'user', content: `「${item.request.selectedText}」\n论证脉络` }, { role: 'assistant', content: item.seed_answer }],
    } : item.request;
    const reading = buildReadingMessages(body);
    const payload = { model: 'deepseek-v4-flash', messages: [
      { role: 'system', content: '使用自然中文回答。保留必要的原文引用，不使用 Markdown 标记，除非用户明确要求 Markdown。' },
      ...reading.messages,
    ], temperature: 0.3, thinking: { type: 'disabled' }, max_tokens: correction ? 1800 : 1400,
    stream: true, stream_options: { include_usage: true } };
    const bytes = Buffer.byteLength(JSON.stringify(payload.messages));
    if (bytes > 16000 || payload.messages.length > 30) throw fail('INPUT_LIMIT');
    const inputReservation = bytes + 8192;
    const baseline = previousAnswers.find(row => row.caseId === caseId && row.turn === turn
      && mapping.some(m => m.id === row.id && m.variant === 'current'));
    if (!baseline || baseline.status !== 'completed' || baseline.requestedModel !== payload.model) throw fail('BASELINE_MISSING');
    return { caseId, turn, body, payload, material: reading.material, baseline,
      requestHash: hash(JSON.stringify(payload)), inputReservation,
      reserveCny: (inputReservation * PRICING.inputMiss + payload.max_tokens * PRICING.output) / 1e6 };
  });
  const reservedCny = tasks.reduce((sum, task) => sum + Math.round(task.reserveCny * 1e9), 0) / 1e9;
  if (tasks.length !== 3 || reservedCny > 0.5) throw fail('BUDGET_OR_COUNT_LIMIT');
  return { tasks, promptVersion: PROMPT_VERSION, maxAuthorizedCalls: 4, plannedCalls: 3,
    budgetCny: 0.5, reservedCny, noRetries: true, pricing: PRICING,
    hashes: Object.fromEntries(checks), comparison: 'archived v2 versus new v3, not simultaneous or repeated sampling' };
}

function durableNew(file, value) {
  const fd = fs.openSync(file, 'wx');
  try { fs.writeSync(fd, JSON.stringify(value, null, 2)); fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
}

async function runBatch(plan, key, directory = OUTPUT, transport = sendSse) {
  // Rebuild the authorized plan before taking a lock or sending any request.
  if (!isDeepStrictEqual(plan, makePlan())) throw fail('PLAN_CHANGED');
  if (typeof key !== 'string' || key.trim().length < 20) throw fail('CREDENTIAL_MISSING');
  key = key.trim();
  const serialize = value => JSON.stringify(value, null, 2).split(key).join('[REDACTED_SECRET]');
  fs.mkdirSync(directory, { recursive: true });
  durableNew(path.join(directory, 'execution.lock'), { plannedCalls: 3, noRetries: true,
    note: 'Never remove to retry. Old stage3 lock remains untouched.' });
  durableNew(path.join(directory, 'plan.json'), plan);
  const records = [];
  let stopReason = null;
  for (const task of plan.tasks) {
    const attempt = records.length + 1;
    if (attempt > 3 || attempt > plan.maxAuthorizedCalls) throw fail('CALL_LIMIT');
    durableNew(path.join(directory, `attempt-${attempt}.reserved.json`), {
      caseId: task.caseId, requestHash: task.requestHash, reserveCny: task.reserveCny,
    });
    let raw;
    try { raw = await transport(task.payload, key); }
    catch { raw = { status: 'incomplete', error: 'TRANSPORT_FAILED', answer: '', usage: null }; }
    const secretEchoed = JSON.stringify(raw).includes(key);
    const clean = JSON.parse(serialize(raw));
    let quoteCheck = 'passed';
    try { verifyDirectQuotes(clean.answer, task.material); } catch { quoteCheck = 'failed'; }
    const record = { caseId: task.caseId, turn: task.turn, ...clean,
      calculatedPeakCostCny: usageCost(clean.usage), actualAccountDebitCny: null,
      explicitQuoteCheck: quoteCheck, secretRedacted: secretEchoed };
    durableNew(path.join(directory, `response-${attempt}.json`), record);
    records.push(record);
    if (secretEchoed) stopReason = 'SECRET_ECHO_REDACTED';
    else if (clean.status !== 'completed') stopReason = 'UPSTREAM_NOT_COMPLETED';
    else if (record.calculatedPeakCostCny == null) stopReason = 'UNKNOWN_USAGE';
    else if (clean.unexpectedReasoning) stopReason = 'UNEXPECTED_THINKING';
    else if (clean.returnedModel !== 'deepseek-flash') stopReason = 'UNEXPECTED_MODEL';
    else if (clean.usage.prompt_tokens > task.inputReservation || clean.usage.completion_tokens > task.payload.max_tokens
      || record.calculatedPeakCostCny > task.reserveCny) stopReason = 'RESERVATION_MISMATCH';
    if (stopReason) break;
  }
  const summary = { callsAttempted: records.length, completed: records.filter(r => r.status === 'completed').length,
    stopReason, noRetries: true, reservedCny: plan.reservedCny,
    calculatedPeakTotalCny: records.every(r => r.calculatedPeakCostCny != null)
      ? records.reduce((sum, r) => sum + r.calculatedPeakCostCny, 0) : null,
    actualAccountDebitCny: null };
  durableNew(path.join(directory, 'responses.json'), records);
  durableNew(path.join(directory, 'summary.json'), summary);
  const blind = ['# v2 / v3 匿名复核', '', 'A/B 每组随机；含历史 v2 与本轮 v3，不是同时采样。评分后查看 unblinding.json。',
    '全部为合成材料。纠错组使用固定错误 AI 历史。五维各 0–4 分，按原 rubric 评估；本轮不验证14轮。', ''];
  const mapping = [];
  for (const task of plan.tasks) {
    blind.push(`## ${task.caseId} / ${task.turn}`, '', `原文：${task.body.selectedText}`, '额外前后文：无',
      `问题：${task.body.message || '按指定模式解读原文'}`, `模式：${task.body.mode}`);
    if (task.body.initialAnswer) blind.push(`固定错误历史：${task.body.initialAnswer}`);
    const pair = [{ version: 'v2', row: task.baseline }, { version: 'v3', row: records.find(r => r.caseId === task.caseId) }];
    if (crypto.randomInt(2)) pair.reverse();
    pair.forEach((item, index) => {
      const label = index ? 'B' : 'A';
      mapping.push({ caseId: task.caseId, label, version: item.version });
      blind.push('', `### ${label}`, '', item.row?.answer || '（未收到回答）', '',
        `完成状态：${item.row?.status || 'not_attempted'}`, '', '正确性 __；证据 __；模式 __；可读性 __；边界 __；关键错误 ____', '');
    });
  }
  fs.writeFileSync(path.join(directory, 'blind-review.md'), blind.join('\n').split(key).join('[REDACTED_SECRET]'), { flag: 'wx' });
  durableNew(path.join(directory, 'unblinding.json'), mapping);
  return summary;
}

module.exports = { makePlan, runBatch, OUTPUT };
if (require.main === module) {
  (async () => {
    const plan = makePlan();
    if (process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === '--plan')) {
      console.log(JSON.stringify({ plannedCalls: plan.plannedCalls, reservedCny: plan.reservedCny,
        budgetCny: plan.budgetCny, promptVersion: plan.promptVersion, noRetries: true }, null, 2));
      return;
    }
    if (process.argv.length !== 3 || process.argv[2] !== '--execute') throw fail('INVALID_ARGUMENTS');
    const result = await runBatch(plan, process.env.DEEPSEEK_API_KEY);
    console.log(JSON.stringify(result, null, 2));
    if (result.stopReason) process.exitCode = 2;
  })().catch(error => {
    console.error(JSON.stringify({ error: /^[A-Z_]+$/.test(error.code || '') ? error.code : 'RUNNER_ERROR', noRetry: true }));
    process.exitCode = 1;
  });
}
