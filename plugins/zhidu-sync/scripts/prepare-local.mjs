// Explicit, disposable local fixtures only. Not imported by the plugin bundle.
const origin = 'http://127.0.0.1:3002';
const email = 'zhidu-plugin-demo@example.invalid';
const password = 'Local-plugin-demo-only-2026!';
const mode = process.argv[2] || 'init';
if (!['init', 'update', 'delete'].includes(mode)) throw new Error('Use init, update or delete');
async function main() {
  const health = await (await fetch(origin + '/api/health')).json();
  if (health.production !== false || health.environment !== 'obsidian-local-test'
      || health.database !== 'zhidu_obsidian_phase1_test') throw new Error('Refusing a non-isolated backend');
  const request = (path, method, body, token) => fetch(origin + path, { method,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
  const registration = await request('/api/auth/register', 'POST', { email, password });
  if (registration.status !== 409 && !registration.ok) throw new Error('Local fixture registration failed');
  const login = await request('/api/integrations/obsidian/login', 'POST', { email, password });
  if (!login.ok) throw new Error('Local fixture login failed; no records changed');
  const token = (await login.json()).token;
  for (const type of ['highlight', 'thought', 'ai_explanation', 'ai_question']) {
    const revision = { writer_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', client_revision: mode === 'init' ? 1 : mode === 'update' ? 2 : 3 };
    const payload = { ...revision, source: type, book_id: 'zhidu-plugin-demo-book', book_title: '知读同步验收（示例）',
      chapter_index: 2, chapter_title: '示例章节', original_text: '这是一条合成的测试摘录，不是书籍原文。',
      user_input: mode === 'update' ? '第二次更新的测试想法。' : '第一次创建的测试想法。',
      ai_explanation: type.startsWith('ai_') ? '这是一条预置的测试解读，不是插件新生成的内容。' : null,
      auto_tags: ['测试', '阅读'] };
    const response = await request(`/api/entries/client/zhidu-plugin-demo-${type}`, mode === 'delete' ? 'DELETE' : 'PUT', mode === 'delete' ? revision : payload, token);
    if (!response.ok) throw new Error(`Fixture ${mode} failed: HTTP ${response.status}`);
  }
  console.log(`Isolated local demo ${mode} completed. No credentials or reading text printed.`);
}
main().catch(() => { console.error('Local fixture preparation failed. Check the isolated server and the documented test account.'); process.exitCode = 1; });
