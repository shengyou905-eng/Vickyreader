# 知读小U P1-B2.1：派生结果基础与合成数据库验证

报告日期：2026-10-22。范围：B2.1，不是正式回望功能交付或上线批准。测试运行日志的主机日期为2026-10-21，合成业务时钟也固定在该日；不使用这些日期推断真实用户数据。

## 1. 结论与边界

- 新增候选 migration 010、四张派生结果表、repository/service 基础、严格请求契约和关闭的独立 router。
- 生产 `app.js` 未接入新 router；当前应用不存在可用回望入口。router 单独挂载时所有方法返回 503，配置也不能把本阶段功能打开。
- 无真实来源 resolver、模型 executor、客户端或 UI 接入。内部 service 的生成完成方法仅在合成测试中传入模拟结果，不接受客户端直接提交答案作为云端事实。
- 没有接入原始 trace、追问、Reliable Upload、永久删书的写入/失效流程。来源被编辑或删除时，当前读取复核会拒绝正文，但数据库中的旧派生正文尚不会自动清除。**必须完成 B2.2 后才能接触真实用户回望数据。**
- 没有真实环境 SQL、现有测试业务库连接、付费模型调用、应用构建、部署、commit、push 或密钥配置变更。

## 2. 实际文件清单

除下面列出的文件，本轮未修改其他业务源码。

| 文件（仓库相对路径） | 状态与用途 |
| --- | --- |
| `backend/src/db/migrations/010_reading_recaps.up.sql` | 新增，事务化候选 DDL |
| `backend/src/db/migrations/010_reading_recaps.down.sql` | 新增，仅空派生环境可撤销，存在数据/围栏时拒绝 |
| `backend/src/config/bookRecap.js` | 新增，关闭入口、可配置测试期限，不加载部署凭证 |
| `backend/src/services/bookRecapApiContract.js` | 新增，请求白名单、UUID/revision/范围/长度校验 |
| `backend/src/repositories/bookRecap.repository.js` | 新增，注入 DB、账号锁、派生事务、删除围栏 |
| `backend/src/services/bookRecapStorage.service.js` | 新增，prepare/begin/complete/get/save/feedback/cancel/remove 内部基础 |
| `backend/src/routes/bookRecap.routes.js` | 新增，未挂载的关闭入口；不调用 DB/模型 |
| `backend/src/repositories/xiaouConversation.repository.js` | 修改，普通会话隔离过滤；拒绝通过普通创建接口指定回望关联 |
| `backend/src/services/bookRecapStorage.test.js` | 新增，4 项离线契约测试 |
| `backend/src/repositories/bookRecap.postgres.test.js` | 新增，真实 PostgreSQL 合成事务与旧 HTTP 边界测试 |
| `backend/test-support/runRecapSynthetic.js` | 新增，一次性本地 PostgreSQL 集群运行器 |
| `docs/zhidu-xiaou-p1-b21-report.md` | 新增，本报告 |

本轮开始时对 `backend/src`、`lib`、`docs`、`test`、`tool` 的 316 个现有文件采集 SHA-256，结束前逐项比较：仅 `xiaouConversation.repository.js` 变化，无文件缺失。新文件单独按上表核对。工作区原有大量未提交成果仍保留；本轮没有重置、清理、覆盖备份。该核对不是新建完整工作区备份，也不声称覆盖忽略的构建缓存。

## 3. 候选 DDL 与现有 schema 的关系

核对依据是本地实际 `backend/src/db/schema.sql` 和迁移历史，不是线上数据库探测。现有编号到 009；本轮新增 010，未修改 001–009 或 `schema.sql`。

| 结构 | 最小变化与约束 |
| --- | --- |
| `reading_recaps` | UUID 主键；`user_id -> users` 级联删除；稳定 TEXT bookId；版本、状态、选择范围、覆盖信息及结果；ready 必须有结果，非 ready 不得有结果正文；deleted/invalidated 清空书籍、范围、模型和私密派生字段 |
| `reading_recap_sources` | `(recap_id,evidence_id)` 主键；`(recap_id,user_id,book_id)` 复合 FK；原记录/追问 ID、字段、来源类型、摘要、集合摘要、定位元数据；不存原文副本 |
| `reading_recap_feedback` | `(recap_id,user_id)` 复合 FK；`(user_id,client_request_id)` 唯一；私有类别和最多1000字符反馈，不送入模型 |
| `reading_recap_operations` | `(user_id,request_id)` 主键；回望/账号复合 FK；规范化请求 HMAC、版本、generation_id、状态、deadline；同一回望只能有一个 running generate/follow_up |
| `xiaou_conversations` | 仅新增 nullable `recap_id`、owner 复合 FK、kind 对应 CHECK、每回望一个专属会话的部分唯一索引；不回填或改写旧聊天 |

现有 `users.id`、会话 ID 为 UUID，消息按 conversation 级联删除。用户阅读的 `book_id` 是 TEXT，不等同于公共目录 `books.id` 或 `public_books.id` 的 UUID，因此没有错误地把回望 bookId 外键接到公共书表，也没有用标题合并身份。

新依赖表对原始 entry/follow-up 故意不加阻塞删除的 FK。复合 FK 只能证明派生记录内部账号/书籍一致，**不能证明原文真实性或原记录归属**；后者必须由服务端 resolver 重新读取并验证。当前 resolver 仅存在于合成测试，不能用于正式功能。

新增索引覆盖账号列表、账号书籍范围、到期项、entry/follow-up 依赖及 operation。`selected_sources_json` 上限64 KiB，结果128 KiB，定位2 KiB；保留现有 B1 的证据和输出预算。

### 迁移与回滚实测

1. 在本轮新建空集群中执行现有完整 `schema.sql`，确认 public 无业务表后才初始化；随后只应用 010。schema 已含的历史迁移没有重复执行。
2. 合成旧 trace、普通会话/消息在 010 前后保持不变。没有修改现存任何数据库。
3. 010 的 CREATE/ALTER/VALIDATE 放在单事务，`lock_timeout=3s`、`statement_timeout=30s`。构造坏 kind 数据导致最后 VALIDATE 失败，四张新表和新增列均整体回滚。
4. 完全空派生数据时 down 可执行，普通聊天仍能读取；再次 up 成功。
5. 只要存在回望或删除围栏，down 明确拒绝，不能悄悄 DROP 用户数据。
6. 重复直接执行 up 会报 `42P07` 并回滚，**不是幂等迁移执行器**。比起 `IF NOT EXISTS` 静默略过结构差异，本阶段选择失败关闭。设计中“目录核对后判定已应用”的发布流程尚未实现；正式迁移前需要 catalog/checksum 审核，不自动运行 SQL。

未来迁移会对 `xiaou_conversations` 加约束并扫描/建索引，可能短暂锁表；真实数据规模、坏 kind、权限、数据库版本、锁竞争都未检查。不能拿合成测试通过当作生产可直接迁移的依据。

## 4. Repository / Service 行为

- DB 使用依赖注入，不 import 默认连接池或 dotenv。每个服务操作校验 user UUID，在事务内确认账号、复用现有 `lockUploadUser`，再锁回望。该 helper 实际通过 `sync_user_cursors` 行的插入或原值更新取得账号级行锁，并非 PostgreSQL advisory lock；不递增同步序号、不写 ledger，也未改原 Reliable Upload 实现或接入它的业务写入口。未来正式接入时需检查这一共用锁的竞争与行版本开销。
- prepare 仅接受稳定 bookId、来源 ID、显式追问选择及请求 ID。服务端 resolver 决定实际证据；验证所有送入材料的证据与依赖身份、字段、类别对应。正文、user_id、客户端 result JSON 等额外字段被拒绝。
- prepare 运行 B1 的纯预算/输入生成函数，不发模型请求，不上传原始历史。云端无法验证的来源直接失败，不能伪装账号保存成功。本机草稿 UI 不在本阶段。
- request ID 按账号隔离，同时校验 operation、recap ID 和规范化内容 HMAC；同 ID 异内容409。用户主动发起的独立行为使用新 ID，不按同原文合并。
- begin 的并发重试返回同一 operation/generation_id；只有首个提交者获得内部 `executionClaimed=true`。后续重试为 false，不能接管执行。这个标识不得返回客户端作为授权。
- 未来 executor 必须只执行首个 claim，且不自动重试。尚未实现网络调度，不能据此宣称供应商调用 exactly-once。提交 claim 后进程崩溃仍可能没有调用，调用后崩溃也可能已收费无结果，需要明确 interrupted 状态。
- complete 为内部方法，复核来源、版本、operation、generation_id、deadline 和 B1 完整结果/引文契约；不完整回答不能入 ready。结果与专属空会话、operation 成功状态同事务写入。
- get/save/feedback 先重新核验来源，未知结果版本拒绝；复核异常没有旧正文 fallback。save 和 feedback 支持请求重放；保存后取消预览到期时间。
- cancel 支持取消和到期中断收尾，禁止迟到回答保存；prepared 期限已过也可以收尾 operation。尚无定时清理 worker、网络 AbortController 或执行失败恢复 worker。
- 删除回望：先清依赖/反馈/专属会话（消息级联），再撤销 operation 并清 HMAC/结果指针，最后清正文和私人元数据、保留最小删除围栏。原始记录逐字段不变。删除早于 prepare 也能阻止同 ID 复活。
- 账号删除的 FK 级联清理经过合成验证；不改变现有账号删除 API。

### 通用会话隔离

真实的现有 router/controller/repository 在合成 HTTP 测试中运行，只有认证身份通过测试中间件注入，不声称测试了真实登录/JWT 签发。

- 普通 list、last_message、get、append、delete 排除 `kind=book_recap` 和非空 recap_id。
- 普通 create 收到 recap_id 或 book_recap kind 返回400；普通 chat/xiaou_asks 保持原行为。
- 使用 `to_jsonb(row)->>'recap_id'` 兼容迁移前不存在该列的 schema。测试实际验证了旧结构与新结构，不仅检查 SQL 字符串。
- 猜中专属 conversation ID 的同账号普通 get/append/delete 仍返回404，不能读取或注入专属助手消息。
- 未添加 messages 的新 owner FK，沿用现有表；专属消息写入尚未实现，B2.3 必须在受控事务内绑定父会话 owner。
- **旧 Flutter 可继续使用通用接口；完全未经隔离改造的旧后端不能与专属数据共存。** B2.1 未发布到任何环境，正式产生数据前必须保证所有服务实例都具备过滤；回滚不能退回无过滤版本。

## 5. 独立接口契约与本阶段状态

完整目标仍按 `zhidu-xiaou-p1-b2-design.md` 第5节。基础路径 `/api/xiaou/recaps`，未来只接 App auth + AI consent，不复用 Obsidian/MCP token 权限。

| 目标接口 | 本阶段已有 / 尚未接通 |
| --- | --- |
| POST `/prepare` | 严格请求 schema、内部 prepare、合成来源验证；无生产 HTTP handler |
| POST `/:id/generate` | 严格 schema、原子 claim；无模型请求 |
| GET `/:id` | 内部在线复核后读取；无 DTO/HTTP handler |
| POST `/:id/save` | 内部版本检查及幂等保存；无客户端 |
| POST `/:id/feedback` | 内部私有反馈；无展示/HTTP handler |
| DELETE `/:id` | 内部派生清理与围栏；无已开放路由 |
| POST `/:id/operations/:requestId/cancel` | 内部取消/超时收尾；无调度或网络中止 |
| GET 列表、证据、专属会话、operation 状态 | 保留完整设计，尚未实现公开 handler |
| POST `/:id/follow-ups` | 严格 question/版本 schema 及表约束；尚无执行器和消息写入 |

内部对象使用 `expected_revision` 十进制字符串，避免 JS bigint 精度丢失。未来 HTTP adapter 从设计中的 If-Match 严格转换；本轮没有改变现有客户端协议。

新 service 返回的是内部 DB row/operation，**禁止未来 handler 原样序列化**。HTTP DTO 需仅返回设计允许的 result/coverage/revision/fingerprint/状态等字段，排除 HMAC、内部选择、generation_id、executionClaimed、DB 错误上下文；错误日志也不能带私人正文。

当前 router 未被 app 引入，因此当前应用请求目标路径不会获得新功能。单独挂载测试时返回 `503 RECAP_NOT_AVAILABLE` 和 `Cache-Control: no-store, private`，不发 DB 或模型请求。

## 6. 在线复核、期限、成本与断网体验

没有实现15秒轮询，也没有默认在线许可时长。`onlineRevalidationSeconds=null`。

理论请求量为同时展示页面数 N / 间隔 T：例如1000个前台页面，15秒复核约66.7请求/秒，60秒约16.7请求/秒。这只是算术估计，不是已批准间隔或生产容量测试。

复核不调用模型，Token成本为0；主要成本为认证、账号锁、结果/依赖与原记录读取、摘要计算和网络流量。本阶段原型 get 使用账号级锁，是保守安全策略，同账号高频复核可能拖慢其他写入；不能直接把它当成生产高并发读方案。未来应批量读取全部依赖，避免逐条 N+1；评估事务锁持有时间、行数、响应字节、p50/p95和同账号上传竞争。

优先事件触发：打开、回前台、断网恢复、查看依据、保存及追问前复核；本机编辑/删除立即遮蔽。仅事件触发无法约束“另一个设备删除，而当前页面一直停留”的可见窗口，所以在线短期许可/推送/复核频率仍需独立选择并验收。调整频率是在网络和撤回延迟之间取舍，不可宣传全设备瞬时擦除。

离线重新打开只展示无私人正文占位，不显示缓存摘要/书名来绕过边界。连接失败不得沿用已过期的展示许可；断网会暂时打断查看，但可明确提示联网重试，不要求用户重新付费或重新生成。客户端实现及测试留到对应阶段。

测试配置（传入纯 config 函数，不读或写部署环境）：

| 配置键 | 测试默认 | 实施情况 |
| --- | --- | --- |
| `RECAP_TEST_PREPARED_SECONDS` | 1800 | prepare 期限，可改；已测短期限 |
| `RECAP_TEST_PREVIEW_SECONDS` | 86400 | 未保存 ready 期限，可改；到期拒绝正文 |
| `RECAP_TEST_OPERATION_SECONDS` | 120 | 操作 deadline，可改；到期不接管执行 |
| `RECAP_TEST_MAC_RETENTION_SECONDS` | 2592000 | 仅声明可配置候选值，没有清理 worker |

operation ID/删除围栏没有自动清理；留存政策未批准，本阶段不会删这些标识。正式使用前必须批准保留、配额、过期清理、备份恢复和防滥用方案。测试 HMAC 为代码内固定的合成 Buffer，不是真实密钥；未新增或修改任何真实凭证。

## 7. 实际测试结果

| 测试 | 结果 | 范围说明 |
| --- | --- | --- |
| 改动前后端离线基线 | 193通过 | 排除所有现有 `*.postgres.test.js`，不连接已有业务测试库 |
| 改动后后端离线回归 | 197通过，0失败 | 原193项 + 本轮4项；含P0a/P0b、B1、Reliable Upload、Obsidian、Apple IAP离线测试 |
| 新建 PostgreSQL16.13 集群 | 21个场景通过；Node计数22（含父测试），0失败 | 真SQL、事务、FK、并发及真实旧HTTP路由；不是内存数据库 |
| Flutter既有系统SQLite harness | 134通过，2既有跳过，0失败 | 账号隔离、P0a/P0b、B1、原有上传等；没有改Flutter业务文件或根SQLite配置 |
| 现有文件SHA-256复核 | 316项，无缺失，仅计划内通用对话repo变化 | 不把原有dirty工作区冒认成本轮改动 |

PostgreSQL场景覆盖：旧/新schema普通对话、迁移重复失败/空回滚/失败原子回滚、来源owner拒绝、父子事务失败、并发prepare/generate/save、异内容防重、复合owner/book FK、状态约束、普通会话四接口隔离、删除清理/先删后prepare/删除完成竞态、取消和超时、重建service不接管、源编辑/删除读取拒绝、账号级联、依赖ID一致、同意范围/完成token错误、未知schema、复核断网、预览过期、同请求不同账号及同名不同bookId。

现有 sqflite factory、widget hit-test 警告及2项skip仍在；迁移失败回滚测试故意触发SQL错误，不是新增回归。没有运行根项目构建、真实Apple联调或已有数据库集成套件；本报告不声称这些已完成。

### 合成环境与可重复运行

旧临时 PostgreSQL 工具目录缺少依赖，未连接其中旧 cluster。Docker不可用时也未启动或重置Docker。另下载 `@embedded-postgres/windows-x64@16.13.0-beta.16` 到全新临时目录，按registry返回的SHA512完整性值校验；未安装项目依赖或改lockfile。

工具目录：`C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-tools-e95b1746f4cb4447a6bee969a2ff60bd`。

最终验证集群：`C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-Nt8k6R`；运行器确认 data_directory、新空public、专用库名后执行。仅监听127.0.0.1随机端口，16MiB shared_buffers，1MiB work_mem，12连接。使用trust仅为短暂本机合成数据，不可复制到部署环境。

启动器针对Windows子进程管道继承问题已改为文件日志，并在启动异常后检查本次新data的postmaster.pid再停止。成功和中途启动实例均已停止；目录与日志保留，没有删除任何历史备份。运行器拒绝外部数据库URL，清掉测试子进程继承的数据库连接变量，不加载dotenv。

复跑命令（从 backend，路径指向已校验的二进制；每次创建全新集群）：

```powershell
node test-support/runRecapSynthetic.js "C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-tools-e95b1746f4cb4447a6bee969a2ff60bd\package\native\bin"
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
```

Flutter命令在 `tool/reliable_upload_tests`：`flutter test --no-pub --reporter expanded`。只使用该既有合成测试入口。

## 8. B2.2 审查与修改点

下列是下一阶段计划，本轮未修改这些文件：

1. `entry.repository.js`：核对 create/upsert、deleteByClientId/deleteEntry、importance、createFollowUp 等实际生效写入口；只在源内容实际变更时，同事务调用派生失效服务。Reliable Upload replay 不应重复失效。
2. `bookDeletion.repository.js`：永久删书的账号/book围栏和派生清理必须与原删除同事务；普通下架和本地文件缺失不得冒充永久删除。
3. 新的派生失效服务：编辑变stale并清正文，删除变invalidated并清全部私密派生、依赖、专属会话/消息和反馈；撤销正在运行operation，迟到结果不复活。
4. 核查所有来源写路径、账号删除锁顺序、follow-up集合变化。不能只跟踪最终引用，要覆盖全部实际送入模型的材料。复核客户端pending删除和未上传修改的优先级，不能秘密上传原历史。
5. 实际服务器证据resolver/身份映射：私有记录owner、稳定bookId、重导入版本、client/remote ID、来源字段可信度、已删除围栏。没有可靠映射就拒绝云端保存；不得按书名合并。
6. 增加可控barrier的并发回归，强制编辑/删除/保存/完成两种事务先后顺序。当前删除完成的自然并发测试不是全部时序覆盖，尤其不代表原写入口已安全。
7. 关闭入口时删除维护仍须可运行。正式接入前单独审核HTTP DTO、auth/AI consent、日志脱敏、速率限制、任务恢复、保留期限、迁移发布和回滚下限。

继续保留知识整理、我的思考、可选继续思考、依据、追问、保存、删除及私有反馈完整目标。没有提前开发跨书回望、思考轨迹、思维导图或付费能力。

本轮结束于 B2.1，等待审核，不自动进入 B2.2。
