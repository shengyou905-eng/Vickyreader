# 知读小U P1-B2.3.2：受控模型执行器与服务端接口适配

日期：2026-10-25。范围：关闭入口下的代码实现、离线回归及全新合成 PostgreSQL 验证。不是正式上线、真实模型质量验收或真机验收。

## 1. 结论与边界

本轮将 B231 正式 resolver 接入受控生成流程：认证/AI consent → prepare → 范围指纹确认 → 原子生成 claim → 再次解析与授权核验 → 事务外模型请求 → 完整结束/JSON/引用校验 → 事务内再次复核来源与代次 → ready 临时结果 → 用户显式 save。

已实现未挂载的 HTTP adapter、显式服务端组合工厂、单次无重试的模型传输、超时/取消/断流处理、持久化请求防重及调用统计。来源变更、删除、取消、授权撤销、错误引用或不完整输出均不能形成成功正文。

所有回望用户入口仍关闭：`app.js` 没有挂载 adapter；原 `bookRecap.routes.js` 仍固定503；`bookRecapConfig` 两个开关仍为false。新组合工厂不被应用启动代码调用，不读取模型环境变量或自动取得凭证。这里只在合成测试应用中显式挂载。

本轮没有修改 schema、010及历史 migration、B1 快照/结果结构、B231 resolver、五种免费模式及其 Prompt、Flutter、Reliable Upload 原写入、IAP、Pro、Obsidian、明台、随心记或小U发现。没有连接真实/既有业务数据库，没有调用付费模型，没有改真实凭证，没有构建发布、部署、commit、push、reset、clean。

## 2. 实际文件清单

相对于本轮开始的工作区，修改3个既有文件，新增8个文件（含本报告）。此前未提交成果不算本轮新增。

| 文件 | 状态及作用 |
| --- | --- |
| backend/src/services/bookRecapStorage.service.js | 修改；增加 dispatch/inspect/fail，begin/complete 可注入事务内授权检查，完成与统计原子写入 |
| backend/src/repositories/bookRecap.repository.js | 修改；使用010已有字段写调用统计 |
| backend/src/repositories/bookRecap.postgres.test.js | 修改；注册本轮合成场景，不改变原测试断言 |
| backend/src/services/bookRecapAuthorization.js | 新增；按既有 AI_CONSENT_VERSION 复核 active、token_version、consent |
| backend/src/services/bookRecapExecutor.js | 新增；原子领取、发出前复核、超时取消、预算、结果校验、完成/失败收尾 |
| backend/src/services/bookRecapModelTransport.js | 新增；有界 SSE 传输、完成判断、usage/返回模型采集，无重试 |
| backend/src/services/bookRecapHttpContract.js | 新增；请求复用原严格契约，对外响应独立白名单 |
| backend/src/routes/bookRecapHttpAdapter.js | 新增；未挂载 handler 与服务端组合工厂，复用实际 auth/requireAiConsent |
| backend/src/services/bookRecapModelTransport.test.js | 新增；17项本机HTTP上游模拟测试 |
| backend/test-support/bookRecapB232Scenarios.js | 新增；38项隔离 PostgreSQL/执行器/HTTP 场景 |
| docs/zhidu-xiaou-p1-b232-report.md | 新增；本报告 |

开始时对 backend/src、backend/test-support、lib、docs、test、tool 中336个既有文件采集SHA-256，排除 node_modules/.dart_tool/build/.git。最终核对仅上表3个既有文件变化，无缺失。该核对不是完整可恢复备份；没有清理或覆盖原有备份/执行锁/评测答案。整个 Git diff 仍包含此前大量修改，不能将其整体当成本轮变更。`git diff --check` 通过，存在既有行尾转换提示。

## 3. 接口与响应契约

未来基础路径仍为 `/api/xiaou/recaps`；下列是**已实现但未挂载的适配路径**。测试只在 loopback 使用 `/recaps`、`/composed`。

| 方法/相对路径 | 输入及行为 |
| --- | --- |
| POST /prepare | 原 api.prepare：recap_id、request_id、book_id、selected_sources；服务端解析后返回范围和指纹，不调用模型 |
| POST /:id/generate | 原 api.generate：request_id、expected_revision、source_fingerprint、consent_scope_fingerprint；同步等待受控任务，返回 status/replay，不流出未校验正文 |
| GET /:id | 在线复核后返回状态、范围；仅ready含结果，失败/取消无正文；stale/invalidated/deleted拒绝 |
| POST /:id/save | 原 api.save；显式保存，返回重新复核后的白名单响应 |
| POST /:id/feedback | 原 api.feedback；私有存储，返回反馈ID，不调用模型 |
| POST /:id/operations/:requestId/cancel | 空请求体；取消指定操作。已完成返回冲突，不把成功伪装成已取消 |
| DELETE /:id | 空请求体；沿用派生清理/删除围栏，不修改原始阅读记录 |

版本确认沿用实际内部 `expected_revision` 十进制字符串，本轮没有把设计稿中的 If-Match 设为既定客户端协议。不存在旧回望 HTTP 客户端需要迁移；后续客户端契约评审应固定这一选择，不能同时忽略两个版本来源。既有普通AI的SSE路径、字段和完成事件均未修改。新的回望接口选择“最终状态JSON + GET校验后的正文”，不向客户端流出半成品。

请求是 strict Zod 对象，拒绝 user_id、snapshot、result_json、客户端 provenance、完成标志及未知字段。HTTP JSON上限80 KiB，来源选择沿用64 KiB/80条及追问限制。多余 query 参数拒绝。模型、endpoint、价格、密钥只能来自显式服务端组合参数，不在请求DTO中。

响应明确列出 id、book_id、revision、state、is_saved、source_fingerprint、coverage、解析后的 sources（远端entry ID和实际选中follow-up ID）、发送/排除证据数量及 result。它不序列化原始 DB row、内部选择JSON、HMAC、generation_id、executionClaimed、原始 metadata 或完整快照。

响应固定 `scope_basis=selected_cloud_records_only`、`local_pending_verified=false`，不能暗示所有设备已同步。`fullBook=false`，`sourceCompleteness=server_selected_records`仍只表示已验证的云端记录选择，不是完整原书/逐字真实性证明。

追问范围保留原契约：省略 follow_up_ids 表示所选父记录当前全部追问；[] 表示不发送追问；非空数组表示明确子集。服务端返回实际解析的ID集合与数量，生成需确认同一快照指纹。全部追问集合版本仍进入依赖，新增/编辑/删除会触发失效或复核失败。

HTTP错误不输出 Zod 原始 issues、SQL详情、供应商正文或堆栈；返回结构化业务错误码。所有适配响应设 `Cache-Control: no-store, private`。这不是客户端展示许可协议，也不能代替离线遮蔽。

## 4. 身份、同意与材料边界

`createServerBookRecapHttpAdapter` 显式组合真实 `auth`、`requireAiConsent`、`AI_CONSENT_VERSION`、正式 server storage/resolver 和 executor。没有第二套登录、JWT签发或 consent 版本。

- userId 取 `req.user.id`，并要求匹配 `req.authUser.id`；不取请求正文。App JWT 的 active/token_version 检查沿用原中间件，不使用 Obsidian/MCP token。
- prepare/get/generate/save 复用现有 AI consent 中间件。取消/删除不要求重新同意AI处理，避免撤销同意后无法清理；反馈是私有存储操作，不发AI。
- begin、dispatch、complete 在数据库事务中重新检查账号 active、当前 token_version 和 ai_consent_version。生成期间撤销 consent、撤销令牌或封禁账号，保存被拒绝。
- 范围同意由客户端确认**服务器已计算的** source_fingerprint；两个指纹都必须与当前row匹配。客户端提供同一字符串不是来源真实性证明，resolver仍重读所属记录。
- 输入仅来自本次选择和正式resolver；没有普通聊天、其他书籍、未选择trace、随心记或反馈补充检索。历史AI保持 historical_ai，保存的阅读上下文最多是 reader_context。
- 不使用客户端生成的结果，也没有公开 complete/dispatch/fail/snapshot 上传接口。内部DI只能由可信服务器组合和合成测试提供。

授权复核是事务时点检查，不宣称其他设备的尚未上传变化已被观察，也不宣称网络发出与数据库删除之间存在跨系统原子事务。

## 5. 执行与预算

1. 严格校验请求及可信 principal，按实例并发上限准入，不建立无界排队。
2. begin 在账号锁下校验来源、指纹、revision和请求HMAC，原子建立 running operation。只有第一次提交得到 executionClaimed。
3. dispatch 再次核验授权、正式resolver快照、完整依赖、prompt版本、revision、generation_id、operation状态与deadline。
4. dispatch事务提交后，用现有 `prepareGeneration` 构造请求并复核预算。**事务和数据库连接已释放后才执行HTTP。**
5. 单次上游请求，stream=true、include_usage=true、thinking=disabled。模型/endpoint需显式配置；不改现有五模式模型配置。HTTPS为正常允许入口，127.0.0.1 HTTP仅为本机模拟；拒绝URL凭证/query/hash及重定向，不会把Authorization转发到重定向站点。
6. 有界SSE解析；要求非空内容、finish_reason=stop及[DONE]。工具调用、非空reasoning、坏事件、length结束、缺DONE、断流、返回模型中途变化均拒绝。DONE是协议完成边界，不等待keepalive连接物理关闭。
7. JSON必须完整且通过原B1 schema、scope fingerprint、evidenceRefs、引文/声音/关系检查；不修补坏JSON，不剥掉任意内容凑成功，不调用第二次模型修复。
8. complete 再次解析来源及版本围栏，并在事务内校验B1结果；正文、调用统计、专属空会话和成功operation一起提交。提交前再次检测取消/授权；任何异常整笔回滚。
9. ready仍是临时预览，is_saved=false；只有显式save才是账号收藏保存。GET/save均再核验来源。

| 限制 | 实际策略 |
| --- | --- |
| 来源 | 复用80条trace、320发送证据、完整追问集合320条、来源序列化256 KiB保护 |
| 输入 | B1完整消息UTF-8字节+1024余量，估算上限16000；不截断、不静默删选择 |
| 输出 | 请求max_tokens=3000；返回usage若声明超过3000则拒绝；正文128 KiB、总SSE输入256 KiB硬上限 |
| 请求次数 | 每个持久化generate claim最多一次本应用dispatch，自动重试0；重放只能查状态 |
| 超时 | 构造器默认90秒，可配置1–600000ms，同时不能超过operation剩余deadline |
| 并发 | 构造器默认每实例4项，可配置1–64；超限429，不修改每日额度/价格/Pro |

16000是保守估算，不是实测Tokenizer。usage缺失时不能独立证明供应商的计费Token上限；输出还受字节保护。并发/超时是关闭入口执行器的可配置技术默认，不是批准的最终付费政策或全局成本限额。

## 6. 取消、失败与防重

- HTTP生成连接在完成前关闭会触发AbortController；显式cancel先提交数据库取消，再中止本实例正在执行的网络请求。
- Promise.race让超时/取消能结束等待；即使测试替身忽略AbortSignal，迟到Promise结果也不会再次调用complete。真实传输使用fetch signal并取消reader。
- 未完整结束、坏结果、坏引用或上游故障走fail：仅当仍为同一running generation且revision相符时写failed/清正文。连接取消写cancelled。不写半成品会话消息。
- 删除/失效/取消/新代次已获胜时，fail不回填统计或正文，不覆盖新状态。complete已提交后再取消，返回RECAP_ALREADY_COMPLETED。
- 同账号+request ID校验规范化内容HMAC；并发重试不会再调模型。不同主动行为使用新recap/request ID，原文相同不去重。
- 领取后崩溃可能是“没有发出请求”，也可能是“供应商已计费但没有结果”。本实现不接管、不自动重发，**不是供应商 exactly-once 或零重复计费证明**。
- 未到deadline的重复running请求返回202/running；过期claim的重放会调用既有expiredOnly收尾，返回interrupted，不发模型。若prepared本身已过期而复核被拒，仍可通过取消/删除收尾。
- DB收尾失败返回RECAP_FINALIZATION_UNAVAILABLE，不宣布成功；持久化running claim继续阻挡重试。测试验证显式过期收尾不会重发。没有新增后台恢复/清理worker。
- 跨进程取消由数据库围栏保证不得保存；AbortController仅本实例有效。其他进程已发出的请求可能继续到deadline并产生供应商费用，后续若需即时跨进程中止应另审信号机制。

## 7. 调用统计与成本含义

复用010已有 requested_model、returned_model、input_tokens、output_tokens、elapsed_ms、cost_amount、cost_currency、pricing_version；operation保存状态及安全错误码。不新增表/列。

返回模型、Token来自上游事件；缺失/非法计数置null，不以估算冒充实测。模型别名变化可以记录，但费率只在显式配置的计费模型名与实际返回名匹配、输入输出usage都已知时使用：

`cost_amount = (input_tokens × inputPerMillion + output_tokens × outputPerMillion) / 1,000,000`

费率必须包含currency/version；本轮只在合成测试传入虚构费率。该数值是**按配置计算的费用**，不是账单扣款；缓存命中、峰谷价格、reasoning等特殊计费需以后单独核对。未配置费率/别名不匹配则费用null。真实付费请求数为0，未读取余额或API Key。

正常完成和可安全收尾的失败记录已观察到的统计；来源删除/失效优先清理隐私字段，不为审计恢复它们。显式cancel已抢先完成时不再补写迟到usage，因此部分取消的Token/费用仍未知。elapsed_ms在已发模型请求时是本机调用等待耗时；发出前失败可能仅反映准备耗时，不能把它当供应商响应时间。

新增代码没有普通正文日志/完整Prompt日志/错误堆栈日志。测试使用本机假凭证和自写合成材料，无真实用户内容。

## 8. 来源变化与事务并发

保持 `users KEY SHARE → lockUploadUser → 原始来源 → recap → operation → 专属conversation → message/feedback`。授权查询仅SELECT，不反向申请用户更新锁；不修改上传cursor/ledger协议。

B22原钩子继续负责同事务 stale/invalidated、清正文/反馈/专属对话、撤销operation。B231继续复核所有送入模型的材料，不只复核最终引用；父trace、追问集合、来源身份、章节/metadata指纹均保留。

测试中的模型barrier先确认已进入请求等待，再执行来源编辑、删除、追加追问或删除回望，最后释放模型。相关写入不需要先释放模型即可完成，验证网络期间未持账号锁。结果返回后不得变ready。B22/B231原有双向事务barrier全部重跑，包括保存/编辑、完成/删除、取消/完成、prepare/删除。

另外在complete已执行setReady但未提交时暂停，用客户端AbortSignal取消，再继续事务：最后检查导致整笔回滚，正文和专属会话不保留，最终cancelled。这覆盖的不是自然并发偶然时序。

普通chat/xiaou_asks与专属会话隔离继续通过真实旧router/controller/repository测试；旧schema兼容、同/跨账号猜ID、last_message、assistant注入拒绝均保留。正式产生专属数据后仍不能回滚到无隔离/无失效钩子的老服务器。

## 9. 本轮实际测试

下表均来自本轮运行，不沿用B231/B21数字冒充。

| 测试组 | 实际运行 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前后端离线基线 | 202 | 202 | 0 | 0 |
| 最终后端非PostgreSQL回归 | 219 | 219 | 0 | 0 |
| 最终全新合成PostgreSQL | 116场景；Node含父测试117项 | 116场景/117项 | 0 | 0 |
| Flutter系统SQLite harness | 136 | 134 | 0 | 2既有 |

离线新增17项：真实loopback HTTP的成功/UTF8/usage、缺DONE、缺stop、length、空输出、坏JSON事件、上游错误、tools/reasoning拒绝、stop后追加、字节/Token超限、返回模型变化、无usage、HTML错误、挂起中止、连接中断。

PG新增38场景，原B21 21 + B22 26 + B231 31场景全部重跑。新增覆盖正式resolver/executor/统计、并发相同请求及异内容冲突、非法结果/引用/历史AI误充证据、超时/取消/迟到、来源编辑/删除/追问变化/删回望、发出前复核、consent/token/封禁变更、完成事务故障回滚、提交前断开、并发准入、独立历史、取消注册窗口、收尾DB故障/过期恢复、模型别名费用、真实JWT/consent/HTTP/本机模拟上游全流程、组合工厂、跨owner/book/伪造字段、随心记/普通聊天来源拒绝、全部/空/部分追问、请求体超限及HTTP真实断开。

旧回归涵盖五种模式、P0a SSE/14轮上下文、P0b规则与固定语料、Reliable Upload、普通对话、Obsidian和IAP离线行为。不运行指向既有业务数据库URL的其他PG套件。引用校验通过不等于模型语义/因果推断正确；真实DeepSeek、Apple、设备、负载与真实账号均未验收。

开发第一轮新增HTTP测试把既有RECAP_SOURCE_UNAVAILABLE预期误写为409；核对实际resolver一直使用422后修正新测试并加强错误码断言。最终完整重跑通过；没有改旧断言、评测答案、评分标准或跳过关键场景。

Flutter仍使用既有系统SQLite harness。sqflite factory提示、widget hit-test warning、2项跳过保留；迁移回滚测试的SQL错误是预期故障注入。根项目SQLite native asset及历史BuildContext问题未顺手更改，不宣称已消失。

### 复跑

从backend目录：

```powershell
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
node test-support/runRecapSynthetic.js "C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-tools-e95b1746f4cb4447a6bee969a2ff60bd\package\native\bin"
```

从tool/reliable_upload_tests目录：`flutter test --no-pub --reporter expanded`。

复用的是既有PG16.13二进制，不是旧数据库。每轮运行器新建PGDATA/随机loopback端口，核对data_directory及空public，只在新合成库初始化schema+010；不加载部署dotenv、不接收已有库URL、清除继承DB连接变量。测试结束停止集群并保留目录。

本轮最终集群：`C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-9wAiJG`。此前本轮GkHYe8、0j7kiA、oy8p48（同前缀）也已停止且保留。没有清理任何旧目录。目录保留PG日志，TAP/断言输出在本轮命令记录中，不宣称另外保存了TAP文件。重新验证必须使用运行器新建集群，不可初始化这些保留目录。

## 10. 未完成事项、风险与下一阶段

1. **客户端pending协议仍未完成**：本地新trace、pending编辑/删除、缺远端身份的追问不能靠本接口被证明已同步。后续必须在发送、范围确认、保存、展示和异步返回时核验 userId+sessionEpoch+origin、本地tombstone及pending；不能默默上传或用旧云端版本覆盖本地删除。当前scope响应已明确不作此保证。
2. **展示与撤回尚未完成**：本轮没有UI、回望列表/证据详情/缓存许可端点。GET只有实时复核后的当前结果，不授予永久离线许可。离线重新打开无正文占位、当前页面来源变更遮蔽、跨设备删除撤回窗口需B2.4设计与验收；未加15秒轮询。
3. **专属追问留待B2.3.3**：当前只沿用complete创建专属空会话；未执行追问模型调用/成对消息写入。必须独立设计证据继承、完整轮次、幂等/取消、来源再核验及私有消息owner关系，不能用普通append assistant入口绕过。
4. **真实模型未验证**：解析器支持当前代码使用的chat-completion SSE形状，不代表已对未来供应商版本、实际usage/别名、Tokenizer、网络故障和语义质量联调。真实小样本需要单独许可、预算和匿名材料。
5. **非分布式exactly-once**：数据库claim/代次防止应用重放触发第二次执行，但无法证明供应商没有内部重试，也无法撤回已经发出的材料或保证断开后不计费。跨进程即时取消、崩溃恢复worker、运营审计与全局限流/费用上限未实现。
6. **授权/删除的时间边界**：发出前复核和保存前复核之间允许来源变化，结果必须丢弃；已经发给供应商的数据不因本地删除自动消失。无锁网络调用与数据库变化之间无法提供跨系统原子性。用户撤销consent的即时供应商侧撤回也未实现。
7. **性能与保留**：多次resolver/hash/授权查询与账号锁有成本。未做真实数据规模/p95/高扇出压力测试；并发限制只是单实例保护。保留期限、MAC清理、最小围栏、过期worker仍沿用待审批状态。
8. **发布回滚仍需另审**：无真实迁移、生产密钥配置或部署检查。正式启用前要批准010迁移与一致部署/回滚下限，所有实例必须具备会话隔离及来源失效保护，不能回退到不兼容旧代码。

代码完成和自动化验证仅限上述关闭入口范围。P1知识整理、我的思考、可选继续思考、证据、追问、保存、删除与反馈的完整产品目标不变；本轮未以部分接口代替最终交付。

本轮到此停止，不自动进入B2.3.3/B2.4，也不开放入口、部署或提交。
