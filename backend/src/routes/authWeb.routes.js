const express = require('express');

const router = express.Router();

router.get('/reset-password', (_req, res) => {
  res
    .status(200)
    .set({
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'Content-Security-Policy':
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    })
    .send(`<!doctype html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>重置知读密码</title>
<style>
body{margin:0;background:#f5f3ee;color:#20211f;font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:520px;margin:12vh auto;padding:32px 24px;text-align:center}
a{display:inline-block;margin-top:18px;padding:12px 22px;border-radius:12px;background:#75658f;color:#fff;text-decoration:none}
p{color:#72746f}
</style></head>
<body><main><h1>在知读中设置新密码</h1><p>重置链接将在 30 分钟后失效，并且只能使用一次。</p><a id="open" href="#">打开知读</a><p>若没有自动打开，请确认已安装最新版知读后再次点击。</p></main>
<script>
const token=new URLSearchParams(location.hash.slice(1)).get('token')||'';
const target='readu://reset-password?token='+encodeURIComponent(token);
const link=document.getElementById('open');link.href=target;
if(token){setTimeout(()=>{location.href=target},250)}
</script></body></html>`);
});

module.exports = router;
