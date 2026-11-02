# 小U多账号隔离实施报告

日期：2026-10-19。范围：经批准的阶段 A、B、C；不包含真实设备迁移、安装包构建或部署。

## 1. 阶段结论

| 阶段 | 结果 | 边界 |
| --- | --- | --- |
| A 安全备份 | 完成，逐文件 SHA-256 校验及恢复验证通过 | 源码及工作区备份，不是 iPhone/生产数据库备份 |
| B 隔离开发 | 完成 SQLite 17→18 代码及会话隔离 | 只在合成临时数据库执行迁移 |
| C 自动化验收 | 新增 26 项专项测试，现有 harness 回归通过 | 未执行真机验收、真实 Apple 或生产 PostgreSQL 联调 |

没有执行 commit、push、部署、生产配置修改或真实数据库迁移。没有清库、自动认领旧 AI 历史或批量 backfill。

## 2. 安全快照

位置：`D:/Zhidu-private-backups/reader-pre-isolation-20261018-01/`。

- 备份前可用空间：C 盘约 16.23 GiB，D 盘约 18.38 GiB。
- 收录 21,627 个普通文件，原始字节数 5,951,426,564，约 5.54 GiB；另外记录 19 个符号链接目标。
- 包含原有 `.git`、未提交、未跟踪及必要的忽略文件，包括原有构建产物、配置、依赖与日志。符号链接不向外递归收录 Flutter SDK 等外部依赖。
- 所有文件使用 AES-256-GCM 加密；敏感配置和其他私有材料分开存放于 `private/`，其余存放于 `source/`。
- 密钥由 Windows DPAPI CurrentUser 保护；目录 ACL 限当前用户与 SYSTEM。不上传、不在报告中输出密钥或配置值。
- `manifest.json`、`SHA256SUMS.txt` 提供逐文件记录；`git-state.json` 保存原 Git 状态。
- 全部 21,627 个文件完成解密认证与 SHA-256 校验；7,044 个非敏感文件恢复至 `restore-check/`，14,583 个私有文件仅在内存中验证。另一个新进程重新解开 DPAPI 密钥并再次验证全部文件。
- 源文件清单及 hash 在验证时重新对账；恢复的 Git HEAD 为 `caf7dd675322153bc1ee3c09747619510151d08d`，当前 HEAD 未改变。

恢复说明在快照目录 `RESTORE.md`。恢复必须进入新目录，不得直接覆盖现在的工作区。当前验证依赖同一 Windows 用户及其 DPAPI 配置，不能宣称已经具备跨机器灾难恢复能力。

## 3. SQLite 18 结构与数据策略

增量迁移只有以下结构变化：

| 表 | 新字段 | 含义 |
| --- | --- | --- |
| `ai_messages` | `user_id TEXT`，可空 | 新记录的知读账号归属 |
| `user_entry_follow_ups` | `user_id TEXT`，可空 | 已确认父 trace 所有权的追问归属 |

新增索引：

```sql
CREATE INDEX IF NOT EXISTS idx_ai_messages_owner_book_time
ON ai_messages(user_id, bookId, timestamp);
CREATE INDEX IF NOT EXISTS idx_follow_ups_owner_entry_time
ON user_entry_follow_ups(user_id, entry_id, created_at);
```

`DatabaseService.createAiOwnershipSchema` 检查字段后才添加，索引使用 `IF NOT EXISTS`。创建数据库和升级共用此函数；升级在 sqflite 的事务内执行。合成测试覆盖实际 17→18、重复执行、故障回滚。

旧记录新增列保持 `NULL`，不删除、不覆盖、不按当前登录账号或 bookId 猜测所有权。未知 AI 历史及追问不返回给任何账号，也不在登录时自动合并。已具备可信账号归属的云端历史可以通过现有接口正常读取；这不等同于认领原来归属未知的本地记录。

归属未知的 AI trace 及其 pending/revision 保持原样，不由匿名数据合并或可靠上传的认领逻辑绑定当前账号。普通匿名阅读业务保留现有行为，不扩展本轮产品边界。

此次没有修改 `user_entries`、pending queue 的 schema、revision/generation 协议、后端 migration、Obsidian 或 IAP 协议。

## 4. 会话与异步隔离

- 新增 `AuthSessionScope`，捕获 `userId + sessionEpoch + API origin`。开始登录、退出、切换时立即使旧 scope 失效，A→B→A 不会恢复 A 的旧异步请求。
- 在模型请求、历史读取、缓存恢复、远端返回、本地保存和事务内写入的关键边界校验原始 scope。过期结果不写入新账号、不恢复旧界面。
- `AiProvider`、`ReaderProvider` 及私有详情页监听会话变化，取消或忽略旧请求、清理可见的私有状态；返回旧详情页也不会重新显示上个账号内容。
- `ai_messages` 按 userId 和 bookId 查询；新消息用独立 UUID，保留同一原文多次主动解读，不按内容去重。
- 追问必须找到属于当前账号且未被书籍删除标记排除的父 trace；无可信父记录时不得猜测归属。
- 小U首页、trace、标签、批注及回顾入口按账号读取；磁盘缓存增加 API origin 和账号命名空间，旧缓存原样保留但不作为新账号恢复来源。
- 本地登录持久化增加单条 `auth_session_v2` JSON 作为一致性恢复来源，并保留旧偏好键的兼容写入。旧版本未生成 v2 时仍能读取旧格式；v2 已存在但损坏时拒绝回退至可能过时的旧凭证。退出写入持久化注销标记。
- 并发登录采用最后一次发起的操作作为有效操作；旧登录、退出响应或 Apple 原生登录回调不得覆盖之后的会话。

没有改 JWT、PKCE 或 Apple IAP 的服务端协议。v2 会话沿用项目现有本地凭证存储机制，不宣称本轮完成了安全存储迁移。没有在日志或导出中新增认证信息。

五种免费模式、长原文预览及展开/收起、独立解读历史和主要阅读布局保留。未新增 Pro、思维导图、深度回望或小U发现规则。

## 5. 本轮文件清单

以下按阶段 A 快照比较，而不是相对旧 HEAD 猜测。工作区原有 P0a、IAP、Obsidian、图标等大量未提交成果保留。

修改 22 个原有文件：

| 文件 | 修改目的 |
| --- | --- |
| `lib/app.dart` | 私有页面随账号会话重建 |
| `lib/config/constants.dart` | SQLite 版本 18 |
| `lib/providers/ai_provider.dart` | AI 状态、历史及请求的会话隔离 |
| `lib/providers/auth_provider.dart` | 账号操作与会话边界对齐 |
| `lib/providers/reader_provider.dart` | 阅读器私有状态及异步保存防串号 |
| `lib/screens/notes_free/notes_free_screen.dart` | 私有详情会话边界，未接入 AI |
| `lib/screens/reader/reader_screen.dart` | 阅读器会话失效处理 |
| `lib/screens/reader/widgets/ai_explanation_card.dart` | 解读及追问会话校验 |
| `lib/screens/reader/widgets/reader_question_sheet.dart` | 问小U上下文及保存边界 |
| `lib/screens/xiaou/widgets/xiaou_card.dart` | 私有详情、Agent、回顾失效处理 |
| `lib/screens/xiaou/xiaou_home_screen.dart` | 首页缓存及异步结果隔离 |
| `lib/services/ai_service.dart` | AI 请求会话边界 |
| `lib/services/apple_auth_service.dart` | 迟到的 Apple 登录回调保护，不是 IAP 修改 |
| `lib/services/bmob_api.dart` | 并发认证及一致的本地会话恢复 |
| `lib/services/book_service.dart` | 本地归属查询、缓存、追问与事务保存 |
| `lib/services/database_service.dart` | 两列两索引的增量迁移 |
| `lib/services/reliable_upload_service.dart` | 不自动认领未知 AI 数据 |
| `lib/services/sync_service.dart` | 匿名合并跳过未知 AI 记录 |
| `lib/services/xiaou_conversation_service.dart` | 对话异步会话保护 |
| `test/services/book_removal_test.dart` | 补齐历史 schema fixture，不放宽生产迁移 |
| `test/services/reliable_upload_service_test.dart` | 完整旧 schema 与版本 18 回归 |
| `test/services/xiaou_trace_snapshot_test.dart` | 明确测试会话与缓存命名空间 |

新增文件：

- `lib/services/auth_session_scope.dart`
- `lib/widgets/session_bound_state.dart`
- `test/services/ai_account_isolation_test.dart`
- `test/services/ai_ownership_migration_test.dart`
- `test/services/auth_session_race_test.dart`
- `test/support/legacy_ai_schema.dart`
- `tool/reliable_upload_tests/test/ai_account_isolation_test.dart`
- `tool/reliable_upload_tests/test/auth_session_race_test.dart`
- 本报告 `docs/zhidu-xiaou-account-isolation-report.md`

快照 hash 对账中没有原有文件丢失；原有后端、IAP、Obsidian 和图标源文件与阶段 A 快照一致。Git index 未暂存，本轮没有覆盖既有成果。

## 6. 自动化结果

日志目录：`D:/Zhidu-private-backups/reader-isolation-validation-20261019/`。

| 检查 | 结果 | 说明 |
| --- | --- | --- |
| 新增隔离专项测试 | 26 通过 | 已计入下面的完整 harness，不重复累计 |
| 现有 Flutter SQLite harness 全量 | 113 通过，2 跳过，0 失败 | 修改前 87 通过、2 跳过 |
| diagnostics 编译模式专项 | 3 通过，1 跳过 | DB/WAL、账号及导出只读断言通过；正常模式专属用例跳过 |
| 后端非 PostgreSQL 测试 | 89 通过，0 失败 | 包含 P0a、认证、上传、MCP、Obsidian、IAP |
| 后端 `npm run check` | 通过 | 无后端源码修改 |
| Obsidian 插件测试 | 20 通过，2 集成用例跳过 | 未连接真实 vault/服务执行集成用例 |
| Obsidian `npm run typecheck` | 通过 | 无插件源码修改 |
| 本轮 Dart 源码及测试定向 analyze | 无问题 | 不等同于全项目历史 warning 已修复 |
| 根目录 Flutter 全量 | 84 通过，10 个文件加载失败 | 全部同一 Windows native SQLite 加载问题，见下 |

新增专项覆盖：A/B 相同 bookId、相同时间戳独立消息、未知历史保留、父 trace 所有权、离线追问、trace/标签/批注读取、A→B→A 排队读写及流式迟到结果、事务失败回滚、首页及磁盘缓存恢复、API origin 隔离、注销后重开、并发登录及晚到 Apple 登录回调、旧 schema 迁移与失败回滚、未知 AI pending/revision 不被认领。

所有数据库测试使用合成临时 SQLite；网络使用 fake、loopback 或离线，不连接正式数据或真实模型。

复跑 SQLite harness：

```powershell
Set-Location C:\Users\29319\Desktop\reader\tool\reliable_upload_tests
flutter test --no-pub --reporter expanded
flutter test --no-pub --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=true test/local_diagnostics_mode_test.dart --reporter expanded
```

### 既有环境问题与新增 regression 的区分

根目录 Windows 测试原有 8 个文件因 `sqlite3_initialize` 无法从进程/native asset 解析而加载失败。本轮新增的两个 SQLite 测试入口同样受此环境问题影响，因此当前是 10 个加载失败，不是 10 个业务断言失败。未修改应用全局 SQLite hook、依赖或 iOS 配置来追求全绿。

项目现有 `tool/reliable_upload_tests` 选择系统 SQLite，已运行这些真实临时数据库测试并通过。建议后续独立处理根目录 Windows 测试 runner 的 native asset 配置，并与移动端打包分开验证。

既有键盘测试 hit-test warning 仍在；原有 `share_service.dart` async BuildContext warning 未顺手重构。没有将这些 baseline 写成已经修复。当前已运行回归中未发现新增业务断言失败，但真实 PostgreSQL、iPhone 和跨进程原生时序仍需单独验收。

## 7. 回滚与真实数据前置条件

1. 合成测试已证明升级失败时版本、两表字段及数据一起回滚，数据库仍为 17。
2. 升级成功后，不直接安装旧版程序作为回滚：旧版有未按账号过滤的读取，且未提供 18→17 安全降级路径。
3. 优先用兼容 schema 18 的修复版本回滚业务行为；确需恢复数据库备份时，必须先保全升级后的新数据，禁止覆盖丢失新记录。
4. 当前源码快照不包含真实 iPhone SQLite 的一致性备份。真机迁移前，需另取 SQLite backup API 生成的一致副本，或在 App 完全停止后保留 DB/WAL/SHM；不可只拷主 DB。
5. 在用户再次确认真实迁移与安装范围前，不制作安装包、不打开真实数据库升级、不尝试认领旧记录。
6. 同一真实 App 数据容器不要混用测试与正式 API。磁盘缓存带 origin，但 SQLite `user_id` 并非环境命名空间；独立测试安装/容器仍是必要边界。

不对未经检查的真实设备数据作“已验证没有丢失”的承诺。当前结论是：代码不清理未知历史，合成迁移与事务测试证明保留，源码成果已完成恢复验证。

## 8. 下一阶段真机验收建议（尚未执行）

1. 先经确认准备独立测试后端、独立账号 A/B 与独立客户端容器，不复用生产或擅改 IAP Sandbox；真实旧容器先完成 DB/WAL/SHM 一致备份。
2. A 对同一 bookId 保存解读、问答、追问、划线和想法；B 登录同书，只能看见 B 自己的私有历史。退出后不能看见 A/B 私有历史。
3. A→B→A 切换时故意保留模型流、远端历史和缓存读取；迟到响应不得落库、恢复旧卡片或冒充当前回答。
4. 离线切换、杀进程重开、注销后重开、重新登录重复上述检查，验证归属未知旧数据仍保留但不可见。
5. 对同段原文主动解读两次应保留两条独立历史；进行 14 轮追问验证首轮原文/模式/书籍证据，同时复验同章重复原文、EPUB 章节定位、取消及断流状态。
6. 验证长原文预览与展开/收起不变，个人笔记边界不变。对比迁移前后的记录数、原文、未知归属行与 pending/revision，禁止清库替代排查。
7. 真机迁移、线上 PostgreSQL、Apple Sandbox 与 Obsidian 实际联调各自记录证据；不能用本轮单元测试结果替代这些验收。

本阶段到此暂停，等待确认真实设备备份与下一阶段实施范围。
