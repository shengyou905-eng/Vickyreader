const assert = require('node:assert/strict');
const express = require('express');
const legalRoutes = require('./legal.routes');

async function main() {
  const app = express();
  app.use('/legal', legalRoutes);
  const server = app.listen(0, '127.0.0.1');

  try {
    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
    const { port } = server.address();
    const checks = [
      ['/legal/privacy', '隐私政策'],
      ['/legal/privacy/en', 'Privacy Policy'],
      ['/legal/data-collection', '个人信息收集'],
      ['/legal/third-parties', '第三方'],
      ['/legal/ai', 'DeepSeek'],
      ['/legal/account-deletion', '注销'],
    ];

    for (const [path, expected] of checks) {
      const response = await fetch(`http://127.0.0.1:${port}${path}`);
      const html = await response.text();
      assert.equal(response.status, 200, `${path} should be public`);
      assert.match(response.headers.get('content-type') || '', /text\/html/);
      assert.ok(html.includes(expected), `${path} should contain ${expected}`);
      assert.ok(response.headers.get('content-security-policy'));
    }
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

main()
  .then(() => console.log('Legal routes smoke test passed.'))
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
