# 知读小U P1-B2.4b-2：Flutter 客户端集成与回望页面

日期：2026-10-28。

## 1. 结论与交付边界

已完成本阶段 Flutter 协议、控制器、只读材料目录、来源变更通知和可显式注入的完整回望页面，并执行模拟 HTTP、隔离 SQLite、真实 Flutter Widget 与既有合成 PostgreSQL 回归。

**代码实现与自动化验证不等于真实联调或上线。** 正式小U入口默认关闭：`XiaouHomeScreen.recapEntryBuilder` 默认 null，现有应用调用方没有注入。服务端展示适配器仍未挂载；本轮没有改变生产路由可用状态。没有设定生产展示时长、自动轮询或自动生成规则。

本轮没有连接真实用户/业务数据库，没有调用付费模型，没有修改数据库结构或迁移，没有构建发布、部署、TestFlight、commit、push、reset、clean，也没有清理备份。没有推进 B2.4c。

## 2. 实际文件清单

以下按本轮工作内容列举，不把整个脏 Git diff 归为本轮成果。工作区保留大量前阶段未提交文件；部分“修改”文件在 Git 中仍显示 untracked，因为其基础版本也尚未提交。没有重新制作或宣称完成全工作区逐文件 SHA 对照备份。

| 文件 | 本轮内容 |
| --- | --- |
| lib/services/book_recap_display_contract.dart | 新增：history/scope/view/evidence/validate 严格 DTO、展示许可与期限计算 |
| lib/services/book_recap_display_repository.dart | 新增：会话绑定的无正文历史、范围恢复、隐私删除 |
| lib/services/book_recap_material_catalog.dart | 新增：按账号及稳定 ID 读取材料、追问选择、跨设备恢复安全检查 |
| lib/services/reading_source_changes.dart | 新增：提交后无正文来源变更通知、事务包装 |
| lib/screens/xiaou/book_recap_screen.dart | 新增：显式测试组合、入口组件及完整回望工作流页面 |
| lib/providers/book_recap_controller.dart | 修改：正式展示许可、证据、续核、专属追问展示、撤回和恢复版本绑定 |
| lib/services/book_recap_client_api.dart | 修改：允许真实展示 adapter 的相对路径，保留原认证与传输约束 |
| lib/services/book_recap_client_contract.dart | 修改：无正文 scope 解析和中文错误映射，保留旧响应解析 |
| lib/services/privacy_service.dart | 修改：AI consent 撤回通知及捕获原账号的缓存更新 |
| lib/screens/xiaou/xiaou_home_screen.dart | 修改：仅增加默认关闭的可注入回望入口插槽 |
| lib/services/book_service.dart | 修改：现有来源/书籍写入在提交后发出通知 |
| lib/services/reliable_upload_service.dart | 修改：已有匿名归属、上传 ACK、待删除/重试写入后通知 |
| lib/services/sync_service.dart | 修改：已有阅读痕迹落库及归属事务提交后通知 |
| lib/services/database_service.dart | 修改：数据库成功初始化后通知，不更改 schema |
| test/services/book_recap_display_contract_test.dart | 新增：53 项契约测试 |
| test/services/book_recap_display_controller_test.dart | 新增：12 项控制器测试 |
| test/services/book_recap_material_catalog_test.dart | 新增：41 项材料与归属测试 |
| test/services/reading_source_changes_test.dart | 新增：34 项通知、失败及写入口接线测试 |
| test/screens/book_recap_screen_test.dart | 新增：13 项真实 Widget 流程测试 |
| test/screens/book_recap_visual_test.dart | 新增：1 项真实组件渲染及像素检查 |
| test/support/recap_display_fixture.dart | 新增：隔离 SQLite 与 MockClient 合成夹具 |
| test/services/book_recap_client_test.dart | 修改：适配正式许可测试夹具、时钟与明确新增请求次数；保留 43 项既有断言目标 |
| tool/reliable_upload_tests/test/ | 新增上述六个测试文件的 harness 转发入口 |
| docs/zhidu-xiaou-p1-b24b2-report.md | 新增：本报告 |

本轮没有修改后端业务实现。书籍服务中名称涉及明台的既有写入，本轮只在其已存在的关联阅读记录/重要性事务提交后通知，不改变分享、可见性或原始写入权限。没有修改 IAP、Pro、Obsidian、随心记规则或五种模式 Prompt。

## 3. 接口与控制器适配

基于已配置的回望 API base，使用以下真实相对契约，不假定这些接口已经在线上可访问：

| 操作 | 路径及输入 | 客户端处理 |
| --- | --- | --- |
| 历史 | POST display/history；limit/filter/cursor | 有界分页；只保留无正文元数据；区分 state 与 is_saved |
| 恢复范围 | POST display/:id/scope；空对象 | 读取无正文来源目录，必须重新检查本地选择并确认 |
| 正文 | POST display/:id/view；book_id、expected_revision、expected_source_fingerprint | 校验 recap 与 display；没有许可不展示 |
| 证据 | POST display/:id/evidence；版本字段及 evidence_ids | 严格核对已授权目录、请求集合、类型和 fragment_only 定位 |
| 续核 | POST display/:id/validate；版本字段 | 只在仍有效的展示周期内按需续核；不以旧缓存降级 |

prepare、generate、旧状态 GET、save、follow-ups、cancel、feedback、delete 继续使用既有协议。旧 GET 即使返回 result，也只能更新状态，不能单独授予展示许可。旧 `RecapHeader.parse` 仍要求相应完整字段；新增 `fromScope` 不放宽旧协议。

许可核对 policy_version、recap_id、book_id、revision、source_fingerprint、有效时间，以及在线重新打开和 local_pending_verified 标志。未知策略、额外字段、非法时间或不匹配来源拒绝。`local_pending_verified=false` 明确表示服务器没有证明本地无待同步变化，客户端仍必须执行 guard。

复用 userId + sessionEpoch + origin 会话身份。请求发送、返回、本地复核及展示写入均检查原会话；恢复时绑定服务器给出的 revision/fingerprint，不凭书名重配。

## 4. 页面与实际交互

采用一个工作流内的分步页面，复用现有主题，不新增底部 Tab：

1. 小U入口组件：主动选书与历史入口；只在显式注入时出现。
2. 材料选择：按类型查看、独立勾选、长原文预览及展开/收起；不同阅读行为不合并；追问区分全部、空选择与明确子集。不可用材料显示待同步/来源问题。
3. 范围确认：显示实际服务端确认范围与覆盖限制，授权后才生成，不自动扩大选择。
4. 生成与详情：等待、取消、错误和请求重放；纵向呈现知识整理、我的思考及可选继续思考；关系与推断使用读者可理解的标记。
5. 证据：按授权引用查看片段、章节提示及来源类型；返回详情。当前不伪装精准阅读跳转。
6. 专属追问：有序展示独立问答、发送/等待/取消/异常；不调用普通小U会话。
7. 我的回望：分页、保存/临时预览标记、失效提示、重新确认、删除及刷新。书名只通过本机同 bookId 信息关联，缺失时使用占位。
8. 保存、删除和私有反馈均接实际数据层行为；反馈不发送模型供应商。

空材料、证据不足、超限、断网、授权失效、版本冲突和预览过期使用中文状态，不向读者展示 SQL、HMAC、DTO 或模型堆栈。

AI consent 弹层覆盖页面时按隐私策略撤回既有材料；用户接受后需要重新选择/确认，不能静默使用弹层打开前捕获的私人材料继续请求。此行为已有 Widget 测试。

## 5. 本地来源、会话与缓存

材料目录只读现有记录，排除随心记、不支持/归属不明及不合法来源。检查本地 pending、tombstone、永久删书围栏、远端身份和父子关系，不触发上传。相同书名或相似原文不用于身份归并。

读取有明确上限：书籍目录 200、本地书籍扫描 4000、材料 320、单记录追问 640、总追问 2560、聚合文本 512 KiB。超限拒绝，不静默缩减用户范围。模型预算仍沿用原契约。

跨设备恢复流程为 scope → 精确本地来源映射 → guard → 用户确认 → view。本机缺少必要记录时保留明确占位，不隐式下载、上传或合并历史；仍可删除自己账号的回望，不要求先恢复私人正文。

来源通知不包含私人正文，发生在成功写入或最外层事务提交之后。BookService 本轮接入 18 处现有事务，涵盖书籍更新/移除/永久删除、划线想法、阅读痕迹、追问新增和 ACK、远端拉取及相关重要性写入；Reliable Upload 和 SyncService 落库也通知。事务失败不发出已提交信号。普通书架移除或阅读进度写入可能撤回临时展示，但不删除回望或原始记录。

当前通知是保守的进程级撤回：可能因为其他书或无内容变化的写入而要求重新核验。这是隐私优先的可用性成本，尚未做精细逐书过滤。未改变同步游标、上传协议或删除围栏。

正文、授权证据、专属追问只通过可撤回的 controller handle 临时读取，不写入普通持久缓存；Widget 不另存可绕过撤回的正文副本。材料、书名及输入草稿在会话/生命周期失效时也清除。

## 6. 展示生命周期与请求成本

页面离开或被其他路由覆盖、App inactive/后台、明确断网、退出/换账号、AI consent 撤销、本地来源变化、许可过期，均撤回正文和证据并取消相关在途操作。迟到结果不能恢复旧会话内容。

展示期限取服务器许可与显式客户端上限较早值。采用单调时间，包含发送、网络等待和最终本地复核消耗；同时尊重服务器墙钟截止时间，时钟异常时安全拒绝。续核返回后再次检查原许可是否已经失效，不能利用慢响应复活已撤回正文。

没有生产时长默认值。测试使用显式测试策略；服务端技术上限不是产品审批。`BookRecapWorkspace` 要求明确提供展示上限、批准策略、网络状态、RouteObserver 和 consentGate。

没有无条件定时轮询。用户主动续看时可 validate；许可到期后需重新在线 view，失败仅占位。当前正文重新打开通常是状态 GET + view 两次请求；追问展示包括状态、专属消息与 validate 三次请求；手动续核一次。每次服务端核验会复核授权来源，不能将其视为无成本心跳。

**跨设备变化不是即时推送撤回。** 最迟在下一次有效检查或当前短暂许可结束时检测；生产窗口、成本和可接受延迟仍待审批。断网识别依赖注入的连接状态和请求失败，真实系统网络回调与后台帧时机尚需真机验证。

## 7. 实际测试结果

以下是本轮实际执行，不复用历史报告数字：

| 验证 | 实际总数 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 最终 Flutter 合成 harness | 333 | 331 | 0 | 2 |
| 其中本轮新增测试 | 154 | 154 | 0 | 0 |
| 后端离线回归 | 234 | 234 | 0 | 0 |
| 全新合成 PostgreSQL 回归 | 190 | 190 | 0 | 0 |

PostgreSQL 190 为 189 子场景加 1 父测试，不能当作 190 个独立业务场景。本轮未新增后端场景，重新执行了 B2.1—B2.4b-1 回归。新集群位于系统 Temp 的 `zhidu-recap-b21-BsnCEx`，runner 校验实际数据目录、使用 loopback 随机端口并在结束后停止；未使用既有业务库。保留合成数据及日志，没有清理旧集群/备份。

Flutter 分项：ai_account_isolation 16、auth_session_race 10、book_recap_client 43、display_contract 53、display_controller 12、book_recap_evidence 16、material_catalog 41、screen 13、visual 1、local_diagnostics_mode 4（2 既有跳过）、local_sync_diagnostics 9、P0a 24、reading_quality 4、reading_source_changes 34、reliable_upload 27、xiaou_auth_failure 6、xiaou_trace_snapshot 20。

两项既有条件跳过为诊断 evidence mode 的拒绝业务写入、以及启动/前台/定时器/导出分享不改变 DB/WAL/账号测试；没有为本轮隐藏新增失败。

真实 Widget 与 MockClient/隔离 SQLite 覆盖生成、追问、保存、历史恢复、证据、删除、分页、长文本、小屏、撤回和授权流程。通知测试组合了 fake DB 失败注入及源码接线检查，不能把全部 34 项都称作真实 SQLite 事务执行。后端离线和 PG 与 Flutter 模拟套件分别运行，不代表已完成 Flutter 到真实服务端的完整网络联调。

### 中途失败与残余稳定性风险

早期夹具出现展示请求计数/时间匹配、Widget 生命周期 await void、证据目录数量、滚动目标和 fakeAsync 等待错误，修正夹具/测试驱动后通过，没有放宽生产校验或既有评测标准。

第一次全量 Flutter 曾出现 **328 通过、1 失败、2 跳过**，输出被截断，未保留下该项失败的名称及根因。这一点仍未解释，不能宣称已消除所有不稳定性。随后默认并发全量运行分别为 329/0/2、补齐最后两项测试后 331/0/2；最终单并发复跑再次为 331/0/2。建议后续 CI 保存完整结构化事件并重复运行，继续追踪该风险。

最终 JSON 事件日志：`artifacts/book-recap-b24b2/flutter-final-20261028.jsonl`，约 103.8 秒；保留 run2/run3 文本日志。定向分析本轮主要实现与 Widget 夹具共 13 个文件，`dart analyze` 返回 No issues found。`git diff --check` 通过，不代表整个既有脏工作区全面静态分析无问题。

原根项目 SQLite asset-loading 测试环境问题未顺手改配置，本轮使用现有隔离 harness / winsqlite3；既有 async BuildContext warning 不在本轮宣称修复范围。旧 sqflite factory/键盘命中警告仍需区别于本轮功能失败。

### 可复跑方式

在 `tool/reliable_upload_tests`：

```powershell
flutter test --no-pub --reporter json --concurrency=1
```

在 `backend`，仅选择离线测试（排除需要独立 runner 的 PostgreSQL 文件）：

```powershell
$tests = @(rg --files src -g '*.test.js' -g '!*.postgres.test.js')
node --test $tests
```

合成 PG 使用已审核的 `backend/test-support/runRecapSynthetic.js`，参数为现有独立 PostgreSQL binaries 路径。必须先确认 runner 创建全新 PGDATA、未使用任何业务连接配置，禁止把它替换成真实连接字符串。本轮参数为系统 Temp 下 `zhidu-recap-b233-tools-64e2e36f0b7b41bdbb0f8b24be0b00b1/package/native/bin`。

视觉验证使用真实组件 RepaintBoundary 生成 390×844、320×640 PNG，检查非空像素并人工查看中文、图标、长正文和布局。测试单独加载系统中文字体与 MaterialIcons，没有改变应用字体。最终图片位于 `C:/Users/29319/AppData/Local/Temp/zhidu-recap-b24b2-visual-db919c64`，包含 materials-390、confirmation-390、detail-390、detail-320。没有用截图替代交互测试。

## 8. 未验证事项与正式集成前置条件

- 尚未进行 iPhone/Android 真机、真实模型、TestFlight 或生产验收；模拟输出只能证明协议与交互，不能证明真实回望质量。
- 服务端 adapters 未挂载；生产入口保持 null。后续需要独立批准测试服务组合和路由挂载，不可把本机模拟成功说成线上可用。
- 生产展示 policy/version/窗口、客户端安全上限、成本与撤回延迟需审批。没有批准时不可启用页面。
- 正式组合需接入可靠网络状态、现有 Navigator RouteObserver 和真实 AI consent 流程；测试目前是显式注入。真实弹层授权后重选行为需要产品/真机复核。
- 跨设备缺少本地记录仍安全阻断，需要未来同步范围证明协议；没有偷偷完成“自动恢复所有历史”。
- fragment_only 仍不支持保证精准跳原书。书籍重新导入、同名不同 ID 不合并。
- 大书架/大量追问的逐条本地查询性能未做真机量测；当前显式上限可能要求用户缩小范围。
- 进程级通知偏保守；时钟偏差可能安全拒绝有效许可，需真实设备诊断而非放松校验。
- 旧 GET 传输可能含正文，但不会直接渲染。没有把一次 GET 成功作为永久缓存许可。
- 请求重放沿用内存状态，不保证 App 进程重启后恢复正在执行的请求 ID；持久化操作恢复仍需单独设计。
- 首次全量测试未定位失败需后续重复验证，不能仅凭末次全绿认定无不稳定性。

后续真实联调应先用独立服务和合成账号，验证路由、授权弹层、断网/后台、账号 A→B→A、来源编辑删除、许可到期、保存追问并发，再单独审批有限真实模型质量评测。不得因此自动开启入口或消耗模型余额。

## 9. B2.4c 建议与停止条件

轻提示应另行审查，仅使用已许可的最低必要元数据，低频且可关闭；不自动分析随心记、不自动生成私人回望、不把短期重复测试当长期兴趣。需要先确定触发依据、频率、冷却、消失条件和撤回规则。本轮未实施任何轻提示或发现规则。

本轮交付为：**已完成代码；已通过上述自动化验证；真实联调未完成；正式上线未批准。** 报告完成后停止，等待审核，不自动进入 B2.4c。
