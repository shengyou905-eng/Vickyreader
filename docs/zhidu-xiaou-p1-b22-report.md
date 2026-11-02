# 知读小U P1-B2.2：来源失效与并发安全

日期：2026-10-23。范围：关闭入口下的后端来源维护、内部存储基础和全新合成环境验证。不是回望上线或 B2.3 启动批准。

## 1. 结果与边界

- 已在现有 trace 更新、删除、重要性修改、追问新增及永久删书事务内接入统一失效机制。新增独立 trace 不改变旧回望；Reliable Upload 重放、无内容变化及被拒绝的冲突不会重复失效。
- 编辑变 stale，清派生正文、专属对话/消息、反馈并撤销 operation；删除变 invalidated，进一步清来源依赖及私人身份快照。两者递增 revision，迟到结果不能越过围栏。
- createFollowUp 改为先取得账号级锁，再锁父 trace；回望内部操作也先锁来源，再锁回望。清理统一按 operation、专属 conversation、消息/反馈的顺序取得锁。
- 增加服务端来源身份检查：账号、稳定 bookId、远端 entry UUID/client_entry_id、追问父子关系及显式选择范围。身份检查不等于原文真实性证明。
- 没有新增或修改 migration、schema.sql、公共 API 请求/响应格式、Flutter 业务代码、模型配置或用户入口。
- 没有真实数据库连接、既有业务测试库连接、付费模型调用、生产操作、构建、部署、commit、push 或凭证修改。
- 全部回望入口仍关闭；app.js 没有挂载 router，独立 router 仍始终返回503，config 仍不能启用功能。没有绕过 resolver 接入真实资料。

**未完成并留给后续审批**：正式来源 resolver、模型执行器、HTTP DTO/授权/同意范围适配、专属追问执行、客户端保存与缓存撤回、在线展示许可、清理 worker。P1 产品功能未删减，但本阶段不是完整产品交付。

## 2. 实际文件清单

以下路径均相对于项目根目录；“修改”相对于本轮开始时的工作区，而不是相对于 Git HEAD。已有大量未提交成果未被归为本轮新增。

| 文件 | 本轮变化 |
| --- | --- |
| backend/src/repositories/bookRecapInvalidation.repository.js | 新增；旧/新 schema 检查、统一 stale/invalidated/deleted 清理 |
| backend/src/repositories/bookRecapSource.repository.js | 新增；来源身份校验、原始来源锁、依赖归属检查；不是正式 resolver |
| backend/src/repositories/bookRecapInvalidation.test.js | 新增；3项离线测试，含全部30种部分结构组合拒绝 |
| backend/test-support/bookRecapB22Scenarios.js | 新增；26个实际 PostgreSQL 场景，含可控双向并发与事务失败注入 |
| backend/src/repositories/entry.repository.js | 修改；5个实际变化路径的失效调用，以及 createFollowUp 锁顺序 |
| backend/src/repositories/bookDeletion.repository.js | 修改；永久删书事务内失效 |
| backend/src/repositories/bookRecap.repository.js | 修改；来源先锁、删除共用清理模块 |
| backend/src/services/bookRecapStorage.service.js | 修改；prepare 身份边界、stale 拒绝、反馈先登记 operation |
| backend/src/repositories/bookRecap.postgres.test.js | 修改；加入事务观测器和 B22 场景、旧 schema 写入口兼容测试；保留 B21 断言 |
| backend/src/repositories/reliableUpload.repository.test.js | 修改；明确原有模拟夹具不含010，响应新增只读结构探测 |
| backend/src/repositories/syncChange.repository.test.js | 修改；同上，不模拟掉真实失效业务判断 |
| docs/zhidu-xiaou-p1-b22-report.md | 新增；本报告 |

开工时对 backend/src、backend/test-support、lib、docs、test、tool 中328个既有文件记录 SHA-256；复核仅上表7个既有文件改变，没有文件缺失。新增文件单列。该范围内 IAP、Obsidian、P0b Prompt、B1契约/基准、010及历史迁移、Flutter文件均未变化。工作区其他已有图标、配置和未提交改动保留。没有创建/清理全量备份，哈希核对不冒充可恢复源码快照。

## 3. 来源写入口与覆盖

核对实际 entries.routes/controller/repository、library.routes/controller、mcp.repository、user.repository，以及所有非测试代码对 user_entries/user_entry_follow_ups 的写 SQL。没有发现另一套 trace 或追问编辑入口。

| 实际入口 | 行为与钩子 |
| --- | --- |
| POST entries / createEntry | 新 UUID、新独立阅读行为；不失效已有回望，不按同原文去重 |
| PUT entries/client/:id / upsertEntryByClientId 新建分支 | 同上；仍沿用 writer/revision/hash/book 围栏 |
| 同接口 accepted 更新分支 | 只有原 SQL 的 IS DISTINCT FROM 检测到实际字段变化，才按 owner+entryId 标 stale；包括正文、来源元数据、书籍/章节信息、标签和重要性变化 |
| Reliable Upload 重放/无变化/冲突 | replay 直接返回；更高revision但字段未变不失效；旧revision/异writer/同revision异内容仍由原机制拒绝 |
| DELETE entries/client/:id / deleteEntryByClientId | 原删除实际返回记录后，同事务 invalidated；仍保留原上传删除围栏和同步事件语义 |
| DELETE entries/:id / deleteEntry | 原 legacy 写入保护保留；实际删除后同事务 invalidated |
| PATCH entries/:id/importance | 实际改变才 stale；重复设置同值不改回望revision或重复写同步事件 |
| POST entries/:id/follow-ups / createFollowUp | 账号锁→所属父 trace FOR UPDATE→新增追问→父来源关联回望 stale；问答仍是独立历史，不改变原响应格式 |
| 追问修改/单条删除 | 当前没有公开路由或 repository 方法；没有新增接口。内部统一钩子可以按父 entry 处理，合成 SQL 事务分别验证编辑stale/删除invalidated。未来新增端点必须调用它，不声称现已有端点 |
| 父 trace 删除级联追问 | 与父 trace invalidation 同事务；不能留下曾使用这些追问的派生正文 |
| DELETE library/books/:bookId/data | 原永久删书事务、上传围栏、trace/progress/library清理保留；按 owner+bookId 失效所有相关回望，包括 prepared/generating/ready/stale |
| DELETE library/books/:bookId、书架replace移除 | 只移除书架信息，不调用回望失效，不误当永久删除 |
| 本地 EPUB/TXT 缺失 | 没有对应的服务器来源删除请求；不因文件不可用删除回望，定位应降级 |
| 临时离线/尚未上传 | 不等于远端删除；不能将旧云端版本冒充本机新版本。客户端正式接入仍待B2.3及后续阶段 |
| 账号删除 / DELETE users | 沿用现有 FK 级联，包括派生表、专属消息；未改登录、Apple撤销或账号删除接口 |

现有 Obsidian/MCP 的痕迹接口是读取路径，未新增 Apple、MCP 或插件直接操作回望的能力。当前同步 ledger 没有 recap 类型。

来源删除实现复用现有 DELETE ... RETURNING 的真实 ID，再在**同一事务提交前**清理派生。与设计稿“先找依赖再删原记录”的 SQL 先后不同，但同账号锁覆盖全事务，依赖表有意没有原始 entry 的级联 FK，因此返回 ID 和依赖仍可用于清理；失败整体回滚，不存在对外提交的半删除状态。没有借机重写原删除协议。

## 4. 状态、正文清理及防复活

| 事件 | 状态与保留范围 |
| --- | --- |
| 来源真实编辑/新增追问 | 非终止回望→stale；result_json清空；专属conversation/messages、feedback删除；全部相关operation改revoked并清MAC/key-version/result指针/error；revision+1 |
| 已stale再次编辑 | 已无正文与可执行operation，不重复递增；保留原非正文依赖，后续删除仍能找到它 |
| 来源删除/永久删书 | →invalidated；以上清理外，删除dependencies，清bookId、selection、coverage、fingerprint、Prompt/模型/用量/成本元数据及期限；保留最小id/owner/state/revision/时间/保存标记 |
| 删除回望 | →deleted，同样清理，is_saved=false，保留deleted_at围栏；不改任何原始trace/追问或普通对话 |
| cancel 与 complete | 先提交cancel则完成被拒；先提交complete则取消返回既有RECAP_ALREADY_COMPLETED，不伪称已取消 |

来源依赖使用 reading_recap_sources，而不是 result_json 中的最终引用。prepare仍核对所有实际送入的可用 evidence 与dependency逐项对应，并增加真实所属记录检查。合成测试把第二条资料送入输入但不放进任何最终引用，删除它仍清整份结果。

追问新增按父 trace 保守失效，即使当时显式不选追问，也要求重新确认范围。它不依赖 parent.updated_at 是否改变。当前实现是写入端集合变化钩子；正式 resolver 对 follow_up_set_digest 的重建/复核仍未实现，不能把合成resolver的空摘要当成正式能力。

complete继续检查 generation_id、operation状态、deadline、recap revision/state、来源快照及完整结束契约。stale在任何正文读取/保存/完成前被拒；invalidated/deleted返回不可用；旧operation重放不恢复正文。

010 的四表和约束足够表达本轮变化，无新增迁移。未知/残缺结构不能静默漏清理：全部四表及recap_id列都不存在时按旧schema跳过；部分存在返回RECAP_SCHEMA_INCOMPLETE并回滚原写入。完整结构但列/约束不匹配时SQL失败也整体回滚；这只是运行时保护，不替代上线前DDL/checksum核验。

## 5. 事务与并发验证

应用写入锁序：

`lockUploadUser → 原 trace/追问 → recaps → operations → 专属 conversations → messages/feedback`

- lockUploadUser仍使用 sync_user_cursors 行的原值更新；不递增last_sequence、不产生额外sync_changes。新增追问实测也没有新增同步事件。
- 回望事务先对users作KEY SHARE确认账号存在，再取账号锁；find在回望FOR UPDATE之前按UUID锁现存所属来源/追问。prepare按账号和书籍解析并锁来源，再创建回望。删除清理按UUID锁全部相关回望，再按request ID锁operation和会话ID锁conversation。
- 原trace UPDATE/DELETE本身取得行锁，永久删书由原DELETE取得来源锁；同账号user锁将这些业务事务串行化。没有给原业务批量DELETE额外改SQL排序。
- feedback先登记operation，再插反馈；complete已取得operation锁后才创建专属会话，后续更新同一个已锁operation不是新的反向取锁。
- 失效、原写入、原ledger和上传状态处于同一事务。注入中途失败后，原记录、派生正文/状态、操作、会话和永久删除围栏均回滚；真实upsert的上传revision/hash也回滚。
- 所有新增业务函数仅执行本地计算或DB查询，无模型调用或网络等待。注入的resolver当前只在合成测试中使用；未来正式resolver必须是受控DB读取，不能在该接口内调用模型/远程存储。

### 可控屏障

合成测试用AsyncLocalStorage观测器暂停首个事务在取得账号锁之后，启动第二个独立连接，以pg_blocking_pids验证第二个确实被第一个阻塞，再释放首个事务。每组双向运行，不靠随机调度：

1. save先/编辑先：最终stale；前者保存标记保留，后者save拒绝。
2. complete先/来源删除先：最终invalidated；删除先时complete拒绝。
3. cancel先/complete先：先提交者决定cancelled或ready，另一操作明确拒绝。
4. 新增追问先/complete先：最终stale；追问先时complete拒绝。
5. prepare先/来源删除先：前者prepared随后invalidated；后者不产生新回望。

测试事务lock_timeout=3s，仅存在于合成适配器；没有修改生产数据库超时配置。测试未出现死锁或半提交。但这不是生产容量测试，也不是所有第三方SQL/账号注销/任意运维并发的形式化证明。

账号注销的既有实现直接DELETE users，通过FK级联，不先取得相同账号锁；回望服务的users KEY SHARE能防止账号消失后迟到保存。当前已测级联完整性和删后不可恢复，尚未枚举注销与所有旧业务写入的双向时序。既有trace写入也有该交错边界；不擅自改认证/IAP流程。正式开放前需单独覆盖死锁/序列化错误的整体回滚与提示，不能自动重试模型。

## 6. 身份与可信边界

| 项目 | 已实现/现状 | 尚需完成 |
| --- | --- | --- |
| userId+bookId+entryId | 服务端WHERE严格匹配；其他账号、其他book、未知ID拒绝 | HTTP必须从认证获取owner，禁止原样信任客户端owner |
| client_entry_id | 使用服务端实际列映射到UUID；一个选择列表内远端/本地双别名指向同一记录会拒绝 | 真实resolver复用映射；legacy仅metadata.local_id时不猜配，必要时走已知远端UUID |
| 追问归属 | 必须同owner且父entry属于选择；显式子集不能包含未知/其他父记录 | 正式证据分类、完整集合摘要与历史AI声音区分 |
| 独立导入bookId | EPUB/TXT默认Uuid.v4，可由明确调用方提供bookId | 没有内容指纹自动归并；同文件不同设备独立导入不能宣称同一身份 |
| 明台书籍 | 现有mingtai_及legacy mingtai:读取规则保留 | 不在本轮归一化/混并；公共书身份不证明用户私有痕迹归属 |
| 永久删除后导入 | 旧book围栏拒绝旧身份，新独立bookId不复活旧recap | UI来源说明和重导入交互未开发 |
| provenance/原文 | B1分类和引用校验保留；服务端身份检查不接收客户端正文/result | user_entries.original_text、metadata、source hash是可由客户端提交的内容，不是书籍真实性签名；正式resolver必须明确可信来源/降级，不能直接复用合成resolver |
| pending修改/删除 | XiaouTraceSnapshot和BookRecapEvidence现有本地优先、owner+origin、tombstone规则未改，Flutter测试复跑 | 云端不知道本机未同步变化；正式prepare需客户端范围/版本冲突协议，本机草稿不能假称账号保存成功 |
| 未同步追问 | 本地独立身份保留，不暗中上传或按文本合并 | 无可靠远端身份只能本机草稿；本阶段没有正式云端适配器 |

身份检查只读取锁定所需ID/owner/book/client ID，不为映射多读原文。原有独立历史没有重新归属、合并或删除。

正式resolver另有两项前置问题必须明确：

1. 模型输入中的book header、章节/定位说明等也要有稳定来源与版本。当前合成book元数据是固定测试材料，并非实际读取user_library_books。因此没有为书架标题/作者变化添加失效钩子；未来若resolver使用这些可变字段，必须纳入依赖/复核或采用明确的不可变范围描述，不能在缺少钩子时开放。
2. B1 sourceCompleteness仍是local_and_supplied_cache，不能冒充云端完整历史。正式服务端快照的版本/覆盖语义需在B2.3审查兼容，不擅自改变当前契约。

## 7. 普通对话隔离与兼容

没有修改B21的xiaouConversation.repository.js；本轮重新运行实际旧router/controller/repository对合成DB的测试：

- migration010前无recap_id列时，普通list/get/append/delete正常；旧schema trace创建、重要性修改、追问及删除也正常。
- 新schema中，kind=book_recap或recap_id非空均被普通查询排除；普通create拒绝指定专属kind或recap_id。
- 同账号或跨账号猜专属conversation ID，普通get/append/delete均404，不能注入assistant消息。
- list/last_message只使用普通所属对话与所属消息。来源失效清专属会话/消息，不影响chat/xiaou_asks。
- HTTP测试注入合成认证身份，没有访问真实登录系统，不声称完整JWT/设备链路已联调。旧Flutter继续使用的通用路径和格式未改变。

**回滚下限**：真实专属数据产生后，不能回滚到无普通会话隔离的旧后端；也不能退回无来源清理钩子的版本继续写来源。010 down仍拒绝已有回望/删除围栏，不能通过DROP表“回滚”。正式发布需保证所有实例同时具备兼容保护，审批迁移与停用/回滚流程。

## 8. 本轮实际测试

不是沿用B21报告数字。以下均在本轮实际执行：

| 测试组 | 实际计数 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前后端离线基线 | 197 | 197 | 0 | 0 |
| 修改后后端离线回归 | 200 | 200 | 0 | 0 |
| 全新PostgreSQL合成套件 | 47个场景，Node另计父测试共48 | 47场景/48测试 | 0 | 0 |
| Flutter既有系统SQLite harness | 136 | 134 | 0 | 2既有跳过 |

PostgreSQL为原21个B21场景重新执行，加26个B22场景。除上面的双向屏障，覆盖：旧/新结构、完整/部分结构失败关闭、owner/book/client/追问错配、未引用输入来源删除、原始upsert/no-op/replay/conflict、stale后删除、永久删书与重复删除、重导入隔离、普通下架/replace不误删、迟到operation、反馈/消息清理、事务中途失败回滚、账号FK级联、迁移空回滚/失败回滚/非空拒绝回滚及普通会话HTTP隔离。

两项“追问编辑/删除”场景验证的是内部钩子的事务契约，明确不是不存在的公开端点。文件缺失验证的是fragment-only无文件模式及B1 Flutter已有定位测试，不是假造真机文件管理测试。账号注销全并发压力、生产DB规模、真实模型、真机及真实Apple联调未执行。

后端离线回归包含P0a/P0b、B1、Reliable Upload、Obsidian与IAP离线断言。没有运行依赖原有业务数据库URL的旧PostgreSQL套件，也没有为此连接这些数据库；真实SQL只在本轮新集群执行。

Flutter仍使用既有harness系统SQLite配置，无Flutter源码/依赖修改。sqflite factory提示、键盘hit-test warning及2项skip属于既有情况；迁移失败测试的SQLite错误是预期失败注入，不是新增回归。根项目SQLite asset-loading及历史async BuildContext问题未借机修复，也不宣称已消失。

### 可复跑方式

从backend目录：

```powershell
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
node test-support/runRecapSynthetic.js "C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-tools-e95b1746f4cb4447a6bee969a2ff60bd\package\native\bin"
```

从tool/reliable_upload_tests目录：

```powershell
flutter test --no-pub --reporter expanded
```

复用的是已存在的PostgreSQL16.13二进制和安全启动器，不是旧数据库。每次mkdtemp建立新PGDATA、随机loopback端口、独立新库；核对SHOW data_directory及空public后才运行schema.sql和候选010。没有在存量库上初始化schema。目录前缀仍沿用zhidu-recap-b21，不代表复用B21数据。

所有本轮启动的集群在测试后停止，目录与日志保留，不清理旧备份。仅127.0.0.1、16MiB shared_buffers、1MiB work_mem、12连接；临时trust认证只用于本机合成数据，不可复制到部署环境。启动器不读取部署dotenv，不接受已有库URL。

最终复跑集群保留在 `C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-vMxHrI`；此前本轮两次验证目录为 `zhidu-recap-b21-sPCJbV`、`zhidu-recap-b21-qcJ5FZ`，均已停止。不要直接复用这些数据目录执行初始化；复跑只用上述启动器创建全新目录。

## 9. 风险与性能限制

1. 新增失效检查增加实际来源变更事务的目录查询、依赖查找和清理成本；旧schema也多一次只读目录检查。未做真实规模p95/锁等待测试。同账号读复核、上传、清理共享一把锁，不能持锁做模型或长网络等待。
2. 同一source被大量回望引用时，需要一次原子清理全部关联派生，可能放大锁时长、WAL及删除量。不能改成异步清理并让旧正文继续可见；正式开放前需配额/索引计划/受控负载测试。
3. 身份检查枚举所选父记录的追问ID用于严格关系验证，目前没有真实规模上限测试；正式resolver需在取正文前执行数量与字节预算，拒绝超限而不是静默丢弃。
4. 运维直接SQL、未来新增写端点、未更新的服务实例都可能绕过应用钩子。现有读取复核仅是第二道拒绝展示防线，不保证任意外部写库都会清除物理派生正文。
5. 数据库删除不意味着备份/WAL/已经显示在另一设备内存中的文本立即消失。备份保留、恢复后围栏、展示许可/断网遮蔽必须另行验证。离线重新打开只显示无正文占位的产品决定保留。
6. 完整正式resolver及缓存展示协议未完成，不能开启入口。客户端hash、original_text、provenance、result JSON、完成状态都不是自动可信事实。
7. 部分迁移结构导致原业务写入失败是有意的隐私安全选择；未来发布前必须保证010完整且所有实例兼容，不能边产生回望数据边部署无钩子的旧实例。
8. 期限仍是可配置测试默认值，没有新增保留政策或清理任务。stale、invalidated、deleted围栏不自动清理；需要后续批准留存与资源限制。

## 10. B2.3 建议与审批项

建议先完成正式服务端来源resolver：明确远端身份映射、可信字段/降级规则、完整输入依赖、追问集合摘要、书籍header版本及本机pending冲突协议；通过合成跨设备/缺失/恶意metadata测试后，再审查实际资料接入。

随后审查独立HTTP DTO、账号认证/AI consent、请求预算/速率限制、模型执行器与取消恢复、专属追问成对写入和来源复核；禁止将内部DB row/operation直接返回客户端。

客户端在线正文许可、来源编辑/删除即时遮蔽、owner+sessionEpoch缓存隔离、离线占位与保存/删除/反馈交互，需要独立开发与验收。15秒不是既定轮询值。

任何真实环境迁移/数据检查、真实资料接入、付费模型、部署、密钥配置、UI开放或存储契约版本变化都须再次明确批准。新follow-up编辑/删除接口、账号注销锁序变更、公共书籍身份归一化也不能随本轮悄悄实现。

本轮停在B2.2，不自动进入B2.3。
