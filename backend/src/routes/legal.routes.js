const express = require('express');

const router = express.Router();

const operatorName =
  process.env.LEGAL_OPERATOR_NAME ||
  '【上架前请配置为 Apple 开发者账号登记的法定姓名或主体全称】';
const privacyEmail =
  process.env.PRIVACY_EMAIL || process.env.SUPPORT_EMAIL || '2931952407@qq.com';
const effectiveDate = process.env.LEGAL_EFFECTIVE_DATE || '2026-08-10';
const policyVersion = process.env.LEGAL_POLICY_VERSION || '1.0';

const links = [
  ['/legal/privacy', '隐私政策'],
  ['/legal/data-collection', '个人信息清单'],
  ['/legal/third-parties', '第三方清单'],
  ['/legal/ai', 'AI 数据说明'],
  ['/legal/account-deletion', '账号与数据删除'],
];

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function page({ title, description, body, lang = 'zh-CN' }) {
  const nav = links
    .map(([href, label]) => `<a href="${href}">${label}</a>`)
    .join('');
  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="${escapeHtml(description)}">
  <title>${escapeHtml(title)} · 知读 ReadU</title>
  <style>
    :root { color-scheme: light; --paper:#f5f3ee; --surface:#fbfaf6; --ink:#20211f; --muted:#6f716c; --line:#dedbd3; --accent:#75658f; --soft:#e8e1ef; }
    * { box-sizing: border-box; }
    body { margin:0; color:var(--ink); background:var(--paper); font-family:-apple-system,BlinkMacSystemFont,"PingFang SC","Noto Sans CJK SC","Microsoft YaHei",sans-serif; line-height:1.75; }
    header { border-bottom:1px solid var(--line); background:rgba(251,250,246,.94); }
    .header-inner, main, footer { width:min(880px,calc(100% - 40px)); margin:0 auto; }
    .header-inner { padding:28px 0 22px; }
    .brand { font-size:14px; color:var(--accent); font-weight:700; letter-spacing:.04em; }
    h1 { margin:8px 0 4px; font-size:clamp(28px,5vw,42px); line-height:1.25; }
    .meta, .lead, footer { color:var(--muted); }
    nav { display:flex; gap:8px; flex-wrap:wrap; margin-top:18px; }
    nav a { color:var(--ink); text-decoration:none; padding:7px 11px; border:1px solid var(--line); border-radius:10px; background:var(--surface); font-size:13px; }
    main { padding:40px 0 64px; }
    section { margin:0 0 38px; }
    h2 { margin:0 0 12px; font-size:21px; line-height:1.4; }
    h3 { margin:22px 0 8px; font-size:16px; }
    p { margin:8px 0; }
    ul { margin:10px 0; padding-left:1.3em; }
    li { margin:5px 0; }
    .notice { padding:16px 18px; border:1px solid #d8cfe3; border-radius:14px; background:var(--soft); }
    .plain { padding:18px 20px; border:1px solid var(--line); border-radius:16px; background:var(--surface); }
    table { width:100%; border-collapse:collapse; background:var(--surface); font-size:14px; }
    th, td { padding:12px 13px; border:1px solid var(--line); text-align:left; vertical-align:top; }
    th { background:#efeee8; }
    a { color:var(--accent); }
    code { padding:2px 5px; border-radius:5px; background:#ece9e2; }
    footer { padding:24px 0 42px; border-top:1px solid var(--line); font-size:13px; }
    @media (max-width:640px) { .table-wrap { overflow-x:auto; } table { min-width:680px; } main { padding-top:28px; } }
  </style>
</head>
<body>
  <header><div class="header-inner">
    <div class="brand">知读 ReadU</div>
    <h1>${escapeHtml(title)}</h1>
    <div class="meta">版本 ${escapeHtml(policyVersion)} · 生效及更新日期 ${escapeHtml(effectiveDate)}</div>
    <nav>${nav}<a href="/legal/privacy/en">English</a></nav>
  </div></header>
  <main>${body}</main>
  <footer>个人信息处理者：${escapeHtml(operatorName)}<br>隐私与数据请求：<a href="mailto:${escapeHtml(privacyEmail)}">${escapeHtml(privacyEmail)}</a></footer>
</body>
</html>`;
}

function sendLegalPage(res, options) {
  res.set({
    'Cache-Control': 'public, max-age=300',
    'Content-Security-Policy':
      "default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; connect-src 'none'; font-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
  });
  res.type('html').send(page(options));
}

function policyMeta() {
  return `<div class="notice"><strong>请先知道：</strong>知读不接入广告，不进行跨 App 跟踪，不出售个人信息。用户导入的 EPUB、TXT、PDF 原始文件默认只保存在其设备中。登录后，书籍元信息、阅读进度和用户创建的阅读痕迹会与知读云端同步；用户主动使用小U时，完成请求所需的数据会发送给 DeepSeek。</div>`;
}

router.get('/', (_req, res) => res.redirect(302, '/legal/privacy'));

router.get('/privacy', (_req, res) => {
  const body = `${policyMeta()}
  <section><h2>一、适用范围与处理者</h2>
    <p>本政策适用于“知读 ReadU”移动应用及与其配套的账号、同步、小U和明台服务。</p>
    <p>个人信息处理者为：<strong>${escapeHtml(operatorName)}</strong>。如对个人信息处理有疑问、投诉或权利请求，请联系 <a href="mailto:${escapeHtml(privacyEmail)}">${escapeHtml(privacyEmail)}</a>。</p>
  </section>
  <section><h2>二、我们处理哪些信息</h2>
    <h3>1. 仅在设备本地处理</h3>
    <ul>
      <li>用户通过系统文件选择器导入的 EPUB、TXT、PDF 原始文件及为阅读而解析的章节内容。</li>
      <li>阅读字体、字号、行距、页边距、翻页方式、纸张主题和首次使用引导状态。</li>
      <li>未登录状态下产生且尚未同步的数据。</li>
    </ul>
    <p>我们不会因为导入书籍而自动上传整本电子书。请用户确保其有权持有和阅读所导入的文件。</p>
    <h3>2. 注册、登录与云同步</h3>
    <p>注册和登录时，我们处理邮箱地址、经安全哈希后的密码、账号标识和登录令牌。登录后，为提供跨设备留存和小U功能，我们会同步书名、作者等书籍元信息，以及阅读进度、书签、划线、想法、小U解读、小U提问、随心记和小U对话历史。原始电子书文件不随此同步上传。</p>
    <h3>3. 个人资料与头像</h3>
    <p>用户主动编辑阅读档案时，我们处理昵称、头像和个人介绍。选择头像需要调用系统相册选择能力；只有用户选中的图片会上传。</p>
    <h3>4. 明台公开内容</h3>
    <p>明台内容默认不公开。用户明确确认发布后，相关昵称、头像、书籍信息、必要短摘录、原创想法、帖子、评论、收藏、回应、关注关系和发布时间可能向其他用户展示。用户可删除自己发布的内容，并可设置是否展示阅读状态、进度及是否出现在同书读者中。</p>
    <h3>5. 设备与安全日志</h3>
    <p>用户访问服务时，服务器可能自动接收 IP 地址、请求时间、App 或系统版本、网络请求状态等必要日志，用于保障安全、排查故障和防止滥用。我们不将这些日志用于广告或跨 App 跟踪。</p>
  </section>
  <section><h2>三、小U与第三方 AI</h2>
    <p>小U由知读服务器调用 DeepSeek 提供。只有在用户主动使用小U并完成首次授权后才会调用。</p>
    <ul>
      <li>“小U解读”可能发送选中文字、所在段落、前后文、书名、作者、章节及相关追问。</li>
      <li>“问小U”可能按照用户选择的范围发送当前选区、当前页或当前章节，以及对话历史。</li>
      <li>小U全局对话和“小U问我”可能使用近期划线、阅读想法、小U解读和明台公开痕迹。随心记不会进入小U上下文。</li>
    </ul>
    <p>我们不会将用户导入的整本电子书文件发送给 DeepSeek。AI 输出可能存在错误，请结合原文判断，不能替代医疗、法律、金融等专业意见。用户可在“设置 → 隐私与安全 → 小U与第三方 AI”撤回授权；撤回后基础阅读功能仍可使用。</p>
    <p>DeepSeek 的公开政策说明，其数据可能在中华人民共和国境内处理和存储，并可能用于服务改进或模型优化。具体规则、保存期限和权利方式以 DeepSeek 适用于开放平台服务的最新条款为准。详见<a href="/legal/ai">《AI 功能与数据处理说明》</a>。</p>
  </section>
  <section><h2>四、处理目的与法律依据</h2>
    <ul>
      <li>履行用户请求和提供账号、阅读、同步、小U及明台功能。</li>
      <li>基于用户主动同意处理可选的 AI 数据及公开内容。</li>
      <li>保障服务安全、预防欺诈、处理举报并遵守适用法律义务。</li>
      <li>在不识别特定个人的前提下改善稳定性和阅读体验。</li>
    </ul>
    <p>对于非必要处理，用户有权拒绝或撤回同意。拒绝使用小U或明台不会影响本地基础阅读。</p>
  </section>
  <section><h2>五、共享、委托处理与公开披露</h2>
    <p>我们不会出售个人信息。我们仅在提供服务所必需的范围内委托云服务器和 AI 服务商处理数据，或在用户主动公开、法律要求、保护用户与服务安全的情况下披露。服务商详情见<a href="/legal/third-parties">《第三方信息共享清单》</a>。</p>
  </section>
  <section><h2>六、保存期限</h2>
    <ul>
      <li>账号、资料和云端阅读内容：保存至用户删除相应内容或注销账号。</li>
      <li>公开内容：保存至用户删除内容或注销账号；因举报、争议或法律义务需要保留的除外。</li>
      <li>服务器安全与故障日志：仅在排查安全和稳定问题所必要的最短期间保存。</li>
      <li>数据库备份：当前默认轮换期限为 14 天。主数据库删除后，残留备份将在轮换周期内覆盖清除。</li>
      <li>DeepSeek 处理的数据：依其适用于开放平台的政策和法律要求保存。</li>
    </ul>
  </section>
  <section><h2>七、用户权利</h2>
    <p>用户可以访问、更正或删除资料、划线、想法、随心记、小U对话和公开内容；撤回 AI 授权；调整明台公开范围；举报或拉黑其他用户；退出登录；以及在 App 内永久注销账号。</p>
    <p>需要复制、导出、更正或删除无法在 App 内自行处理的数据时，可通过隐私邮箱提出请求。我们可能要求完成必要的身份验证。</p>
  </section>
  <section><h2>八、账号注销</h2>
    <p>可在“设置 → 账户 → 注销账号”发起注销。注销将删除账号、云端阅读记录、随心记、小U对话、个人资料以及用户公开发布的帖子和评论。设备中的本地电子书不会因此删除。详细规则见<a href="/legal/account-deletion">《账号与数据删除说明》</a>。</p>
  </section>
  <section><h2>九、安全措施</h2>
    <p>我们使用 HTTPS、密码哈希、具有有效期且可撤销的登录令牌、访问控制、用户隔离、数据库备份和最小权限等措施保护数据。互联网传输不存在绝对安全，我们会在发现安全事件后采取补救措施，并依法通知受影响用户及主管部门。</p>
  </section>
  <section><h2>十、未成年人</h2>
    <p>知读不面向未满 14 周岁的儿童提供注册和公开社区服务。若发现未经适当监护人同意处理了儿童个人信息，我们将核实并依法删除。未成年人不应向小U或明台提交敏感个人信息。</p>
  </section>
  <section><h2>十一、跨境与境外用户</h2>
    <p>知读服务器及 DeepSeek 可能在中华人民共和国境内处理数据。向境外用户提供服务时，我们将根据适用法律采取必要的告知、同意和传输保护措施。若特定地区的合规条件尚未满足，我们可能暂不在该地区提供部分服务。</p>
  </section>
  <section><h2>十二、政策更新与联系</h2>
    <p>功能或处理规则发生重要变化时，我们会更新版本和日期，并通过 App 内提示等适当方式告知。重大变化需要重新取得同意的，我们会依法再次征求同意。</p>
    <p>隐私、举报、版权或数据权利请求：<a href="mailto:${escapeHtml(privacyEmail)}">${escapeHtml(privacyEmail)}</a>。</p>
  </section>`;
  sendLegalPage(res, {
    title: '隐私政策',
    description: '知读 ReadU 隐私政策',
    body,
  });
});

router.get('/privacy/en', (_req, res) => {
  const body = `<div class="notice"><strong>At a glance:</strong> ReadU does not sell personal data, serve advertising, or track users across apps. Imported EPUB, TXT and PDF files remain on the device by default. Account-linked reading data is synced after sign-in. Data needed for AI requests is sent to DeepSeek only after the user actively invokes Xiaou and provides consent.</div>
  <section><h2>1. Scope and controller</h2><p>This policy applies to the ReadU mobile app and its account, cloud sync, Xiaou AI, and Mingtai community services.</p><p>Controller: <strong>${escapeHtml(operatorName)}</strong>. Privacy requests: <a href="mailto:${escapeHtml(privacyEmail)}">${escapeHtml(privacyEmail)}</a>.</p></section>
  <section><h2>2. Data we process</h2><ul><li>Account data: email address, hashed password, user ID and revocable authentication token.</li><li>Profile data: nickname, avatar and bio provided by the user.</li><li>Reading data: book metadata, progress, bookmarks, highlights, thoughts, AI explanations and questions.</li><li>Private writing and conversations: free notes and Xiaou conversation history. Free notes never enter Xiaou's AI context.</li><li>Public community data: content the user explicitly publishes, comments, follows, favorites, responses, reports and privacy preferences.</li><li>Security data: IP address, request time, app/system version and request status where necessary for security and troubleshooting.</li></ul><p>Imported ebook files and locally parsed chapter files are not uploaded merely because the user imports a book.</p></section>
  <section><h2>3. AI processing</h2><p>After explicit consent, ReadU sends the minimum context needed for the feature to DeepSeek. Depending on the feature, this may include selected text, surrounding text, the current page or chapter, questions, recent reading traces, chat history, and free notes explicitly authorized for Xiaou. Full imported ebook files are not sent.</p><p>DeepSeek states that data may be processed and stored in the People's Republic of China and may be used to improve its services or models. Retention and user rights are governed by the current terms applicable to its Open Platform. Users can withdraw AI consent in ReadU settings without losing basic reading features.</p></section>
  <section><h2>4. Cloud sync and public sharing</h2><p>After sign-in, account-linked reading data and user-created content are synced to provide persistence and cross-device access. Mingtai sharing is private by default; content becomes public only after the user confirms publication.</p></section>
  <section><h2>5. Retention and deletion</h2><p>Account-linked data is retained until the user deletes the content or account, unless a longer period is required for security, disputes or law. Primary account data is removed when account deletion completes. Rotating database backups are retained for up to 14 days. DeepSeek retains data under its applicable policies.</p></section>
  <section><h2>6. Your choices</h2><p>Users can edit or delete their content, withdraw AI consent, manage Mingtai visibility, report and block users, sign out, and delete their account in the app. Requests for access, correction, export or deletion can be sent to the privacy email above.</p></section>
  <section><h2>7. Children, security and changes</h2><p>ReadU is not directed to children under 14. We use HTTPS, password hashing, access controls, expiring and revocable tokens, and backups. Material policy changes will be communicated in the app where required.</p></section>`;
  sendLegalPage(res, {
    title: 'Privacy Policy',
    description: 'ReadU Privacy Policy',
    body,
    lang: 'en',
  });
});

router.get('/data-collection', (_req, res) => {
  const body = `<section><h2>个人信息收集与处理清单</h2><div class="table-wrap"><table>
    <thead><tr><th>信息</th><th>来源</th><th>用途</th><th>是否离开设备</th><th>保存</th></tr></thead><tbody>
    <tr><td>邮箱、用户 ID、密码哈希、登录令牌</td><td>注册与登录</td><td>账号识别、鉴权与安全</td><td>是</td><td>账号存续期间；注销后按本政策删除</td></tr>
    <tr><td>昵称、头像、个人介绍</td><td>用户主动填写或选择</td><td>个人阅读档案和明台展示</td><td>是</td><td>删除资料或注销前</td></tr>
    <tr><td>EPUB、TXT、PDF 原始文件与章节正文</td><td>用户导入</td><td>本地阅读</td><td>默认否</td><td>由用户在设备中删除</td></tr>
    <tr><td>书名、作者等书籍元信息</td><td>文件元数据或用户操作</td><td>书架组织、同步与同书关联</td><td>登录后是</td><td>删除书籍关联数据或注销前</td></tr>
    <tr><td>阅读进度、书签、阅读状态</td><td>阅读行为</td><td>恢复位置、跨设备留存</td><td>登录后是</td><td>用户删除或注销前</td></tr>
    <tr><td>划线、想法、小U解读与提问</td><td>用户主动创建</td><td>阅读痕迹、小U回顾与同步</td><td>登录后是</td><td>用户删除或注销前</td></tr>
    <tr><td>随心记</td><td>用户主动创建</td><td>私人记录和云端留存</td><td>登录后是</td><td>用户删除或注销前</td></tr>
    <tr><td>小U对话历史</td><td>用户与 AI 对话</td><td>回看和继续对话</td><td>是</td><td>用户删除对话或注销前</td></tr>
    <tr><td>AI 输入与必要上下文</td><td>用户主动使用小U</td><td>生成 AI 回答</td><td>是，发送给 DeepSeek</td><td>知读按账号规则保存；DeepSeek 按其政策处理</td></tr>
    <tr><td>帖子、短摘录、想法、评论与互动</td><td>用户主动公开</td><td>明台展示与同读交流</td><td>是且可能公开</td><td>删除内容或注销前</td></tr>
    <tr><td>举报、拉黑及治理记录</td><td>用户或管理员操作</td><td>社区安全与争议处理</td><td>是</td><td>处理所必要的最短期间</td></tr>
    <tr><td>IP、请求时间、版本及错误状态</td><td>网络请求自动产生</td><td>安全、反滥用和故障排查</td><td>是</td><td>安全目的所必要的最短期间</td></tr>
  </tbody></table></div></section>
  <section><div class="plain">知读目前不收集广告标识符，不接入第三方广告或跨 App 追踪，也不处理精确位置、通讯录、麦克风或健康数据。用户可能在自由文本中自行输入敏感内容，但知读不会主动要求此类信息。</div></section>`;
  sendLegalPage(res, { title: '个人信息收集清单', description: '知读个人信息收集与处理清单', body });
});

router.get('/third-parties', (_req, res) => {
  const body = `<section><h2>第三方信息共享与委托处理清单</h2><div class="table-wrap"><table>
    <thead><tr><th>服务商</th><th>用途</th><th>涉及信息</th><th>处理地区</th><th>政策</th></tr></thead><tbody>
    <tr><td>腾讯云计算（北京）有限责任公司及其关联服务主体</td><td>提供知读服务器、网络和数据库运行环境</td><td>账号、云端阅读数据、公开内容及必要服务器日志</td><td>中华人民共和国境内</td><td><a href="https://cloud.tencent.com/document/product/301/17345">腾讯云隐私保护声明</a></td></tr>
    <tr><td>杭州深度求索人工智能基础技术研究有限公司（DeepSeek）</td><td>提供小U文本生成与理解能力</td><td>用户主动提交的原文、必要上下文、问题、对话历史、近期阅读痕迹及主动授权内容</td><td>中华人民共和国境内</td><td><a href="https://cdn.deepseek.com/policies/zh-CN/deepseek-privacy-policy.html">DeepSeek 隐私政策</a><br><a href="https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html">开放平台条款</a></td></tr>
    <tr><td>Apple Inc.</td><td>App Store 分发、系统文件与相册选择能力，以及由 Apple 独立提供的系统诊断</td><td>由 Apple 根据用户设备与系统设置独立处理的信息；知读仅接收用户明确选择的文件或头像</td><td>依 Apple 服务安排</td><td><a href="https://www.apple.com/legal/privacy/">Apple 隐私政策</a></td></tr>
  </tbody></table></div></section>
  <section><h2>我们没有接入的服务</h2><p>当前版本未接入广告联盟、跨 App 追踪、第三方用户画像或第三方统计分析 SDK。未来如新增服务，我们会在启用前更新本清单和 App Store 隐私标签，并在法律要求时另行取得同意。</p></section>`;
  sendLegalPage(res, { title: '第三方信息共享清单', description: '知读第三方服务清单', body });
});

router.get('/ai', (_req, res) => {
  const body = `<section><h2>一、何时会调用 DeepSeek</h2><p>已登录用户主动点击小U解读、问小U、小U对话或“小U问我”，并同意第三方 AI 数据处理说明后，知读会调用 DeepSeek。未同意或撤回授权后，上述小U功能停止，书架、阅读、划线和本地笔记仍可使用。</p><p>在旧版明台公开书籍功能仍存在的版本中，用户主动公开一本书或打开缺少读前导览的公开书页时，服务器还可能使用公开书籍的书名、作者、公开资料或正文开头节选生成导览。该处理不等于上传私人书架，且不会因普通本地导入自动触发。</p></section>
  <section><h2>二、不同功能发送什么</h2><ul><li><strong>选区解读：</strong>选中文字、所在段落、最多约 3,000 字前文、4,000 字所在段落和 3,000 字后文，以及书名、作者和章节。</li><li><strong>阅读提问：</strong>按用户选择发送选区、当前页（最多约 7,000 字）或当前章节（最多约 24,000 字），以及问题和近期对话。</li><li><strong>小U全局对话：</strong>可能使用近期阅读痕迹的摘要片段、近期对话及明台公开阅读痕迹。</li></ul><p>以上是当前实现的上限，不代表每次都会发送全部内容。我们不会在 AI 请求中上传整本原始电子书文件，随心记也不会纳入小U上下文。</p></section>
  <section><h2>三、处理方、地区与可能用途</h2><p>DeepSeek 由杭州深度求索人工智能基础技术研究有限公司提供。其公开政策说明，相关数据可能在中华人民共和国境内处理和存储，并可能用于提供、保护、改进服务或优化模型。DeepSeek 未对知读公开承诺统一的固定留存天数，因此知读不会向用户承诺“零留存”“立即删除”或“绝不用于训练”。</p></section>
  <section><h2>四、用户控制</h2><ul><li>首次使用前选择“同意并继续”或“暂不同意”。</li><li>在设置中随时撤回授权。</li><li>删除单条小U解读、阅读提问或完整对话记录。</li><li>随心记是完全私密的写作空间，不会进入小U上下文或明台。</li><li>不要提交身份证、密码、医疗健康、金融账户、精确位置等敏感信息。</li></ul></section>
  <section><h2>五、AI 输出</h2><p>所有 AI 内容均应标识“由 AI 生成，可能存在错误，请结合原文判断”。AI 输出不是事实保证，也不构成医疗、法律、金融或其他专业建议。</p></section>`;
  sendLegalPage(res, { title: 'AI 功能与数据处理说明', description: '知读小U与 DeepSeek 数据处理说明', body });
});

router.get('/account-deletion', (_req, res) => {
  const body = `<section><h2>如何注销</h2><ol><li>登录知读。</li><li>进入“设置”。</li><li>在“账户”区域点击“注销账号”。</li><li>阅读删除范围，输入当前密码并确认永久注销。</li></ol><p>无法登录时，可从注册邮箱向 <a href="mailto:${escapeHtml(privacyEmail)}">${escapeHtml(privacyEmail)}</a> 发送请求。我们会进行必要的身份验证。</p></section>
  <section><h2>注销会删除什么</h2><ul><li>账号、邮箱关联和个人阅读档案；</li><li>云端阅读进度、书签、划线、想法、小U解读与提问；</li><li>云端随心记、随心记授权和小U对话；</li><li>明台帖子、评论、收藏、回应、关注关系和通知；</li><li>头像等账号关联上传文件。</li></ul></section>
  <section><h2>不会自动删除什么</h2><p>用户设备中的本地 EPUB、TXT、PDF 文件及本地数据库不会因为服务器账号注销自动抹除。用户可通过删除书籍、清除 App 数据或卸载 App 处理本地内容。</p></section>
  <section><h2>处理时间与例外</h2><p>正常情况下，确认注销后主数据库中的账号关联数据立即删除。轮换备份可能在最多 14 天内残留，期间只用于灾难恢复并受访问控制，随后自动覆盖清除。因法律义务、反欺诈、未决举报或争议处理确需保留的最少信息，可能在必要期限内限制处理后保存。</p></section>
  <section><div class="notice"><strong>注销不可撤销。</strong>完成后无法恢复原账号和云端内容。Apple 订阅如未来上线，需要用户另行在 Apple 账户中取消；当前版本尚未提供 App 内订阅。</div></section>`;
  sendLegalPage(res, { title: '账号与数据删除说明', description: '知读账号注销和数据删除说明', body });
});

module.exports = router;
