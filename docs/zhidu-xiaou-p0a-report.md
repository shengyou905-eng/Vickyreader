# 知读小U P0a 可靠性修复报告

日期：2026-10-17。状态：代码与本地自动化验证完成，待审查和真机验收；不是生产部署完成。

## 1. 范围与安全边界

本轮仅处理固定阅读证据、重复句定位、章节索引、SSE 完整性、本地创建事务和单进程请求防重。没有新增或执行 migration，没有改 schema，没有访问生产或现有验收数据库，没有调用真实付费模型，没有构建安装包、提交、推送或部署。

工作区原有 Obsidian、Apple IAP、图标等未提交内容均保留，不属于本轮变更。五种免费模式、独立重复解读历史、长原文预览及展开/收起、主要阅读布局保持不变。不改小U发现规则、会员权益、模型选择、Pro、思维导图或深度回望。

测试使用临时目录中的合成 SQLite 数据、内存替身和本机临时 HTTP 服务，不读取或修复用户现有书籍与笔记。

## 2. 已实现

| 目标 | 实现与证据 | 限制 |
| --- | --- | --- |
| 长追问保留首轮依据 | ReadingAiContext 独立保存原文、书籍、章节、作者、模式及首轮回答；每次追问重新携带，不依赖滚动历史。真实 Provider + 临时 SQLite 测试完成 14 轮追问，并验证 14 条 follow-up 归属同一 trace | 证明请求组织与保存关系，不等于真实模型语义质量验收；最近对话仍有窗口预算 |
| 历史详情继续追问 | 使用既有 metadata_json 保存 reading_ai_context，重新打开详情时只读获取；问小U恢复 scope/page/chapter 证据 | 旧数据不存在的信息无法还原；缺失作者不猜测，缺失模式回退 auto |
| 同文独立解读 | 每次主动解读仍生成新 trace UUID；即使命中既有回答缓存，也单独保存本次阅读行为 | 本轮未取消已有回答缓存，不保证每次主动操作都调用模型 |
| 重复句定位 | WebView DOM Range 提供 UTF-16 offset、所选原文和邻接文本；恢复高亮只标记匹配位置，保留跨内联标签内容 | 无可信锚点且多处匹配时不猜第一处；旧错误锚点不回填；尚未在真实 WKWebView 验证 |
| EPUB 索引 | 新解读记录保存 sourceIndex；书签导航先将持久化 sourceIndex 转换到可见章节列表下标 | 旧 list index 仅在 sourceIndex 未命中且范围有效时兼容；两种含义重叠的旧记录无法无损判别 |
| SSE 完整性 | 新后端仅在非空回答、上游 finish_reason=stop、[DONE] 全部满足时发 completed+DONE。length、非法 JSON、EOF、超时、断流均非成功 | 对旧后端保留显式 DONE 兼容；旧后端不提供 finish_reason，无法识别被旧后端掩盖的截断 |
| 取消 | Flutter 取消直接关闭 HTTP 客户端并取消源订阅；不等待下一段内容；取消/错误的未完成解读不保存为成功 trace | 服务端无法可靠区分用户点击取消与网络断开，统一记 interrupted |
| business/trace/queue 原子性 | 新建划线或想法在同一 SQLite transaction 写入 highlights/notes、user_entries、pending queue；任一步失败整体回滚，drain 仍在提交之后 | 不扩展到全部编辑/删除链或 AI conversation 多表事务，不修改 Reliable Upload 协议 |
| 输入约束 | 历史仅允许 user/assistant 文本角色；字段、总请求、历史和最终模型上下文均有长度预算；非法输入在模型调用前拒绝 | 字符预算不是精确 token 计费；未做额度扣减 |

后端使用的终止依据参照 [DeepSeek Chat Completion 官方文档](https://api-docs.deepseek.com/api/create-chat-completion/)；未改变五种模式的免费属性或现有模型路由。

## 3. 单进程请求防重契约

- 标识为认证 user ID + X-Request-ID，不接受客户端指定用户，不按原文内容合并。
- 对路由和排序后的完整请求 JSON 计算 SHA-256。相同 ID、相同内容返回 409 AI_REQUEST_DUPLICATE；内容改变返回 409 AI_REQUEST_CONFLICT。
- 同一进程中的并发重试不再次进入 AI controller；真实 HTTP 测试验证只有一次上游调用。不同用户或新的 request ID 可以独立执行。
- 状态包括 running、completed、failed、timed_out、incomplete、interrupted。失败或取消后在有效期内仍保留防重记录，不自动重新执行，也不重放 SSE 回答。
- 终态保留 10 分钟，上限 1000 条。运行中记录不因 TTL 或容量淘汰；容量满时拒绝新请求（429），避免放行重复请求。过期清理在后续请求到达时进行，不启动清理定时器；空闲时占用仍受上限约束。
- 只保留用户/请求标识、摘要和状态，不缓存原文全文、回答或认证 Token。
- 新客户端每次主动请求生成新 UUID；无自动网络重试。若未来增加自动重试，同一次请求必须复用 ID 和内容。再次主动点击属于新请求。
- 为旧客户端兼容，无 X-Request-ID 的请求可继续调用，但不具备本轮防重保护。
- **不保证跨重启、跨进程、跨实例或 TTL 到期后的幂等性。不是完整 exactly-once 系统。**
- **正式 Pro 额度扣减之前必须独立设计并测试持久化幂等、原子扣减、重放/恢复和跨实例并发；本轮未实现。**

## 4. 修改文件

以下路径相对项目根目录 `C:/Users/29319/Desktop/reader`；不包含工作区原有的其他改动。

### 后端

| 文件 | 内容 |
| --- | --- |
| backend/src/controllers/ai.controller.js | 固定证据、模式延续、输入校验、SSE 终态 |
| backend/src/routes/ai.routes.js | 四个 AI 接口在原认证与同意校验后接入同一个 guard |
| backend/src/services/aiProtocol.js（新增） | 输入预算、角色白名单、证据组织、上游完整性解析 |
| backend/src/middleware/aiRequestGuard.js（新增） | 有界进程内请求防重 |
| backend/src/services/aiProtocol.test.js（新增） | 输入/证据与实际 HTTP 字节流测试 |
| backend/src/middleware/aiRequestGuard.test.js（新增） | 用户隔离、内容一致性、状态、TTL、容量、旧客户端 |
| backend/src/controllers/aiReliability.http.test.js（新增） | controller + loopback 模型服务并发/中断测试 |

### Flutter

| 文件 | 内容 |
| --- | --- |
| lib/models/reading_ai_context.dart（新增） | 不可变首轮证据，旧记录兼容 |
| lib/services/reading_anchor.dart（新增） | offset/邻接证据解析与歧义处理 |
| lib/services/ai_service.dart | 请求 UUID、固定证据、SSE 解析及可取消 HTTP 生命周期 |
| lib/providers/ai_provider.dart | 会话证据保留、独立 trace、取消/失败保存保护 |
| lib/services/book_service.dart | 同事务创建 business/trace/queue，详情本地只读查询 |
| lib/providers/reader_provider.dart | 调用原子创建入口，传递选择锚点和问答证据 |
| lib/services/epub_service.dart | 重复句上下文与 sourceIndex/list index 转换 |
| lib/screens/reader/reader_screen.dart | 捕获 DOM 锚点，传递上下文，保存问答范围 |
| lib/screens/reader/widgets/reader_document_html.dart | DOM Range 锚点与精确高亮还原 |
| lib/screens/reader/widgets/ai_explanation_card.dart | 正确章节索引与锚点传递 |
| lib/screens/reader/widgets/reader_question_sheet.dart | 移除失败/取消的未完成 assistant 消息 |
| lib/screens/xiaou/widgets/xiaou_card.dart | 详情追问恢复固定证据，关闭详情取消请求 |
| lib/screens/bookmarks/bookmarks_screen.dart | 导航时转换持久化章节索引 |
| test/services/ai_protocol_test.dart（新增） | SSE、14 轮上下文、历史详情兼容 |
| test/services/reading_anchor_test.dart（新增） | 重复句、跨标签、过滤章节后的导航 |
| test/services/reading_trace_transaction_test.dart（新增） | 真实临时 SQLite 的提交、三处失败回滚、重复 ID |
| test/providers/ai_reliability_test.dart（新增） | 真实 Provider + 临时 SQLite 的追问、失败、取消 |
| tool/reliable_upload_tests/test/p0a_test.dart（新增） | 复用现有 Windows SQLite harness 运行新增测试 |

本报告为新增文档。不更改数据库版本、migration、服务环境变量、Nginx、DNS 或安装包版本。

## 5. 测试结果

| 检查 | 结果与覆盖边界 |
| --- | --- |
| 后端全部非 PostgreSQL Node tests | **89 passed，0 failed**，含新增 11 项 P0a、现有 auth/MCP/上传/Obsidian/IAP 测试 |
| 最后补充断流状态断言后重跑后端 P0a | **11 passed**；同请求取消后仍为 interrupted，模型调用数不增加 |
| backend npm run check | 通过 |
| Flutter 本次修改的 17 个源文件/测试文件定向 analyze | **No issues found** |
| Windows harness 全套 Flutter tests | **87 passed，2 skipped**；其中 P0a **23 项通过**，其余含 Reliable Upload/诊断/本地痕迹与 UI 回归 |
| ENABLE_LOCAL_SYNC_DIAGNOSTICS=true 诊断模式测试 | **3 passed，1 skipped**；DB/WAL、账号、revision/generation/retry metadata 不变，禁止自动上传 |
| 根目录 flutter test --no-pub --reporter expanded | **74 passed，8 个文件加载失败，exit 1，不能标为全绿** |
| Obsidian 插件 npm test | **20 passed，2 integration skipped**；没有连接人工验收库 |
| Obsidian 插件 npm run typecheck | 通过 |
| 本次已跟踪修改文件 git diff --check | 通过，仅 Git 行尾转换提示 |

各测试集存在重叠，不能把数量相加当作独立覆盖总数。正常模式的 2 个 skip 是仅诊断模式适用用例；诊断模式的 1 个 skip 是正常启动树用例，已分别运行对应模式。

### 既有问题与本轮新增覆盖

Phase 0 已记录根目录 Windows sqlite3 native asset/process lookup 无法找到 `sqlite3_initialize`，以及 6 个既有文件加载失败。本轮新增的 Provider/事务测试也依赖该初始化，因此根目录共有 8 个文件加载失败，不是 8 个业务断言失败；新增的两个文件及相关旧用例在已有 winsqlite3 harness 下通过。没有为消除该基线问题修改全项目 SQLite 配置。

既有 `lib/services/share_service.dart` 的 async BuildContext warning 保持原样，不在本次定向 analyze 范围内；没有宣称全项目 analyze 全绿。harness 的既有 keyboard tap 命中 warning 仍出现，但不导致失败。

没有运行真实 PostgreSQL 集成测试：相关测试会重建 schema，不应在当前用户验收库执行。本轮未更改 PG schema/业务表协议；通过非 PG 回归不能替代真实 PG 验收。

未执行真实 DeepSeek 模型质量测试、iPhone/WKWebView、Apple Sandbox、TestFlight 或安装包构建。自动化通过不表示这些外部环境已验收。

### 本地复跑

从项目根目录运行新增后端测试：

```powershell
node --test backend/src/services/aiProtocol.test.js backend/src/middleware/aiRequestGuard.test.js backend/src/controllers/aiReliability.http.test.js
```

在 `tool/reliable_upload_tests` 目录分别运行：

```powershell
flutter test test/p0a_test.dart --reporter expanded
flutter test --reporter expanded
flutter test test/local_diagnostics_mode_test.dart --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=true --reporter expanded
```

## 6. 后续人工验收建议（未执行）

1. 在单独测试环境配套运行新后端和新客户端。未来发布优先后端再客户端；当前报告不构成部署授权。
2. 用测试书包含同章两处相同句子，选择第二处划线/解释；重开书后应只高亮第二处，发送上下文对应第二处。补测跨 em/b 标签、中文、emoji、TXT、重新进入章节。
3. 使用含被过滤空章节/导航项的 EPUB，新建解读及书签，确认 sourceIndex 与目录下标不相同时仍定位正确。旧锚点歧义不能靠猜测修复。
4. 从任一模式连续追问至少 12 轮，再问“最开始的原文、书名及解读方式是什么”；检查实际请求始终携带原证据，并人工判断回答。重复主动解读同文应有两条独立历史。
5. 从小U详情重新打开解释/问答继续追问；新记录应恢复原证据范围。旧记录只使用确实保存的信息；长原文预览及展开/收起不变。
6. 在隔离模型替身分别模拟正常 stop+DONE、length、空回答、坏 JSON、半途断网和超时；只有正常流可生成成功记录。输出中点击取消/关闭详情应迅速结束，不生成成功回答；再主动请求可重新发起。
7. 离线创建划线与想法，检查 business、trace、pending 同时存在；联网按已有 Reliable Upload 同步。三处写入失败回滚由自动化故障注入覆盖，不在真实用户库上制造失败。
8. 同用户同 request ID 并发重复请求应只有一次模型执行；变更内容返回冲突，新的主动 ID 可执行。跨后端重启/多进程不属于本轮保证范围。
9. 保留现有登录、阅读、书架、离线上传、Obsidian cursor/用户笔记保护与 IAP 关闭状态，配套验收后再决定下一阶段。

## 7. 待确认与后续独立任务

- 当前暂停于代码/测试报告，等待负责人确认真机验收或下一开发范围；不自行提交、推送或部署。
- 持久化请求幂等与 Pro 额度扣减必须在后续专项方案中一并设计、测试，不能直接沿用当前内存 guard 扣费。
- 已有 ai_messages 按 bookId 读取、无独立 user_id 的历史归属是审查中的未验证风险。本轮给回答缓存/活动请求加入账号边界，但不声称解决了历史表所有权；如需 schema 调整必须另行批准。
- 旧错误锚点、重导入后定位、历史缺失元数据不自动回填；需要单独的兼容和用户数据修复方案。
- 小U发现规则独立排期；本轮未修改其行为。
