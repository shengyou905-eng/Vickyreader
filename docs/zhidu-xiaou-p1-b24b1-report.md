# 知读小U P1-B2.4b-1：服务端展示接口与安全协议

日期：2026-10-27。交付范围：未挂载的服务端展示适配器、严格契约、正式来源复核和合成测试。不是页面完成、真机验收或上线。

## 1. 结论与边界

已实现账号私有无正文历史列表、两步恢复、授权证据查看、fragment_only 定位降级，以及在线展示窗口协议。复用 B231 正式 resolver、B22 原事务锁与失效钩子、现有认证和 AI consent 校验。没有增加数据库表、索引、迁移或第二套阅读历史。

旧 HTTP adapter、旧响应 DTO、Flutter 业务代码全部保持不变。新增接口在独立 adapter 内，app.js 未引用/挂载；原关闭 router 仍返回503，readEnabled/generationEnabled仍为false。没有修改部署配置、密钥或正式路由可用状态。

所有数据来自本轮新建的隔离 PostgreSQL 集群和原有合成 SQLite harness。没有访问真实用户/业务库，没有调用付费模型，没有部署、构建发布、TestFlight、commit、push、reset、clean或备份清理。本轮测试中的模型仅为注入的确定性函数，其他既有传输回归只访问loopback模拟服务。

## 2. 实际文件清单

“新增/修改”以本轮开始的工作区为准，不以整个脏 Git diff 冒认本轮成果。

| 文件 | 本轮变化 |
| --- | --- |
| backend/src/services/bookRecapDisplayContract.js | 新增：列表、范围、证据、版本、展示许可严格DTO |
| backend/src/repositories/bookRecapDisplay.repository.js | 新增：只选择摘要字段的有界keyset列表查询 |
| backend/src/services/bookRecapDisplay.service.js | 新增：账号授权、游标、正式resolver复核、证据投影、展示窗口 |
| backend/src/routes/bookRecapDisplayHttpAdapter.js | 新增：独立未挂载HTTP adapter及显式服务端组合工厂 |
| backend/src/services/bookRecapDisplayContract.test.js | 新增：6项纯契约测试 |
| backend/test-support/bookRecapB24b1Scenarios.js | 新增：25项合成PG/HTTP/并发场景 |
| backend/src/repositories/bookRecap.postgres.test.js | 仅增加新场景模块的一行注册；保留全部既有断言 |
| docs/zhidu-xiaou-p1-b24b1-report.md | 新增：本报告 |

开工记录268个既有已修改/未跟踪文件的SHA-256，排除artifacts和node_modules；复核仅上述测试注册文件变化，无丢失。此清单是限定范围的内容核对，不是重新制作完整可恢复备份。没有触碰原有备份、执行锁和真实评测回答。IAP、Obsidian、五种模式、原始写入口、migration010及Flutter文件均未修改。

## 3. HTTP契约

新增适配器未来建议挂在 `/api/xiaou/recaps/display`，**当前没有此线上路径**。合成HTTP测试只挂在本机 `/display`。使用POST传递有界查询/版本条件，避免长证据ID或来源指纹出现在URL日志；这些接口不生成模型结果、不保存用户正文。

| 相对路径 | 严格请求 | 响应 |
| --- | --- | --- |
| POST /history | limit可选1–50，默认20；filter为all/saved/preview，默认all；cursor可选 | items、next_cursor、contains_private_body=false、snapshot_consistent=false |
| POST /:id/scope | 空对象 | 旧响应中除result外的字段，加evidence_catalog、requires_local_confirmation=true；无正文 |
| POST /:id/view | book_id、expected_revision、expected_source_fingerprint | recap为原B24a完整响应；display为新的展示许可 |
| POST /:id/evidence | 上述版本字段加1–24个不重复evidence_ids | evidence白名单数组、display |
| POST /:id/validate | 与view相同 | 只有display；同样在线重读全部授权来源，不以单一hash代替复核 |

来源范围不允许在这些请求中扩展。拒绝额外user_id、result、snapshot、metadata、来源证明、local_pending_verified及query参数。scope只恢复已存在且有效的ready回望，不是prepare或自动生成。prepared/generating等状态可在列表看到，既有状态查询/取消/重放仍走旧协议。

身份来自现有auth产生的req.user与req.authUser一致主体，不从body取用户ID。服务内再检查active、token_version、已验证JWT有效期和当前AI consent版本，输出前再次检查。列表、范围和正文均需要授权；已有取消/删除接口仍可在撤销AI consent后用于隐私清理，没有改其行为。

所有响应设置 `Cache-Control: no-store, private` 和 `Pragma: no-cache`；拒绝非法JSON、超16KiB请求、非法UUID/版本/证据ID。HTTP错误只返回error_code，不返回SQL、Zod字段详情、私人内容或堆栈。

错误示例：401登录/令牌/封禁；428需重新授权；404无所属回望/未授权证据；409来源变化、版本不支持或窗口耗尽；410删除/失效/预览过期；412bookId/revision/fingerprint不符；503未提供展示策略。客户端应映射中文提示，不直接展示技术字段。

## 4. 私有列表与恢复

列表字段：id、book_id（清理后null）、revision、state、is_saved、created_at、updated_at、expires_at和availability。没有书名、问题、原文、结果摘要、模型参数、依赖快照、普通对话或用户ID。

排序采用不可变的created_at降序、UUID降序，保留PostgreSQL微秒，不使用会随保存/追问变化的updated_at排序。第一页记录时间上界，后续使用keyset而非offset。游标签名绑定账号、origin、filter、limit、上界、最后位置和到期时间；篡改、跨账号/origin、改分页参数或过期均拒绝。游标不是登录凭证，不包含正文，也不能替代每次认证。

分页期间状态和saved属性仍可能变化，明确 `snapshot_consistent=false`，不声称跨请求数据库快照一致性。固定排序避免普通编辑导致条目重排；过滤条件变化仍可能使某项离开/进入该筛选，应允许用户重新刷新第一页。新插入条目晚于上界时不混进当前页序列。新一轮完整刷新才能看到它们。

is_saved是独立属性，不增加虚构的saved state。ready只标 `requires_online_verification`，不是永久有效证明；列表不逐项解析来源。未保存且已超期的记录显示expired，其余非ready状态显示unavailable。deleted/invalidated仅显示清理后留下的最小元数据，不恢复书籍或原文。没有在列表请求里顺手执行过期清理。

恢复流程：

1. history选择账号所属ID；不读取缓存正文。
2. scope在线核验来源，返回稳定bookId、明确的entry/follow-up范围、覆盖信息和无正文证据目录。
3. 客户端核对会话、origin、本地pending/tombstone/永久删书围栏，并让用户确认范围。服务器返回的local_pending_verified始终为false。
4. view携带刚确认的bookId/revision/fingerprint，服务端重新解析；变化则412/409，不能静默使用新版范围替换用户刚确认的旧范围。
5. 私人正文仅在展示许可与本地校验均有效时显示；再次打开必须重新在线核验。

云端恢复不要求设备存在完整EPUB/TXT或user_library_books行，不按同名书猜配，不自动下载、上传或合并阅读记录。当前B24a本地guard仍要求本地明确映射，因此**现有Flutter尚不能直接使用“云端记录存在但本机缺记录”的恢复分支**，见第8节；这不是已完成跨设备真机闭环。

## 5. 证据、分类与定位

每次scope/view/evidence/validate调用均在原账号锁内执行repo.find（先锁原来源，再锁recap），调用正式resolver.revalidate核对全部已授权输入依赖，不仅核对结果中引用的证据。再次验证B1快照、结果结构、直接引文及引用关系，要求当前schema/prompt版本与server_selected_records来源契约。

证据DTO仅包含：id、entry_id、follow_up_id、kind、provenance、text、location。客户端只能提交本回望目录中的evidence ID；不能指定其他entry/follow-up来扩大范围。最大24条/次、256KiB响应，超限拒绝，不静默截断。最多320条目录与B1材料上限一致。

| 分类 | 可信边界 |
| --- | --- |
| book_excerpt / reader_context | 当前账号记录中保存的阅读上下文，不是原书逐字真实性认证 |
| highlight / trace | 用户关注的划线或摘录，不推定赞同 |
| user_note、user_question / trace或follow_up | 用户留下的表达/问题，不等于作者观点 |
| historical_ai / trace或follow_up | 历史AI，绝不提升为书籍事实 |
| ai_prompt / ai_prompt | AI开场或提示，不是用户原始观点 |
| unverified_excerpt | 不在可展示授权证据目录中；不作为可信引用返回 |

不会返回sourceField、原始metadata、内部完整snapshot、数据库行或依赖MAC。随心记及普通聊天不查询；伪造metadata不能提升provenance。书名、作者不从可变书架header加入派生依据。

location始终为fragment_only、exact=false，仅有记录中的chapter_index/chapter_title提示。没有伪造start/end、documentVersion、文件路径或精确跳转。即便本机找到同名书，也不能自行把这些提示升级为确定位置。需要未来可靠锚点及版本证据后才能另行扩展。

## 6. 展示有效性与撤回

展示服务要求显式 `displayPolicy={version, windowMs}`。没有生产默认值；缺失时正文/证据/validate返回503，元数据列表和scope仍可用。实现的1–120000ms仅为技术校验边界，不代表批准使用120秒。测试显式用2000ms，**不是产品政策**。cursorLifetimeMs也由组合方显式提供，测试60000ms。

display包含protocol_version、policy_version、recap_id、book_id、revision、source_fingerprint、checked_at、expires_at、max_age_ms、local_pending_verified=false、requires_online_on_open=true。

这是服务端成功在线核验的响应元数据，不是可重放的Bearer凭证；API不接受客户端拿display当授权。有效期受请求开始时刻+配置窗口、JWT截止时间、未保存预览截止时间三者最早值限制。锁等待和服务器处理消耗窗口，不延长窗口。事务结束后若已到期，拒绝返回私人正文。

客户端必须遵守：

- 本机许可截止取服务端许可与本机安全策略的较早值；用单调计时扣除从请求发出到收到响应的全部耗时，不简单从收包时再加windowMs。墙钟明显异常时拒绝或重新核验，不能延长许可。
- userId/sessionEpoch/origin/bookId/revision/fingerprint与请求发起时全部一致才可接收/展示；A→B→A的旧响应仍无效。
- 离开页面、进入后台、断网、退出/切账号、授权撤销通知、本地来源变动、412/409/410等均主动清除临时正文及证据对象。再次打开只显示占位，重新在线取view。
- 当前屏幕仍持有匹配版本的临时对象时，可以在用户需要继续查看时调用validate续核。对象已经撤回/离线/换会话后，不允许仅凭validate重新启用旧磁盘正文，必须重新view。
- 不持久化私人正文/证据到普通缓存，不把一次成功GET或history条目当永久展示许可。专属追问正文同样需要匹配revision/fingerprint的展示许可；旧follow-ups接口读取后需再次validate，不允许直接永久缓存。
- 不内置定时轮询；到期只撤回，续看由显式刷新/重新进入触发。是否采用受控前台续核及具体窗口长度，需要产品与性能评估后确认。

来源编辑变stale、删除变invalidated、回望删除变deleted，B22清理正文/会话/反馈/操作并递增revision。新接口不改变这些写入，只读取其结果。绕过钩子的异常SQL修改仍会因resolver指纹不同而拒绝，不回退旧快照。

并发语义：读取先取得账号锁时可返回当时合法内容，随后删除成功；删除先取得锁时读取拒绝。测试使用barrier及pg_blocking_pids证明两种事务先后关系。已经发送的响应无法远程收回；其他设备发生变更后的陈旧展示最多受剩余窗口约束，前提是客户端正确实现上述撤回。不声称跨设备即时撤回，也不能防止恶意客户端截图或自行留存曾授权的内容。

授权在查询中途变化时，末次授权检查会拒绝；末次检查后极小的提交/传输竞态同样属于有界窗口，而非即时撤销保证。

## 7. 查询成本与性能边界

本轮一个合成trace、单次本机测量（不是生产p95）：history 6次SQL/4.27ms；scope 14次/13.86ms；view 14次/12.72ms；evidence 14次/12.86ms；validate 14次/10.98ms。计数为harness的tx查询回调，不含驱动BEGIN/COMMIT。没有模型调用费用。

validate省下正文传输，但仍解析全部授权来源，数据库成本并不等于一次轻量HEAD。应按需调用，不能为方便UI无条件高频轮询。若未来每W秒为N个活跃屏幕续核，请求量约60N/W次每分钟；尚未批准W或测试并发生产容量。

历史查询有界返回50条，但010现有索引不是完整的(user_id,created_at,id)排序索引，大账号可能仍需扫描/排序其候选记录。本轮没有擅自增加索引或修改迁移；正式开启前应在合成大规模数据上EXPLAIN/压测，若确需索引，单独提交兼容迁移审批。

复用账号级锁保证与删除一致，会与同账号同步写入竞争。所有查询期间无外网/模型等待；最多80条来源、320份证据沿用B1预算。未来可以评估合并查询，但不能跳过归属、来源复核或改变锁顺序。列表锁复用会执行原lockUploadUser的初始化/upsert语句，不是字面上的纯SELECT事务；测试证明已有同步序号未被推进、原始阅读行未被修改。

## 8. Flutter兼容与集成依赖

旧接口、取消/删除/重放、request ID和saved属性不变。新view的recap字段通过原bookRecapHttpContract.response校验；整个新wrapper故意不能被旧严格DTO当旧响应直接接收。合成PG测试验证实际生成的响应，既有Dart/Node契约测试及完整Flutter harness复跑通过。**未做真实JWT+PostgreSQL+Flutter页面端到端联调。**

下阶段须单独实施以下必要客户端适配，不能直接开放现有B24a控制器：

1. book_recap_client_contract.dart增加history、scope、evidence和display wrapper DTO，保留旧DTO；新状态只在列表展示，不把is_saved改为state。
2. book_recap_client_api.dart只增白名单的新路径；不要更改已有写请求格式，不自动重试、下载、上传或自动重新生成。
3. book_recap_controller.dart将本机displayLifetime与服务端剩余许可取最小值，接入单调计时、到期撤回、后台/网络/授权变化事件。现有控制器只有本机TTL，不理解新的服务端许可，不能冒称已完成这一部分。
4. book_recap_local_guard.dart评估严格的“云端所选记录恢复”分支：检查当前账号下所有相关book/remote ID的pending、tombstone和永久删书围栏；本机缺记录不等于云端不存在，也不等于本机不存在待删除意图。无法核验时只显示占位。不能按书名或文本猜配，也不能自动导入整份历史来绕过检查。
5. 本机内容指纹不等于服务端source_fingerprint；来源范围确认需同时保持本机前后证明和服务端版本，显式展示云端所选材料范围。服务器仍看不到尚未上报的本机编辑/删除，local_pending_verified=false不能忽略。
6. 列表无正文元数据按userId/sessionEpoch/origin隔离；退出/换账号清除。无有效在线许可时不显示私人书名、问题、引文或摘要。证据DTO的kind/provenance映射成人类可读标签，不展示内部字段作为文案。
7. 保存/追问会推进revision，旧许可立即作废；完成后重新读取。专属历史仍用原B233校验接口并与新许可匹配。普通聊天接口不复用、不降级回退。

旧GET仍按B232契约可含正文但没有新display字段，本轮为兼容没有改它；它不能单独作为新正式页面的展示授权。后续挂载与客户端接入必须成套审查，不能把关闭中的旧adapter直接上线当成完整新协议。

## 9. 本轮实际测试

| 测试组 | 实际计数 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 后端非PG全量回归 | 234 | 234 | 0 | 0 |
| 其中新增纯契约 | 6 | 6 | 0 | 0 |
| 全新合成PG完整套件 | 190 | 190 | 0 | 0 |
| 其中新增B24b1场景 | 25 | 25 | 0 | 0 |
| Flutter完整SQLite harness | 179 | 177 | 0 | 2既有 |

PG的190包含189个子场景和1个父测试；此前164个子场景是本轮真实重跑，不是直接引用旧报告。新增25个覆盖微秒分页、账号/游标隔离、saved/preview/expired及全部非ready状态、两步无正文恢复、旧DTO兼容、分类/定位、跨书/错误revision/伪造证据、编辑/删除/失效、缺依赖/旧版本、授权/封禁/token、查询途中撤权、展示策略/到期、无本地书籍、未选记录/私密来源/普通聊天排除、分页变动、原数据/游标完整性、查询计数、双向删除并发及loopback HTTP。

首次PG运行3个新增场景失败，原因分别是测试误用updateImportance函数名、deleted账号状态值和user_books表名；实际代码为updateEntryImportance、banned和user_library_books。修正合成测试调用后再全量复跑通过，未更改旧断言、schema或业务验证来制造通过。最终新增25项全部通过。

Flutter仍有既有sqflite factory/hit-test警告、故障注入SQL日志和2项跳过；根工程SQLite asset-loading及此前BuildContext warning未处理，不宣称已经修好。PG保留原测试注入引起的配置循环依赖警告，不包含真实凭证。git diff --check退出0，原CRLF提示不作为新增失败。

最终PG集群：`C:\Users\29319\AppData\Local\Temp\zhidu-recap-b21-ktJF5t`。runner创建全新PGDATA、核验实际data_directory、清除业务DB环境变量，只连接127.0.0.1的新随机端口；只在新合成库应用schema/010。完成后已停止该集群并保留日志/目录，不清理旧集群或备份。

### 可复跑

backend目录：

```powershell
node --test src/services/bookRecapDisplayContract.test.js
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
node test-support/runRecapSynthetic.js <PostgreSQL-bin目录>
```

runner只接受二进制目录，不接受现有业务库URL或旧PGDATA；每次新建合成集群。不得改成线上数据库连接串。

tool/reliable_upload_tests目录：

```powershell
flutter test --no-pub --reporter compact
```

## 10. 风险与下一阶段前置条件

- 明确审批生产展示窗口、游标期限、前台刷新体验和挂载方案；当前无生产默认值、无配置变更。
- 按第8节完成DTO、许可撤回、本地变更通知、云端范围恢复与会话生命周期适配，然后才能开发/验收正式页面。
- 大规模历史分页、最大证据范围、多设备压力和弱网真实设备延迟尚未验证；可能需要独立索引审批、限流和超时策略。
- 当前返回fragment_only，不提供精确跳转保证；缺本地书只可查看获授权的记录片段。不能把云端归属核验当作原书认证。
- 不提供即时跨设备撤回、后台推送、完整离线回看、跨进程命令恢复或自动删除队列。保留此前明确的产品边界，不暗中补上传或自动重新认领。
- 正式回滚不得退回不隔离专属会话的旧服务版本。schema010及所有隐私失效钩子保持原样，不提供破坏数据的回退脚本。
- 未运行真实模型、Apple、真机、正式JWT网关联调或线上验收。代码与合成验证通过不等于产品已上线。

本轮停在B2.4b-1，不进入B2.4b-2页面或B2.4c轻提示。等待审核。
