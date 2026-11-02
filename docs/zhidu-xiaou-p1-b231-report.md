# 知读小U P1-B2.3.1：正式来源解析器与可信证据契约

日期：2026-10-24。范围：服务器内部、关闭入口、全新合成 PostgreSQL 验证。不代表正式功能上线、真实资料接入或模型质量验收。

## 1. 完成与边界

已实现服务端读取的 `createBookRecapSourceResolver`，通过 `createServerBookRecapStorage` 接入现有内部 prepare、begin、complete、get、save、feedback 的来源准备/复核。客户端不提供正文、结果、可信 provenance 或覆盖声明；读取基于当前账号、稳定 bookId、远端 UUID 或实际 client_entry_id 列。

已完成：归属、父子关系、永久删书与上传删除围栏校验；证据分类；完整输入依赖与追问集合摘要；章节/元数据/微秒时间版本核对；来源超限和不足时拒绝；B22 删除/失效及并发机制回归。

经用户单独批准，将 B1 `sourceCompleteness` 兼容扩展为 `local_and_supplied_cache | server_selected_records`。保留旧值原语义、schemaVersion=1、结果 JSON 结构和证据引用规则。新值只表示**服务端核验的所选云端阅读记录范围**，不是完整云端历史、完整原书或逐字真实性认证。

没有修改数据库结构、候选010或历史迁移、schema.sql、公共 API、Flutter 业务代码、原始写入流程、五种免费解释模式、账号隔离、Obsidian、IAP、Pro、明台、随心记。没有调用付费模型、读取真实用户资料、连接已有业务数据库、修改凭证、构建发布、部署、commit、push、reset、clean。

app.js 仍未挂载回望 router；独立 router 仍503，配置仍不能开启回望。本轮没有模型执行器、正式 HTTP handler、客户端或 UI。P1 的完整保存、查看、追问、删除和反馈产品目标不变，未提前开发 B2.3.2/B2.3.3/B2.4。

## 2. 实际文件清单

下列“修改”相对于本轮开始的工作区；原有大量未提交内容不算本轮新增。

| 文件（仓库相对路径） | 变化 |
| --- | --- |
| backend/src/services/bookRecapSourceResolver.js | 新增；只读云端解析、版本依赖及复核 |
| backend/test-support/bookRecapB231Scenarios.js | 新增；31个合成 PostgreSQL 场景 |
| docs/zhidu-xiaou-p1-b231-report.md | 新增；本报告 |
| backend/src/services/bookRecapContract.js | 修改；只扩展覆盖枚举，增加不等于真实性认证的说明 |
| backend/src/services/bookRecapContract.test.js | 修改；2项新旧枚举/引用/消费者兼容测试 |
| backend/src/services/bookRecapGeneration.js | 修改；模型输入保留 provenance/sourceField，明确云端记录与原书认证的区别；仅回望 Prompt 版本变为 xiaou-book-recap-v1.1 |
| backend/src/services/bookRecapStorage.service.js | 修改；新增显式内部工厂，原依赖注入入口保留 |
| backend/src/repositories/bookRecapSource.repository.js | 修改；prepare 身份锁查询最多读取321个追问ID，超过320整体拒绝，不截断后成功 |
| backend/src/repositories/bookRecap.postgres.test.js | 修改；注册新增合成场景，保留原B21/B22断言 |

开工时对 backend/src、backend/test-support、lib、docs、test、tool 中333个现有文件采集 SHA-256，排除 node_modules/.dart_tool/build/.git。复核仅上表6个既有文件变化，无文件缺失；新增文件单列。Flutter、IAP、Obsidian、原五模式 Prompt、全部 migration、已有评测语料/答案及文档未改。Git tracked diff仍含此前96个文件的大量改动，本轮没有将它们重置或冒认成本轮成果。哈希核对不是完整可恢复备份；没有清理原有备份。

## 3. 接口与事务

```javascript
const resolver = createBookRecapSourceResolver({ origin: serverConfiguredOrigin });
await resolver.resolve(tx, authenticatedUserId, bookId, selectedSources);
// => { snapshot, dependencies }
await resolver.revalidate(tx, authenticatedUserId, recapRow, storedDependencies);
// => current snapshot; failure throws, never falls back to old body

const service = createServerBookRecapStorage({ repository, origin, macKey, config });
```

这是内部接口，不是 HTTP 授权接口。调用者必须使用现有 repository.transaction，userId 必须来自认证主体，origin 来自服务器配置；tx 必须处于账号锁保护内。生产 app 不实例化该工厂。测试通过依赖注入使用新合成库，未加载部署 dotenv 或默认连接池。

锁顺序保持：`users KEY SHARE → lockUploadUser → 原始来源/追问 → recap → operation → 专属 conversation → message/feedback`。prepare 在解析前沿用 lockSelection；重新查看/完成前 find 沿用 lockRecapSources。resolver 本身只读，不新增 FOR UPDATE，不在已锁 recap 后反向申请来源锁。无 HTTP、文件加载、上传、模型或其他外部网络等待。

resolve 批量读取所选 trace、所选父记录的追问集合及对应上传状态。revalidate 同时比较完整依赖、来源指纹和快照指纹，不能只比较结果引用或 parent.updated_at。B22 原业务写入钩子不变：真实编辑/新增追问同事务 stale；原始删除/永久删书同事务 invalidated；迟到生成不能越过 revision、generation_id、operation、取消/删除围栏。

同账号受支持的写入口共享账号锁。测试中的越过 repository 的直接 SQL 只用于构造合成异常：读取复核会拒绝旧正文，但不声称可以令任意运维 SQL 自动执行物理清理，或防止不遵循锁契约的外部程序在任意时刻写库。

## 4. 来源分类与可信度矩阵

| 云端字段/来源 | B1 kind / provenance | 可信边界 |
| --- | --- | --- |
| ai_explanation 的 reading_ai_context.selectedText；ai_question 按 scope 取 selectedText/pageText/chapterText | book_excerpt / reader_context | 证明这段上下文存于所选所属阅读记录；不证明与原书逐字一致，不证明作者断言为真 |
| 单独 original_text，缺少可识别阅读上下文 | unverified_excerpt / legacy_unverified | 留在内部快照供范围/版本检查，不送模型，不允许有效引用 |
| highlight 的原始文本 | highlight / trace | 表示一次关注/摘录，不等于赞同，不独立支撑作者观点 |
| user_input，source=ai_question | user_question / trace | 用户保存的问题，不代表持有该观点 |
| 其他允许 source 的 user_input | user_note / trace | 用户保存的表达，不扩展到人格或心理判断 |
| ai_explanation 字段 | historical_ai / trace | 历史 AI 内容，不能变为原文或用户观点 |
| origin=xiaou_asks 的 original_text | ai_prompt / ai_prompt | 自动开场问题，不是书籍原文 |
| 所选追问 question / answer | user_question / historical_ai，provenance=follow_up | 同账号且父 entry 匹配；保留每个独立追问ID，不按文字去重 |
| 任意层级 free_note_id/freeNoteId/free_note/free_notes/authorized_free_note 标记及相应 origin | 拒绝整份选择 | 包括曾授权的随心记；不遍历链接、不访问随心记或普通聊天表 |
| 未知 origin、非对象 metadata、错误身份/父子关系、空的所选追问问答 | 拒绝整份选择 | 不静默过滤后假称完整成功 |

无原始上下文的旧记录仍可提供明确的用户问题/批注、历史 AI；但不能凭字段名补出书籍证据。只有不可信原文字段且没有其他可发送材料时拒绝。只有划线/历史AI而无可用原文或用户表达时，沿用 B1 的 insufficient_evidence 规则。每条被选 trace 必须有实际可发送依赖，不能悄悄丢弃无材料的选择。

metadata 中的 `verified`、`provenance=current_document`、source hash、document_version、offset、sourceCompleteness 或客户端 result 均不能提升信任。保存的 reading_ai_context 也来自阅读客户端，因此最多标为 reader_context；本实现从不产出 current_document/business_record 或 exact。普通对话、ai_messages、自由笔记不作为兜底资料读取。

已知标记排除不能识别用户把私人内容手动复制到普通阅读记录并移除所有来源标记的行为；当前 schema 没有不可伪造的来源证明。不能把本轮分类机制宣传成原文认证或内容来源鉴定。

## 5. 身份、版本、依赖与覆盖

### 身份

- 每次 SQL 以真实 user_id + book_id + entry UUID/client_entry_id 约束。别名指向同一记录重复选择拒绝，不能产生双份假来源。
- client_entry_id 只使用实际列；legacy metadata.local_id 不参与猜配。有合法远端 UUID 的旧记录可以读取，无远端身份的本地记录不能云端认领。
- 追问必须同账号且 entry_id 是选中父记录。数据库现有 FK 不能单独保证这点，resolver 额外检测所选父下存在错 owner 的损坏记录并拒绝。
- 永久删书围栏阻止旧book，即使被直接SQL重新插入记录；上传状态 deleted 或 book 身份矛盾也拒绝。
- 不按书名、作者、文件、文字、时间合并。跨设备同账号同稳定bookId/远端身份可以复核；独立导入生成不同bookId仍分别处理。保留明台现有 mingtai_ / legacy mingtai: 身份，不归一化或相互猜配。

### 指纹

- `RESOLVER_VERSION=server-reading-records-v1` 进入源摘要。
- evidence ID仍为 B1的 `e- + SHA256([entryUUID, followUpUUID|null, sourceField])`；保留同文不同历史ID。
- source_digest 覆盖完整原trace行字段，包括类型、所有正文、metadata、书籍/章节声明、标签、重要性及身份。数据库 created_at/updated_at 使用显式 UTC 微秒字符串参与摘要，避免 Node pg Date 毫秒精度漏掉修改。
- follow_up_set_digest 覆盖同父记录的**完整**追问集合：稳定 entry/id 排序后的 id、owner、parent、question、answer、UTC微秒创建时间。显式选择子集或空数组也保留集合摘要；未发送的追问发生变化会保守要求重新确认。
- 每个实际发送的 evidence 都有依赖；追问依赖同时关联父 trace 摘要和集合摘要。结果中没有引用它，也不能省略依赖。unverified_excerpt不发送；其变化仍在父摘要与快照指纹中。
- revalidate 对依赖的 owner/book/recap、evidence/entry/follow-up/client身份、field/kind/provenance、source_digest、集合摘要及locator逐项规范化比较，再核对 snapshotFingerprint。缺依赖、错依赖或旧 resolver语义拒绝。
- observed_revision/writerId 记录云端已观察值；单纯无内容变化的上传revision前进不作为失效条件。真实 Reliable Upload replay/no-op 已验证仍可读，真实内容改变由B22钩子失效。
- expected_digest 仅能要求“与服务器重算摘要一致”，不授予归属或信任。不等同于 Reliable Upload request_hash，也不直接接受本地自算摘要作为事实。

snapshot SHA-256和源摘要都不是签名、语义证明或鉴权。新枚举由正式 resolver 构造；纯 B1 validator 只是格式/校验和验证，不能用于将客户端快照授权成云端可信资料。

### 覆盖及预算

server_selected_records 的 availableEntries/includedEntries 都指本次实际核验的选择范围，不统计整本书所有云端记录。selectionApplied=true、fullBook=false；includedFollowUps 是实际选择的追问数。被选资料不可用时整体拒绝，因此成功快照 quarantinedEntries=0 不代表该账号其他历史全部可信。

保留 B1 上限：80 trace、320发送证据、16,000输入Token保守估算、3,000输出Token、单次请求、零自动重试。估算仍是完整请求UTF-8字节数+1024，不冒充真实计费Token。输入材料现在保留 provenance/sourceField，模型能区分选区、页面、章节记录字段；长片段不截断。

额外读保护：所选父记录全部追问最多320条；读取正文前在DB计算原trace及完整追问集合的序列化字节合计，超过256 KiB拒绝。超限返回 RECAP_SCOPE_TOO_LARGE，无部分prepared落库。不足或无法验证返回明确失败；没有自动拆批或偷偷上传本地历史。大量追问的单条trace即使只选小子集也可能超集合保护，未来需要另审受限集合摘要/分页方案，不能静默放大上限。

## 6. Book header 与定位策略

现有书架标题/作者修改没有回望失效钩子，因此**不查询 user_library_books、不把本地header放进模型**。云端快照 book.title/author/documentVersion 均为 null；范围由不可变的账号+origin+bookId和所选trace定义。不利用模型记忆补全整书。

chapter_index/chapter_title 来自所属trace列，进入源摘要；chapterTitle作为记录中的提示进入模型，不是原书认证。reading_ai_context 中的 bookId/book_id 若显式存在且不匹配则拒绝；其中标题、作者、initialAnswer、其他任意字段不作为额外模型资料。

定位始终 fragment_only，start/end/documentVersion=null。客户端offset、同章重复句、旧sourceIndex与display chapterIndex不能在没有原文版本的服务器上证明精确位置。本地书文件缺失不等于删除云端trace；书架改名或移除不会误删回望。trace中的章节、metadata、document_version或时间变化会被复核检测，实际原业务编辑还会主动stale。

未来“回到原处”仍须阅读器按当前文档版本、sourceIndex和实际片段核对；不以fragment_only假装精准跳转。本轮不提供该UI，不改阅读器。

## 7. 新旧兼容与本机 pending 边界

检索当前 lib、test、tool、backend 消费端：Flutter `BookRecapEvidence` 只产出旧值，没有读取新云端快照的业务消费者。本轮没有发现需要改Flutter才能兼容的已实现入口。当前后端 validator、生成输入、结果校验和引用检查均测试旧/新枚举；未知值拒绝。Flutter→Node 原有跨语言旧快照测试重新通过。

正式 resolver 不会把既有合成/local标记的存储行默认为已云端认证；遇到旧coverage返回 RECAP_RESOLVER_VERSION_MISMATCH，需重新prepare，而不是重写旧数据。旧B1纯快照仍可照常校验/生成。尚未扩展枚举的旧后端会拒绝新值，不能承诺任意老版本程序前向兼容；未来发布/回滚必须保留枚举兼容、B21会话隔离、B22删除钩子。没有真实回望数据迁移或自动回填。

已只读核对 Flutter `XiaouTraceSnapshot` 和 `BookRecapEvidence`：本地记录优先、pending_upload_operations、upload_entity_revisions删除tombstone、locally_deleted_books、remote_id及owner/sessionEpoch都继续保留。本轮没有改它们。

| 情况 | 本轮能力 / 后续责任 |
| --- | --- |
| 已同步记录/追问 | 服务端归属、身份、内容版本及集合复核 |
| 本地新trace、无远端ID的追问 | 服务端无法找到则拒绝；后续只能本机草稿，不显示账号保存成功 |
| 本地pending编辑/删除 | 云端看不到未上报变化，可能仍有旧合法云端版本；resolver不能独自识别 |
| 跨设备账号相同 | 依稳定ID读取云端当前内容；不等于已知所有设备尚未同步状态 |
| 已删除书籍重新导入 | 旧book围栏保留，新bookId独立；不复活旧派生 |
| 离线重新打开云端回望 | 产品约束仍是无私人正文占位；本轮没有实现客户端缓存许可 |

后续客户端范围确认协议必须在发送、确认、展示、保存及异步返回时复查 userId+sessionEpoch+origin；报告本机pending/tombstone/缺少远端身份，禁止用缓存远端版本遮盖本地删除；显式区分“全部追问”和“空/子集”；由服务器返回解析后的身份、版本和覆盖供用户确认。客户端声明可以拒绝/缩小可用性，不能给自己授信。变更后必须重新prepare/同意，不能为了保存回望隐式同步全部历史。本轮未新增公共字段或端点。

## 8. 本轮实际测试与复跑

以下数字来自本轮实际运行，不沿用上一阶段报告冒充结果。

| 测试组 | 实际运行 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前后端离线基线 | 200 | 200 | 0 | 0 |
| 修改后后端离线 | 202 | 202 | 0 | 0 |
| 全新合成 PostgreSQL | 78场景；含父测试Node计79 | 78场景/79测试 | 0 | 0 |
| Flutter系统SQLite harness | 136 | 134 | 0 | 2既有 |

PG包含原B21的21场景、B22的26场景全部重跑，另新增31场景。新增覆盖：合法解析及内部全流程、跨owner/book/entry/follow-up、坏parent owner、client映射/legacy/重复别名、同名不同book、同文独立历史、永久删除后非法重插围栏、类型分类、伪造metadata、私人来源排除、选区/页/章范围、expected_digest、追问集合新增/编辑/删除、未引用但参与输入的来源删除、章节/微秒/metadata变化、可变header排除、所有预算、坏依赖、真实上传no-op/编辑、保存/反馈/删除/取消，以及事务回滚与锁序。

新增4项barrier场景强制 prepare/delete 和 complete/delete 两种提交顺序。使用独立连接、AsyncLocalStorage观测器，在首事务拿到账号锁后暂停，以 pg_blocking_pids 确认第二事务真正阻塞，再释放。原B22其他双向竞态也全部重跑。未以随机并发碰巧成功作为时序验证。

开发中曾有新测试默认参数内await的语法错误，以及“未引用来源”夹具因随机UUID排序而把两条记录都引用的构造错误；已修复新增夹具，保持核心断言，最终完整套件0失败。没有修改原有评测答案、固定语料、评分标准或业务判断来绕过测试。

后端离线回归包括五种免费模式/P0a/P0b、普通对话、Reliable Upload、Obsidian、Apple IAP。没有运行依赖原有业务数据库URL的旧PG套件。Flutter继续使用既有系统SQLite harness：sqflite factory、hit-test warning和2项skip保留；迁移失败回滚测试的SQL错误为预期注入。根项目SQLite asset-loading和历史async BuildContext问题未顺手修复，也不声称消失。

从 backend 目录复跑：

```powershell
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
node test-support/runRecapSynthetic.js "C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-tools-e95b1746f4cb4447a6bee969a2ff60bd\package\native\bin"
```

从 tool/reliable_upload_tests 目录：

```powershell
flutter test --no-pub --reporter expanded
```

复用的只是既有 PostgreSQL16.13 二进制，不是旧数据库。启动器每次新建PGDATA、随机loopback端口、独立空库，验证data_directory及空public后才初始化schema+候选010；清除继承DB变量，不读部署dotenv。16MiB shared_buffers、1MiB work_mem、12连接，仅本机合成trust认证，不可照搬生产。

最终通过的集群为 `C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-SDEfha`，已停止并保留。此前本轮 `x5OVUu`、`1uKfph`、`JeUdAc`（同前缀）也全部停止、未清理。目录保留PG/启动停止日志；测试断言输出在本次命令结果中，不声称目录含额外TAP归档。复跑必须通过启动器创建新目录，不可拿保留数据目录重新初始化。

## 9. 风险与未覆盖范围

1. 服务器证明的是云端记录归属和版本，不是原书、原作者、客户端诚实或模型语义正确。既有source字段没有签名来源链；无上下文的旧划线不能自动升级为原文证据。
2. 云端无法观察其他设备未上传状态。必须先完成客户端范围确认/缓存遮蔽，再考虑真实接入。断网无正文占位约束不能由本轮后端自动实现。
3. 源摘要包括完整trace元数据，可能保守失效未进入模型的字段变化；这比漏失效安全，但可能增加重新确认次数。版本算法变化也应拒绝旧依赖，不暗中重签。
4. prepare及每次在线复核会增加批量SQL、字节计数、规范化哈希和B1输入预算计算。没有生产容量/p95/大账号负载测试；共享账号锁会阻塞同账号上传。resolver无N+1来源查询，但依赖插入仍沿用逐条INSERT，最多320。
5. 预算限制Node收到的正文量，不代表DB做TOAST解压/序列化没有成本。prepare追问ID查询已有321上限；既有 find/删除锁流程仍会枚举父记录追问ID，极大异常集合/高扇出需单独做受限性能方案，不能牺牲删除原子性。
6. 不支持任意外部SQL绕过锁/失效钩子的并发保证。读取复核能拒绝多数已提交变化，不等于自动清除备份、WAL、其他设备已显示内容。账号注销与全部旧写入口交错的压力测试仍沿用B22遗留项。
7. 回望依赖中的哈希/身份也属于私有派生数据。失效/删除沿用B22清理，不额外打印正文/hash/凭证。正式HTTP适配不得原样返回内部DB row、operation或数据库错误。
8. 本轮测试没有模型调用、真机、网络断开真实体验、真实JWT链路、付费额度或部署验证。自动引用检查不能证明推理被证据蕴含；未生成任何真实回望质量结论。

## 10. B2.3.2 前置条件与建议

后续建议先审核：认证与AI consent、客户端pending/选择范围/版本确认、服务器受控模型执行器、实际模型输入预算、usage/耗时/费用、无自动重试与中断恢复、完整结束状态、结果引用及语义质量验证。发送前必须再次复核当前范围，外部请求不得占用数据库事务；完成后仍走本轮formal resolver及B22围栏。

需要单独批准的后续工作包括：正式HTTP DTO/开放策略、模型请求与测试预算、专属追问的成对消息写入、展示许可/离线遮蔽、缓存撤回、真实数据/迁移/发布/回滚计划。不能让客户端提交result JSON，也不能直接接收客户端标记为server_selected_records的快照。

没有新增跨书、思考轨迹、思维导图或会员限制。本轮停在B2.3.1，等待审核，不自动进入下一阶段。
