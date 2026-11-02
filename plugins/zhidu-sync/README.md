# Zhidu Sync

Sync your Zhidu reading highlights, notes, and reading progress to your Obsidian vault.

这是第二阶段的手动同步测试版 `0.1.0`，不是已发布的 Community Plugin。
要求 Obsidian **1.11.4+**，使用官方 SecretStorage；不要求 MCP 或任何 LLM Key。
本阶段不修改后端，不部署生产，不做自动后台同步或双向写回。

## 构建

Node.js 22+；在本目录执行：

```powershell
npm ci
npm run typecheck
npm test
npm run package:test
```

默认测试包编译到 `http://127.0.0.1:3002`，只适合与本地测试后端同一电脑的
Obsidian 桌面客户端。产物在 `dist/zhidu-sync/`，包含 `main.js`、`manifest.json`、
`styles.css`、说明及许可证，不包含任何用户状态或 secret。

对已确认的非生产 HTTPS 环境构建（这里只展示占位符，不会创建/部署后端）：

```powershell
$env:ZHIDU_API_ORIGIN='https://YOUR-CONFIRMED-TEST-BACKEND'
npm run package:test
Remove-Item Env:ZHIDU_API_ORIGIN
```

`npm run build` 构建普通包，默认目标为正式域名；目前不能因此假定生产已上线
migration 007/授权接口。此次交付使用测试包，没有访问/部署生产。
API origin 是编译期公共配置，不是 secret；不在普通用户设置中提供任意服务器输入。

## 放入测试 Vault

1. 使用单独的空测试 Vault，先备份，不要直接装进主要笔记库。
2. 将 `dist/zhidu-sync` 整个目录放到 `<测试 Vault>/.obsidian/plugins/zhidu-sync/`。
   三个必要文件必须直接位于这个目录，不要再嵌套一层 zhidu-sync。
3. 在 Obsidian 设置 → 第三方插件中启用本地插件，重载/重启后启用 **Zhidu Sync**。
4. 不要把已有 `data.json` 或 SecretStorage 内容从其他 Vault/设备复制过来。
   新安装会建立自己的安装 ID；设备之间不要同时同步本插件的 checkpoint 文件。
5. 打开 Zhidu Sync 设置，确认“测试环境”是预期地址。

## 本地后端前提

复用上一阶段 `backend/scripts/obsidian-test-server.js`，它只允许隔离测试库
`zhidu_obsidian_phase1_test`，不运行 migration，不连接生产。
本机健康检查：`http://127.0.0.1:3002/api/health` 应显示：

```json
{"status":"ok","production":false,"environment":"obsidian-local-test","database":"zhidu_obsidian_phase1_test"}
```

该服务器已包含 `obsidian://zhidu-sync` 重定向白名单。
需要重启时，在 backend 目录运行：

```powershell
$env:OBSIDIAN_TEST_DATABASE_URL='postgresql://postgres@127.0.0.1:55440/zhidu_obsidian_phase1_test'
npm run obsidian:test-server
```

不要重新运行会重置数据库的 Phase 1 PostgreSQL fixture suite 来代替启动服务。
测试服务器重启会更换临时签名密钥；旧 App 会话需重新登录，旧游标可能需完整重读。
已有 integration token 是独立 DB 授权，不是该 App JWT。

使用测试环境已有邮箱账号，或只在上述本地后端注册一个测试账号；注册响应不要打印：

```powershell
$body=@{email='obsidian-local@example.invalid';password='Local-test-only-Change-42!'} | ConvertTo-Json
$null=Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:3002/api/auth/register' -ContentType 'application/json' -Body $body
```

以上是合成测试账号，不是正式账号。已有账号不必重复注册。测试库不会有生产阅读记录。

### 一套可以直接观察生成文件的本地示例

在插件工程目录执行 `npm run prepare:local`。它先核对本机健康标识与数据库名，
只在上述隔离数据库建立合成演示账号及四种测试 trace，不更改其他账号/生产数据。
然后在浏览器授权页使用以下**公开的本地测试专用凭据**（绝不要在正式环境使用）：

- 邮箱：`zhidu-plugin-demo@example.invalid`
- 密码：`Local-plugin-demo-only-2026!`

第一次 Sync Now 会生成 `知读同步验收（示例）.md`。在用户区域写点内容后执行
`npm run prepare:local -- update`，再 Sync Now 验证增量更新。最后可执行
`npm run prepare:local -- delete` 再同步，验证只有远端示例 trace 被移除，用户笔记仍在。
这三个步骤按 init → update → delete 运行；固定 revision 的旧步骤不会复活新删除。
脚本不是插件功能，不会随安装/启动执行，不进入 main.js，也不会打印 JWT。

## Connect → Sync Now 人工验收

1. 在插件设置点击 **Connect to Zhidu**。不应出现复制 Cookie/JWT/Key 的输入框。
2. 系统浏览器打开知读授权页；登录同一测试后端的邮箱账号，检查只读范围，点击允许。
3. 允许浏览器打开 Obsidian，回到**发起授权的同一个 Vault**。
   应显示 `Connected to Zhidu`。错误 Vault/state 会被拒绝，不会替换现有连接。
4. 点击 **Sync Now**。首次同步全部分页后，查看 `Zhidu/Books/` 和最后同步时间。
   测试账号没有书籍/痕迹时，空结果是正常结果，不会伪造示例书籍。
5. 在同一测试账号创建真实测试阅读数据后再次同步；或运行下方隔离 HTTP 集成测试验证完整链路。
   各本书有独立 Markdown，包含进度、划线、想法、小U解读/提问和 auto_tags。
6. 在 `## 我的笔记` 下写一段文字，再修改云端测试 trace 后同步：用户文字必须逐字保留。
7. 将书籍文件重命名、移动到 Vault 中另一个目录；再同步，原文件应更新，不新建重复文件。
8. 再次 Sync Now，无变化不新增重复记录。修改/删除一个远端 trace 后再同步：仅受管区域更新。
9. 移出书架但保留历史：痕迹仍在。永久删除目标 trace 后：受管区域移除对应内容，用户笔记和文件仍在。
10. 人工修改 managed region 后同步：必须暂停，保持内容及 cursor，不强行覆盖。
    先把修改备份到受管区外，再从 Obsidian 文件恢复/备份恢复原受管内容后重试。
11. 复制同一连接同一 book ID 的文件后同步：必须报重复身份。移走副本后可重试。
12. 删除本地书籍 note 后同步：不自动重建；恢复带身份字段的文件后重试。
13. 临时切断网络/模拟文件写入失败后同步：游标不越过失败批次；重启后手动同步可重放计划。
14. 点击 **Disconnect**：服务器撤销授权，SecretStorage 中令牌值清空，Markdown 不删除。
    断网时不能假称已撤销，请联网后重试。
15. 令牌过期或外部撤销后 Sync Now：提示重新连接，不能悄悄读取旧缓存并假称成功。

PKCE 回调必须由真实 Obsidian 处理。当前自动化验证覆盖插件核心和宿主接口 mock，
**没有把 mock 声称为桌面/iOS 真机验收**。仍需按本清单验证 OS URI 跳转和 SecretStorage 持久性。
多个 Vault 同时开启插件时，Obsidian 可能把回调交给另一个活动 Vault；state 会拒绝错配。
验收时先只打开目标 Vault。

## 文件、受管区与身份

默认 `Zhidu/Books/<标题>.md`；同名时加稳定短 hash，不覆盖已有文件。
identity 是 `zhidu_connection_id + zhidu_book_id`，不是路径或标题。
每次手动同步扫描 Vault 的 Markdown frontmatter，用于跟踪移动/重命名及重复 ID。

首次创建写入最小 frontmatter 和标题；以后**不改 frontmatter、H1 或受管区外字节**。
因此 title/author frontmatter 是首次导入值；当前云端元数据呈现在 managed region 中。
作者/标题缺失写 null，不补猜。Markdown 示例见 `examples/book.md`。

```markdown
<!-- zhidu:managed:start -->
## 来自知读
这里是知读维护的阅读记录。
<!-- zhidu:managed:end -->

## 我的笔记
这里由用户维护。
```

记录按 subtype 分组，提供稳定块引用、章节和时间。文本经转义，防止原文插入 HTML、
链接/嵌入或伪造 managed marker；不把云端正文当模板执行。标签保留原 auto_tags 文本，
本版不擅自改写为全局 Vault 标签分类。

写入前核对上次区域 SHA-256，使用 `Vault.process()` 在回调内再次校验当前内容，
只替换受管区域。重复标记、缺失标记、身份字段损坏、重复 ID 或用户修改区域均暂停。
没有强制覆盖或整文件重建入口，也不会删除 Markdown。

## 同步恢复规则

- 读取真实 API `next_cursor`，不解析/伪造服务端游标；默认一批 50 条。
- 本地 cache 按 canonical entity ID 存状态，增量 upsert/delete 幂等处理。
- 每批先持久化 journal，里面保存计划及下一个投影；写完所有文件后才提交 cursor。
- 写完文件但保存 cursor 失败：下次先重放 journal，接受旧 hash 或精确的新内容，不重复创建。
- 重启不会自动上传/同步。用户再次 Sync Now 时先向服务端验证授权，再恢复 journal。
- 410 过期/游标无效：运行命令 **Zhidu Sync: 重新读取完整数据**。
  完整快照最后一页才移除本地 cache 中不再存在的实体；只清理受管内容，不删除用户文件。
- 仍有未完成文件 journal 时禁止丢弃它进行重置，需先恢复冲突文件并完成该批。
- 插件停用会设置 cancellation；已开始的 Vault 写入不可物理撤回，但不会提前 ACK。
- `saveData` 使用宿主存储，不能宣称跨文件或硬盘断电绝对原子；若状态文件损坏，加载失败关闭，
  不重置或继续覆盖。请保留测试 Vault 备份。不要两个进程/设备同时写同一插件状态。

## 当前边界

- 只手动同步；无定时器、启动同步、统计、模板市场、写回或 Agent。
- 后端现有令牌 24 小时到期，无 refresh token；需要 Disconnect 后重新 Connect。
- 当前 status/token 不提供稳定账号标识。为防止换号混入别人笔记，**每次授权建立新连接空间**。
  旧笔记保留，重新授权即使是同一账号也不自动接管它们，可能产生带后缀的新文件。
  这是明确的测试版限制；正常同一连接内的重复同步/重命名不会重复建文件。
- 邮箱密码授权支持；Apple-only 浏览器登录尚未由后端提供。
- 本地删 note 不自动重建，无 ignore/resync 单书 UI；受管区冲突需要手工恢复。
- 历史书籍作者可能为 null。远端已归档书籍的最后 trace 删除不一定带 book tombstone，
  以 trace 删除为准，不推断要删除整篇用户笔记。
- 每次手动同步有 Vault 扫描，超大 Vault 尚未专项性能验收。服务端快照 30 分钟 TTL、
  导出量/限流约束仍有效；大批量受限时停止并保留已提交进度。
- 运行时代码只用 `requestUrl`、Vault API、Web Crypto 和 SecretStorage；无 Node fs/Electron。
  manifest 非 desktop-only，但 iOS/Android 尚需真机验证；手机不可用 127.0.0.1 访问开发机。

## 测试与工程

```powershell
npm run typecheck
npm test
# 可选：当前本机隔离测试 backend 必须已运行，健康标识必须匹配
$env:ZHIDU_TEST_ORIGIN='http://127.0.0.1:3002'
npm test
Remove-Item Env:ZHIDU_TEST_ORIGIN
```

HTTP 集成测试只允许上述地址及 `zhidu_obsidian_phase1_test` 标识，创建独立合成测试账号
和阅读记录，走现有 API 的 PKCE、快照、修改、删除、撤销，不打印凭证/正文、不运行迁移，
不删除已有测试用户或其他数据。其 Vault/SecretStorage 适配器在测试中使用内存实现。

新增工程文件：manifest、versions、package/lock、tsconfig、esbuild 配置、styles、许可证、
隐私说明、README；`src/main.ts`、`api.ts`、`auth.ts`、`crypto.ts`、`errors.ts`、`model.ts`、
`markdown.ts`、`sync.ts`；`tests/`、`scripts/`、`examples/`。本阶段没有修改 backend 文件。

参考官方 API 文档：[SecretStorage](https://docs.obsidian.md/plugins/guides/secret-storage)、
[Obsidian API](https://github.com/obsidianmd/obsidian-api)、[Vault API](https://docs.obsidian.md/Plugins/Vault)。
微信读书插件仅作为产品/工程参考，没有复用其源文件或 Cookie 授权方式。
打包时附带运行时依赖 Zod 的原许可证。本项目不使用 Obsidian 商标图标，也不暗示官方合作。
