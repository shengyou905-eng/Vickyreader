# 知读小U P1-B1：单书回望证据与生成基础

日期：2026-10-20。范围：离线基础模块，不是已经上线的回望功能。

## 1. 产品契约

以用户确认的 P1 V1 为准，保留知识整理、我的思考、可选继续思考、证据追溯、追问、保存、删除与反馈。B1 只建立这些功能依赖的数据与验证基础，不用会话内结果替代正式交付的可靠保存。

- 单书身份是当前账号、API origin、稳定 bookId，不以书名合并版本。
- 不复制、覆盖、合并原始阅读历史。同一原文不同 trace ID、不同追问 ID 独立保留。
- 随心记包括已授权随心记均不读取；公开痕迹、无归属缓存、其他账号/书籍不进入快照。
- 未确认来源的原文片段保留为 `unverified_excerpt`，不进入模型材料，也不能成为有效引用。
- 不连接数据库服务或真实模型；未增加 HTTP 路由、UI、迁移、会员限制或同步入口。

## 2. 文件与实现

| 文件 | 作用 |
| --- | --- |
| `lib/services/xiaou_trace_snapshot.dart` | 原有 `read` 委托给 `readInTransaction`；新增可选 bookId 过滤，默认行为不变 |
| `lib/services/book_recap_evidence.dart` | 在一个事务中读取痕迹、待上传/删除状态、业务来源及追问，输出独立快照 |
| `backend/src/services/bookRecapContract.js` | Zod 严格输入/输出契约、稳定 ID/指纹、引用及来源有效性校验 |
| `backend/src/services/bookRecapGeneration.js` | 纯函数生成材料、Prompt、模型请求描述及范围/预算结果；没有执行网络请求的方法 |
| `test/services/book_recap_evidence_test.dart` | 合成 SQLite 与跨语言契约验证 |
| `tool/reliable_upload_tests/test/book_recap_evidence_test.dart` | 复用现有系统 SQLite 测试 harness |
| `backend/src/services/bookRecapContract.test.js` | 后端契约、引用、失效、预算与异常路径 |
| `tool/book_recap_eval/fixture.v1.json` | 新增自写英文合成材料，不修改 P0b 基准和真实回答 |

只有第一个文件是在既有实现上修改；其余为新增文件。未改现有控制器、路由、数据库 schema、Prompt 或 AI 配置。

## 3. 只读证据快照

调用方提供已经打开的数据库及捕获的 `AuthSessionScope`。模块不调用 `DatabaseService.database`，不初始化/迁移数据库、不访问网络、不发起重试。事务内执行查询，与本地 trace、追问、删除标记保持一致的已提交视图。

复用 `XiaouTraceSnapshot` 的本地优先、远端身份映射、pending delete、保留 tombstone、永久删书处理。远端缓存必须提供当前 origin，且逐行明确属于当前 user/book。该参数是内部调用边界，不是任意客户端可自行宣称可信的凭证。

- 远端旧 metadata 不补回本地已移除的阅读上下文。
- 同一 ID 的冲突记录拒绝处理，不以文本相同判重。
- 追问 local/remote 双份表示按明确 remote ID 合并；不同 ID 的同文追问不合并。
- 原有 `getUserEntryFollowUps` 会同步和写缓存，本模块不调用它。
- 追问只查询本次选中 trace 的身份及远端别名，分批控制 SQLite 参数数量；不读取其他书籍的追问正文。
- 旧 `ai_messages` 不具有稳定 trace 关联，本轮不根据同书或时间猜配。
- A→B→A 后，已捕获快照及排队中的读取仍失效。
- 所有内容为派生内存对象；`toJson` 返回副本，不修改输入记录。

### 来源分类

| kind | 可表示什么 | 不允许表示什么 |
| --- | --- | --- |
| `book_excerpt` | 匹配业务选区、保存的阅读上下文，或当前文档核对通过的片段 | 全书事实、作者观点已被独立证实 |
| `highlight` | 一次关注/划线行为 | 用户同意或持有该观点 |
| `user_note` / `user_question` | 用户明确保存的表达/问题 | 问过即认同、得到回答即已解决 |
| `historical_ai` / `ai_prompt` | 过去回答、小U主动问题 | 作者原文、用户立场、独立证据 |
| `unverified_excerpt` | 不能确认来源的旧字段 | 模型书籍材料或引用来源 |

`original_text` 本身不构成原文证明。`origin=xiaou_asks` 的开场问题属于 AI；未知 origin 隔离。不存在来源元数据的旧记录不会自动补写或认领。

可选 `RecapDocument` 由后续阅读器适配层提供：拥有者、bookId、文档版本、以 sourceIndex 为键的章节文本。模块不打开图书文件，不上传完整文档。没有匹配版本时不信任旧偏移；重复文字无法唯一确认时不输出精确位置。原书缺失时保留合法历史片段，不伪造跳转。

## 4. 数据契约

快照包含 `schemaVersion`、账号/环境/书籍范围、书籍元数据、`evidence`、`coverage`、SHA-256 `fingerprint`。

每条 evidence 有独立 ID、trace/追问 ID、来源字段、类型、文本、时间、provenance、锚点和待上传标识。指纹覆盖内容、来源、时间和范围变化。原始文本不截断、不改写；非法日期为 null，不补“现在”。

结果包含：

```text
schemaVersion + snapshotFingerprint
knowledge[]: concept / viewpoint / argument
relations[]: supports / conflicts / complements / compares / unconfirmed
myThinking[]
openQuestions[]
nextQuestions[]: 0..3
```

重要条目都要求 `evidenceRefs`、解释和 `basis`（原文支持 / 用户明确表达 / AI 推断）。直接引文另列 `quotes`，包含 evidenceId、原文及作者/用户/历史 AI 声音。

校验拒绝：其他快照引用、重复 ID、错误说话者、错配/伪造引文、用历史 AI 支撑书籍结论、用划线支撑用户立场、缺失关系端点及其依据、未完整结束的响应。全部数组允许为空，不填充假发现。

结果的成功校验必须显式提供 `completed=true` 且 `finishReason=stop`；JSON 恰好可解析不是成功依据。既有 SSE 协议不变，后续适配层须在完整流结束后调用。

SHA-256 不是签名，不证明客户端诚实，也不能证明语义正确。来源所有权最终仍须由服务端基于认证身份及原记录核对。

## 5. 覆盖与预算

`coverage` 由读取过程计算，注明 `basis=reading_traces`、`fullBook=false`、当前可用/选中痕迹数、追问数、隔离数量及是否显式选择子集。来源完整性固定标记为“本地与调用方提供的缓存”，绝不称为完整云端历史。

生成准备返回 `ready` / `insufficient_evidence` / `scope_too_large`，并报告实际发送的证据类型数量和排除的未确认片段数。

- 单次最多 80 条选中 trace、320 条发送证据。
- 输入估算上限 16,000；使用完整请求 JSON 的 UTF-8 字节数加 1,024 envelope 余量，保守估算，不是实测 Token。
- 输出 `max_tokens=3000`；每次生成最多一个请求，自动重试为零。这是待接入执行器必须遵守的契约，B1 无执行器。
- 超限不返回请求、不偷偷截断；后续 UI 需请求用户缩小范围。自动分批、多次汇总尚未实现，不能宣称已经覆盖长书。
- 模型必须由调用方显式提供，不修改当前模型配置。
- 未配置价格时费用为 null；可用显式费率和价格版本计算估算，不使用真实价格硬编码，不宣称计费上限已得到供应商保证。
- 材料不包含账号、API origin、文件路径、认证信息或原始 metadata。完整图书不在请求中。

未来上线前必须验证所选模型 tokenizer、实际 usage、执行次数和并发限制。真实账单 Token 缺失应为未知，不能用估算伪装实测。

## 6. 删除与失效

- 删除回望：B2 处理派生结果，不影响原始历史。
- 原始记录修改/新增追问：新旧快照指纹不同，`assessFreshness` 返回 stale，旧结果不获展示许可。
- 原始记录删除/依据不可用：快照去除证据，旧结果不获展示许可；永久删书直接拒绝生成快照。
- 本地原书缺失：不等于删除阅读记录。如果除定位可用性外，所有仍归属当前账号的证据均一致，返回 `location_unavailable` 并允许展示；同时发生内容修改、来源删除或换版本则仍拒绝旧结果。

必须在发送、保存和再次展示前获取当前有效快照或服务端有效性证明。离线设备无法知道别处刚发生的删除；B1 不声称解决跨设备撤回，B2 设计必须处理这一边界。

## 7. 离线验证

实施前基线：
- 后端非 PostgreSQL 测试：173 通过。
- 现有 Flutter 系统 SQLite harness：118 通过、2 跳过。
- 既有键盘 hit-test warning 保留；不为全绿更改根项目 SQLite/native asset 配置。

本轮新增测试包含：同名不同 ID、A/B 同 bookId、独立同文历史、追问别名、未知归属、私密内容排除、本地新内容优先、pending/tombstone/永久删书、原文分类、重导入/重复句子、文件缺失、来源修改、A→B→A 排队竞态、超限与空结果。

SQLite 只读测试比较导出前后 `total_changes()`、pending queue、DB/WAL 字节。所有写入仅用于系统临时目录中的合成夹具；真实用户数据库从未打开。

Flutter→Node 测试把真实 Dart 快照交给后端 Zod/指纹校验，防止只有两端各自通过却协议不一致。

复跑命令：

```powershell
# 仓库根目录
node --test backend/src/services/bookRecapContract.test.js
dart analyze lib/services/book_recap_evidence.dart lib/services/xiaou_trace_snapshot.dart test/services/book_recap_evidence_test.dart

# tool/reliable_upload_tests
flutter test --no-pub
```

最终回归：

| 检查 | 结果 |
| --- | --- |
| 后端全部非 PostgreSQL 测试 | 193 通过，0 失败（基线 173，新增 20） |
| Flutter 系统 SQLite harness | 134 通过，2 既有跳过，0 失败（基线 118，新增 16） |
| 本次三份 Dart 源码/测试静态检查 | No issues found |

后端回归包括现有 P0a/P0b、Reliable Upload、Obsidian 与 IAP 的离线测试；不代表真实 Apple/PostgreSQL 联调已复测。Flutter 仍使用既有 harness，未改根项目 native asset 配置。既有 sqflite factory、键盘 hit-test 警告保留；迁移失败回滚用例中的 SQL 错误是预期注入，不是本轮测试失败。

未运行真实 PostgreSQL、真机、付费模型或发布构建；离线测试不证明生成内容具备真实认知价值，也不能自动判断解释是否被证据蕴含。

## 8. 下一阶段

B2 尚未开始。先审查 `docs/zhidu-xiaou-p1-b2-storage-proposal.md`，确认持久化、尚未同步的来源及离线再次查看策略后，再编写迁移和实现保存。不得擅自缩减保存/删除/反馈需求。
