/* Browser session credentials exist only in this page's memory. */
(() => {
  const root = '/api/integrations/obsidian';
  const $ = id => document.getElementById(id);
  const parameters = Object.fromEntries(new URLSearchParams(location.search));
  let sessionToken = null;
  let busy = false;
  async function post(endpoint, body, token) {
    const response = await fetch(`${root}/${endpoint}`, {
      method: 'POST', credentials: 'omit', cache: 'no-store',
      headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: JSON.stringify(body),
    });
    if (!response.ok) throw new Error(response.status === 401
      ? '登录未通过，请检查账号和密码，或重新登录。'
      : response.status === 429 ? '操作过于频繁，请稍后再试。' : '暂时无法完成授权，请稍后重试。');
    return response.json();
  }
  async function run(action) {
    if (busy) return;
    busy = true;
    document.querySelectorAll('button').forEach(button => { button.disabled = true; });
    $('message').textContent = '';
    try { await action(); }
    catch (error) { $('message').textContent = error instanceof TypeError ? '无法连接知读，请检查网络后重试。' : error.message; }
    finally {
      busy = false;
      document.querySelectorAll('button').forEach(button => { button.disabled = false; });
    }
  }
  $('login').addEventListener('submit', event => {
    event.preventDefault();
    run(async () => {
      const result = await post('login', { email: $('email').value, password: $('password').value });
      $('password').value = '';
      sessionToken = result.token;
      $('account').textContent = `已登录：${result.user.email}`;
      $('login').hidden = true;
      $('consent').hidden = false;
    });
  });
  for (const [id, allow] of [['allow', true], ['deny', false]]) {
    $(id).addEventListener('click', () => run(async () => {
      const result = await post('authorize', { ...parameters, allow }, sessionToken);
      sessionToken = null;
      location.replace(result.redirect_uri);
    }));
  }
  window.addEventListener('pagehide', () => { sessionToken = null; });
})();
