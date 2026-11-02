# 知读小U P1-B2.3.3：回望专属追问与可信对话链路

开发日期：2026-10-26；收尾复核：2026-10-27。范围：关闭入口下的后端实现、合成 PostgreSQL、模拟模型与离线回归。不是正式上线、真实模型质量验证或 iPhone 验收。

## 1. 实现结论

已实现：有效回望 → 认证及 AI consent 复核 → 所选云端来源重新解析 → 专属完整历史校验 → 领取 follow_up operation → 发出前再复核 → 事务外受控模型执行 → 完整结束/引用校验 → 事务内再核验 → 原子写入 user/assistant 两条消息 → 专属历史重新读取。

复用010既有 operation、conversation 和 message 表，没有修改 schema 或 migration。未修改 B1 快照/结果 JSON、正式 resolver、原始记录写入口、五种模式、Flutter、IAP、Pro、Obsidian、明台或随心记。

`app.js` 没有挂载回望 adapter，`bookRecap.routes.js` 仍固定503，generationEnabled/readEnabled仍为false。没有连接真实/既有业务数据库，没有真实模型请求、密钥变更、构建发布、部署、commit或push。没有进入B2.4。

## 2. 实际文件范围

修改6个已有文件，新增5个文件（含报告）。这里以本轮开始的内容哈希为准，不将此前未提交文件冒认为本轮新增。

| 文件 | 本轮变化 |
| --- | --- |
| backend/src/repositories/bookRecap.repository.js | 专属会话/历史有界读取，成对写入，revision递增 |
| backend/src/services/bookRecapStorage.service.js | begin/dispatch/complete/failFollowUp、getFollowUps、历史完整性验证；取消区分生成与追问 |
| backend/src/services/bookRecapExecutor.js | 内部workflow注入复用原有执行生命周期；可信principal兼容携带JWT有效期 |
| backend/src/services/bookRecapAuthorization.js | 已验证JWT有效期的事务时点检查 |
| backend/src/routes/bookRecapHttpAdapter.js | 未挂载的专属POST/GET、取消联动和服务端组合 |
| backend/src/repositories/bookRecap.postgres.test.js | 注册48个新增合成场景，保留旧断言 |
| backend/src/services/bookRecapFollowUpContract.js | 新增；追问回答、消息封装、完整上下文及预算契约 |
| backend/src/services/bookRecapFollowUpExecutor.js | 新增；复用受控executor的专属追问及读取适配 |
| backend/src/services/bookRecapFollowUpContract.test.js | 新增；9项离线契约测试 |
| backend/test-support/bookRecapB233Scenarios.js | 新增；48项PG/并发/模拟上游/适配层场景 |
| docs/zhidu-xiaou-p1-b233-report.md | 新增；本报告 |

开发前记录 backend/src、backend/test-support、lib、docs、test、tool 中344个文件的SHA-256（排除node_modules/.dart_tool/build/.git）。10月26日收尾核对只改变上述6个既有文件，无缺失，新增文件单列。此核对不是完整可恢复备份；没有清理已有备份、执行锁、评测材料或其他未提交成果。Git diff仍包含此前大量工作。10月27日续接仅补报告及复跑，不再修改业务代码；原内存哈希清单不能在续接后重新取得，因此不声称又做了一次同基线全量哈希比较。

## 3. 状态与接口

`saved`不是独立state：有效条件是state=ready，且未保存预览没有过期。is_saved=false/true都允许追问；不会因为追问而自动收藏，也不延长临时预览有效期。prepared/generating/failed/cancelled/stale/invalidated/deleted/expired均不能追问。

沿用独立回望adapter，新增相对路径：

| 接口 | 契约 |
| --- | --- |
| POST /:id/follow-ups | 复用原api.followUp：request_id、expected_revision、question（1–4000字符）、可选item_id；返回status/replay，running为202 |
| GET /:id/follow-ups | 在线重新授权、复核来源与历史；返回revision、source_fingerprint、coverage、local_pending_verified=false、turns |
| POST /:id/operations/:requestId/cancel | 原路径兼容generate/follow_up；取消追问不清空成功回望或旧问答 |

turns仅含turn、question和通过校验的answer。不会返回原始数据库行、MAC、generation_id、内部request body、原始metadata或完整证据快照。adapter所有响应保持no-store/private。

请求仍是strict DTO，拒绝客户端history/result_json/snapshot/user_id/book_id及其他扩权字段；item_id必须属于当前回望。身份来自已有auth中间件，AI consent沿用现有机制。范围锁定在已确认的回望来源指纹，不通过追问追加来源。新问题是用户本次授权的讨论内容，但不能产生新的原书证据ID。

没有新增公开complete、历史append/update/delete接口；普通小U接口仍不可进入专属会话。删除回望继续清整份派生结果及专属历史，不影响原始阅读记录。单轮历史编辑/删除并非本轮新增产品入口；若存储中已有历史缺失/篡改，读取与继续追问均拒绝，而不是带着残缺上下文生成。

## 4. 证据与模型结果

每轮通过B231正式resolver重读账号+bookId+所选entry/follow-up，复核完整依赖、父记录及追问集合，不读取普通聊天、其他书籍、随心记或未选资料。

输入第一份材料保留全部授权证据及B1覆盖说明；回望正文单独标为derivedRecap/historical_ai。原历史AI仍为historical_ai，用户问题与批注保持原分类，reader_context不升级为原书逐字认证。章节只作记录定位提示，fullBook=false。

新增专属回答格式，不改变原B1回望JSON：

```text
{ schemaVersion: 1, snapshotFingerprint,
  parts: [{ text, basis, evidenceRefs, quotes }] }
```

每段通过B1既有引用/声音/逐字引文规则校验：source_supported需要原文片段，user_explicit需要用户表达，ai_inference需要原始书籍或用户证据且标明推断。历史AI不能单独支持原文断言、用户立场或新推断。无效ID、错快照、捏造引文、错voice、不完整结束全部拒绝。

回答最多8段，单段text最多3000字符，每段1–24个引用、最多8个引文；复用B1校验时逐段映射，避免错误地把回望“最多3个继续思考卡片”的限制强加给追问段落。直接引文放quotes，读者text自然回答，不强制栏目或技术术语。Prompt版本为xiaou-book-recap-follow-up-v1。

引用和结构校验不等于语义证明。模型仍可能误解材料、过度推断或把引用与结论错误关联；本轮没有真实模型质量评分，不能宣称已消除幻觉。

## 5. 多轮历史与完整性

复用xiaou_messages.content TEXT保存专属版本化JSON，普通chat/xiaou_asks的文本协议完全不变。每轮两条记录，分别role=user/assistant、status=completed。

- user封装保存规范化问题请求、turn、源指纹及generationId。
- assistant封装保存结构化回答、相同turn/源指纹/generationId及服务端HMAC seal。
- seal绑定回望ID和整组问答，复用已配置的服务端MAC密钥；不是客户端签名、不是原文认证，也不是加密。
- 成功operation.result_id指向assistant消息，request MAC、expected_revision和generation_id共同核验用户问题身份。
- 读取检查全部消息owner/status/角色、连续turn、配对、seal、成功operation数量和对应结果ID，并重新检查每份历史答案引用。
- 不依赖created_at排序解决同事务时间相同的问题。顺序由受保护的连续turn决定；数据库消息按UUID稳定读取以计算历史指纹。
- 单条缺失、整组被删除、内容被改、错误owner、其他回望消息替换均拒绝。不会把损坏历史静默当作“没有历史”。

上下文保留全部已完成轮次，严格user/assistant成对，不做摘要、不自动裁剪，不丢弃最早纠正和原始证据。超过预算返回RECAP_HISTORY_BUDGET，需另行规划缩小范围/新讨论策略；没有假装支持无限追问。

限制：完整消息UTF-8字节+1024余量不超过16000；max_tokens=3000；响应正文128 KiB/SSE256 KiB继续沿用B232。专属历史硬上限64轮/128消息，读取前SQL检查总content不超过512 KiB。实际可继续轮数通常先受输入预算限制；14轮短合成问答已通过，不代表任意14轮长回答都装得下。

## 6. 幂等、取消与事务

operation='follow_up'复用010已有枚举和同回望单running模型操作唯一索引。账号+request ID+规范化内容HMAC决定重放；不同主动请求不按文字去重。同ID改问题/卡片/版本/回望拒绝，同ID同内容只返回原状态，不再调模型。

begin在账号锁下验证ready/来源/版本/卡片/完整历史及输入预算，然后领取claim。dispatch再次复核后提交事务，才调用模型。完成时核对generation_id、running、deadline、expected_revision、源指纹、完整历史指纹、回望正文以及认证/consent；成对INSERT、回望revision+1、operation成功同事务提交。

锁顺序继续为users KEY SHARE → lockUploadUser → 原始来源 → recap → operation → 专属conversation → messages。读取已成功operation元数据不另申请反向写锁；完成后更新的是已锁定的operation。模型期间不占事务或连接。

取消追问只结束该operation，不把ready回望改为cancelled，不删旧消息；失败同理。完成先提交则随后取消返回已完成冲突；取消先提交则迟到结果不可写入。断开请求通过AbortSignal进入同一围栏。

来源编辑使stale、删除使invalidated，沿用B22同事务清理正文、专属消息、反馈并撤销operation；删除回望也不允许迟到结果复活。原始来源追问新增造成集合变化，同样失效。

save与追问并发：save先提交递增revision，旧追问完成被拒并结束failed；追问先提交则旧revision的save返回冲突，需重新GET后保存。不静默覆盖较新版本。

成功历史不拆半组；测试在user INSERT后注入异常、在两条消息/成功状态SQL后但COMMIT前断开请求，均整笔回滚。取消/失败不持久化新的私人问题或半截回答，只保留操作状态与安全错误码。

过期running重放可标记interrupted，不接管或自动重发。新的请求遇到另一running操作拒绝；进程崩溃恢复仍须原request ID取消/过期收尾，没有新增后台worker。

## 7. 身份、隐私与兼容边界

- 发送、返回保存、读取历史均复核active、token_version、AI consent；本轮补充已验证JWT exp在事务时点的检查。未携带exp的既有内部合成principal仍兼容，HTTP只从已验证JWT取有效期，不相信正文声明。
- 单设备切换账号不会改变旧请求绑定的userId。服务器不能知道客户端尚未上报的A→B→A切换；后续Flutter必须继续按userId+sessionEpoch+origin拒绝旧异步展示/缓存写入。
- 服务器仍不知道本地pending修改、删除或未同步追问。响应继续local_pending_verified=false，不能宣称跨设备即时一致。
- 普通list/get/append/delete/create及last_message隔离保持；有真实专属消息后也不能从旧接口读取或注入。未来回滚不能回到缺乏专属隔离及B22失效钩子的老服务。
- 没有旧专属消息自动迁移/认领。存在不符合新封装的专属消息时安全拒绝，不能删除或覆盖它们。本阶段尚无真实专属数据发布。
- 历史完整性依赖MAC密钥和成功operation记录。以后密钥轮换、operation保留/清理政策必须同时支持历史校验；当前不执行轮换或自动清理。丢失校验密钥会导致拒绝读取，而不是跳过验证。
- HMAC不隐藏正文；消息仍沿用现有私有数据库存储。普通日志不输出正文、Prompt或凭证；用户反馈不加入本轮模型材料。

## 8. 本轮实际测试

以下为本轮重新执行，不将旧报告数字冒充新验证。

最终复跑日期为2026-10-27：下表最终后端、合成PostgreSQL与Flutter三组均已完成，包含加强后的HTTP撤销consent后取消测试。修改前219项仅为开发基线，不计入今天最终测试数量。

| 测试组 | 实际运行 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前后端离线基线 | 219 | 219 | 0 | 0 |
| 最终后端非PG回归 | 228 | 228 | 0 | 0 |
| 全新合成PostgreSQL | 164场景；含父测试165项 | 164场景/165项 | 0 | 0 |
| Flutter系统SQLite harness | 136 | 134 | 0 | 2既有 |

PG原116场景（B21 21、B22 26、B231 31、B232 38）全部重跑，新增48场景。新增覆盖ready/saved、14轮、预算、成对/独立问答、持久化重放、并发请求、取消/完成两种顺序、来源编辑/删除/原始追问变化/删回望、授权撤销/令牌版本/封禁/到期、跨owner/recap/非法客户端字段、历史内容/owner/来源篡改、半组/整组删除、事务失败、提交前断开、save竞态、孤立claim到期、预览到期、旧接口隔离以及本机HTTP链路。

新增两项可控事务barrier用pg_blocking_pids确认第二事务确实阻塞于第一事务，覆盖专属完成与来源删除的双向顺序；不是靠自然并发碰运气。模型等待期间来源变更能够独立完成，验证未持锁等网络。

新增真实loopback上游模拟，经过实际SSE传输器测试成功、缺DONE断流、挂起超时，各只有一次请求。专属HTTP测试使用合成认证主体并复核实际DB授权，覆盖POST/GET/取消和撤销consent后仍可取消；既有B232实际JWT/auth/consent/组合工厂及真实HTTP断开测试完整重跑。没有调用外部供应商。

9项新离线测试覆盖B1引用复用、引文voice/内容、历史AI不得单独成为证据、用户表达/推断区分、不完整/错版本/错快照、14轮及超限拒绝。

开发中新增夹具曾写入不合法账号状态disabled、构造超过4000字符的问题、遗漏B1要求的anchor/非null章节标题；按现有契约修正夹具后重跑。未削弱旧断言或改评测基准。最终没有新增已知失败。

Flutter仍为现有harness：sqflite factory、widget hit-test warning及2项skip保留；迁移失败测试输出SQL异常为故障注入。根项目SQLite native asset/历史BuildContext问题未改、不宣称解决。IAP/Obsidian为可运行的离线回归，不是外部Apple/正式同步服务验收。

### 复跑方式

从backend目录：

```powershell
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
node test-support/runRecapSynthetic.js "C:\Users\29319\AppData\Local\Temp\zhidu-recap-b233-tools-64e2e36f0b7b41bdbb0f8b24be0b00b1\package\native\bin"
```

从tool/reliable_upload_tests目录：`flutter test --no-pub --reporter expanded`。

运行器每次新建PGDATA/随机loopback端口/独立空库，核对data_directory和空public后才加载测试schema+010；不读部署dotenv，清除继承连接变量。测试结束停止新集群，保留日志和数据目录，不清理旧备份。复用的仅是PG二进制，不是旧业务库。

2026-10-27最终合成集群目录为 `C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-paSAi1`。运行器已停止该集群，另行确认 `postmaster.pid` 不存在。`git diff --check` 返回0，仅有既有CRLF提示；没有遗留本轮测试进程需要继续等待。

10月27日续接时，原临时PG工具目录已不存在，旧测试会话无法续读，首次复跑在工具路径检查处退出，未连接数据库。随后从npm官方registry重新下载同版 `@embedded-postgres/windows-x64@16.13.0-beta.16` 到新的独立临时目录，核对dist.integrity的SHA-512后解压；未安装项目依赖、未改lockfile，未更新Flutter。上方命令已更新工具路径。临时目录仍可能被系统或其他程序清理，不能作为长期备份承诺；重新测试应创建全新集群，不能初始化存量库。

## 9. 遗留风险与下一步

1. 本轮只有代码和自动化验证。真实模型的语义质量、真实设备取消/重连、多设备离线体验、真实负载和生产迁移均未验收。
2. 全历史保留会逐步触及16000输入预算；当前明确拒绝，不做自动摘要或隐藏裁剪。未来若要摘要，必须单独验证用户纠正/未决问题及证据不会丢失。
3. 各执行器实例的并发上限独立，生成和追问两个实例不是共享的全局配额；多进程也非全局并发控制。正式开放前需另审限流及容量，不能当成Pro额度系统。
4. 跨进程取消通过DB围栏禁止写入，AbortController只中止本实例网络等待；已发送供应商请求可能仍计费。没有供应商exactly-once承诺。
5. 复用执行器会采集本次usage/耗时，但本轮没有新增每轮持久化计费字段，也不覆盖原回望生成统计。追问费用审计尚未实现；不能将原回望统计冒充整个会话成本，正式计费前需另审存储方案。
6. history读取和逐段校验都在账号事务内，受上限保护，但未测生产p95/大量同时上传；现有来源锁高扇出风险继续保留。任意绕过应用锁的运维SQL不受并发原子性保证，异常读取会尽量失败关闭。
7. 凭证有效性是事务时点检查，与供应商发出请求不可能天然跨系统原子。已发送资料无法靠撤销consent收回；本地展示撤回还依赖后续客户端。
8. 专属历史的单轮删除/编辑、摘要压缩、逐轮成本留存、MAC轮换、操作清理、即时跨进程中止均没有新增入口；需要时另审，不通过清库解决。

建议B2.4先确认：本地pending与sessionEpoch检查、源范围确认、专属turn/answer渲染及证据跳转降级、请求ID重放和取消、revision冲突恢复、预算空状态、离线无正文占位、删除/失效时撤掉缓存。回望列表/独立证据读取等未交付接口还需明确边界，不能以当前GET历史替代完整产品UI。

本轮完成后停止，等待审核。不自动开发B2.4，不开放入口或部署。
