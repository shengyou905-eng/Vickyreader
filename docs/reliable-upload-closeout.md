# Reliable Upload 收尾与真机验收

后续两个blocker的实现与最新限制见 [revision与永久删除报告](reliable-upload-revision-fences.md)。
以下内容保留上一轮审计时间点，不代表后续实现仍未进行。

本轮没有部署、执行生产 migration、读取生产 `.env`、commit 或 push。
本地 PostgreSQL 测试不是生产 schema 核验，SQLite/fake HTTP 测试也不等于真机验收。

## 上线前结论

004 是兼容性增量：增加 nullable `client_entry_id TEXT`，历史唯一且未被占用的
`metadata_json.local_id` 才回填；无 local_id、空白、重复历史身份继续保留 NULL。
PostgreSQL 普通唯一索引允许同一用户多行 NULL。不会删除、合并原记录，不改变
`created_at` / `updated_at`，也不制造历史 created ledger。

修复了重复执行时“未绑定行的 local_id 与已绑定行冲突”的问题。
整个 004 在事务内完成，加锁串行化回填和索引创建；获取锁超过 5 秒就失败并回滚。
索引创建不是 CONCURRENTLY；ALTER TABLE还会取得ACCESS EXCLUSIVE锁，事务内读写都
可能被阻塞，需低峰维护窗口并先在恢复库测量回填/建索引耗时。5秒是获取锁的等待限制，
不是整个迁移执行时间上限。
若已有非空 client_entry_id 重复、同名索引定义不正确，停止处理，不自动清理用户数据。
SQL 成功后可重复执行；psql 必须使用 ON_ERROR_STOP，不得忽略失败继续上线。

### 精确部署顺序（供后续获授权执行，本轮不执行）

1. 固定后端和客户端候选版本，先完成下述阻塞修复与本地测试。
2. 在同版本 PostgreSQL 的隔离恢复库演练备份恢复、003/004及 API 验收。
   生产 `.env`、MCP_TOKEN_HASH_SECRET、JWT 等保持原值；不把密钥写入命令、日志或 Git。
3. 对目标生产库做已验证可恢复的备份；记录已有 schema、迁移状态、表规模。
   用只读会话执行 `backend/src/db/checks/reliable_upload_004_preflight.sql`。
   未知 schema 差异、重复非空绑定、异常索引必须先人工核验，不能直接宣称可上线。
4. 确认 Phase 1A/1A.1 的 003 已应用，包含 updated_at、sync_changes、
   sync_user_cursors、user_sequence 及必要唯一键。如果没有，先单独安排003的授权和演练。
5. 低峰停止/暂停相关写入，执行 **004，不是整个 schema.sql / npm run db:init**：
   `psql --set ON_ERROR_STOP=1 --file backend/src/db/migrations/004_reliable_upload_idempotency.up.sql`
   数据库连接通过受保护的部署环境提供，不打印连接串。
6. 确認命令 exit=0，再只读核验 client_entry_id、有效唯一索引、历史行数/时间戳。
   锁超时或任意错误：维持旧版本，查明原因，回滚会话，再择时重试。
7. 部署兼容004的后端代码（不覆盖 .env），重启并检查健康、登录、幂等 PUT/DELETE、
   进度、书架 replace、ledger、MCP modern/legacy 回归。用专用测试账号，不碰真实笔记。
8. 后端及数据库通过后，才分发新版客户端（SQLite 15）。执行本文真机清单。
9. 验收通过后再扩大客户端发布。数据库必须先于新版客户端上线。

### 回滚边界

优先保留004新增字段和索引，回退应用到兼容该 schema 的版本，不执行 DROP COLUMN。
旧后端/客户端若不支持幂等端点或仍采用级联删书，不是安全回滚目标。
新客户端已发布后不能直接移除004：会令队列永久重试，丢失幂等身份，导致重复上传。
旧客户端恢复运行仍可能上传过时全量书架/执行旧删书语义，需控制客户端版本。
SQLite15不能假设可被旧版14无损降级打开；不要通过降低数据库版本号回滚。

## 新删书语义

- 普通 `deleteBook` 委托 `removeFromLibrary`，保留 books 元数据行并设置 is_archived=1。
- `getBooks` 和书架上传快照只选择未归档书籍。历史查询 `getBook` 仍能解析书名和章节。
- highlights、notes/thought、四类 user_entries、bookmarks、reading_progress 保留。
- PostgreSQL replace 只移除 user_library_books 并产生 book deleted ledger；
  无 user_entries/reading_progresses 级联删除，MCP痕迹查询无需依赖书架成员关系。
- 当前旧删书代码没有删除物理文件，因此继续保留文件，不新加文件清理策略。
- `insertBook` 恢复相同 ID 时 UPDATE 而非 SQLite REPLACE，避免外键级联误删历史。
- `permanentlyDeleteBookData` 是没有普通UI入口的破坏性服务方法：清理本机已知的
  canonical trace、原始划线、笔记、书签、进度及对应 follow-up，并可靠排队删除远端。
  free_notes/完整聊天不进入同步；归档元数据锚点保留，避免私有聊天外键被误删。
- **限制：这个服务方法不是“清除所有设备云端历史”的完整实现。** 本机未持有的远端
  trace 不会被枚举。正式接入彻底删除UI前，需要用户限定的服务端按book_id清理事务，
  为每条真实删除写ledger，并与可靠上传队列连接；不能标为已完成的全云端清理。

## 真机准备

仅使用专用测试账号、测试书和合成短文本。在隔离验收后端执行，所有操作仅限自己数据。
记录设备/系统、App build、后端提交、003/004状态、SQLite版本、测试时间和测试账号ID。
准备三本小书 B1（保留）、B2（改元数据）、B3（移出）；另有本地文件 B4（离线导入）。
准备已上传的 E-update、E-delete；对 B3 准备 highlight/thought/AI traces/进度。
另准备用户B，验证跨用户读不到测试对象。不要用真实用户正文做测试样本。

SQLite 观察条件：Android debug 可用应用沙盒的受控调试工具；iOS 用开发签名真机与
Xcode下载应用容器。先在**未杀App**时用调试器只读查询队列，确认操作已经持久入库；
之后再杀进程、取关闭状态数据库核对。复制运行中数据库时必须同时带上 WAL/SHM 并用
一致备份方法，不能只拷贝主库。TestFlight若不能提取容器/观察队列，本轮这一项应标记
“未核验”，不能用界面成功提示代替持久化证据；改用开发签名验收构建，不加生产调试UI。

### 逐项清单

- [ ] 1. 登录测试账号A，保持联网。不要截图/导出 token 或 Authorization header。
- [ ] 2. 基线队列为0；PostgreSQL/MCP能看到B1/B2/B3及已上传trace；记录当前
  `sync_user_cursors.last_sequence` 为W，保存仅含ID/计数/摘要的证据。
- [ ] 3. 开飞行模式并关闭Wi-Fi/蜂窝数据，确认其他联网请求也失败，非仅“弱网”。
- [ ] 4. 在B1创建划线H-new，记录本地id与选中文字的测试期望值。
- [ ] 5. 新建想法T-new，并修改已有划线想法两次，以最后一次值为准。
- [ ] 6. 修改E-update的重要标记或关联想法，记录最终值。
- [ ] 7. 删除E-delete，记录client_entry_id和原服务器UUID。
- [ ] 8. 将B1翻到其他章节，等待阅读页保存进度，记录chapterIndex/scrollOffset。
- [ ] 9. 离线导入B4，确认本地书架可见。不要用必须联网下载的导入方式。
- [ ] 10. 修改B2现有UI允许的书架属性（例如打开阅读更新lastOpenedAt/进度）；
  若该构建提供重命名，再修改title。不新增不存在的UI作为验收前提。
- [ ] 11. 从普通入口移出B3；其历史痕迹仍可在阅读痕迹页查看，不能出现破坏性提示。
- [ ] 12. 在断网状态只读检查pending：H-new/T-new/E-update为最新payload，
  E-delete为delete；进度存在upsert；书架只有一个最终replace快照，含B4、不含B3。
  B3不得因为普通移出产生trace/progress delete。合并存在，不能要求操作数等于点击次数。
- [ ] 13. 仍断网，强制结束App（不是仅切后台）。记录PID/时间，再核对数据库副本队列。
- [ ] 14. 恢复Wi-Fi或蜂窝网络，保持同一测试账号。
- [ ] 15. 重启App。禁止卸载、清应用数据或手工清队列。
- [ ] 16. 保持前台等待自动重传。启动/前台/每30秒触发；单批最多50条、串行；
  到期前不会强制重试，退避最高15分钟。小批次通常数十秒；高退避至少观察16分钟。
- [ ] 17. 当前用户pending最终为0；再次退出重进仍为0。若不清空，按operation_id、
  entity_type、retry_count、next_retry_at定位，不能把payload/token写日志。
- [ ] 18. 核对PostgreSQL：H-new/T-new各一个client ID，E-update为最终值，E-delete不存在；
  B1进度与最后保存一致；书架含B1/B2/B4不含B3；B3历史trace与进度仍在。
- [ ] 19. 查询user_sequence>W的ledger：用户均为A、user_sequence唯一递增，
  真实变更有对应事件，重传同值不额外造事件；B3只产生book deleted，不产生历史删除。
  同一事务可能产生多条事件，原本未上传就删除的对象可能没有created/deleted事件。
- [ ] 20. 用已授权MCP客户端读取：modern `server/discover`→工具发现，或当前支持的
  legacy initialize→tools/list；只有5个只读工具。list_books分页看B1/B2/B4不见B3；
  get_book_traces(B3)/search_traces仍能看到历史；get_trace(E-delete)返回未找到；
  抽样比对excerpt/note/explanation/tags与PostgreSQL白名单字段。用B账号重试这些ID无数据。

### 必测竞态补充

- [ ] 离线 create→update→delete：恢复后服务端不存在对象，再次重启也不复活。
- [ ] 稳定同一client ID的delete→recreate：最后应是新内容；UI导入同名书可能生成新ID，
  不能拿“同名不同ID”冒充本测试。使用受控调试驱动或本地测试harness保留稳定ID。
- [ ] 请求正在执行时又recreate：旧响应不得删除新generation的pending，新操作最终上传。
- [ ] 服务端已提交而响应丢失：重启后重传不产生重复canonical entry/ledger。
- [ ] **迟到的旧请求**：仅在隔离环境，故障代理暂缓旧DELETE请求至重建PUT已提交后，
  再放行旧DELETE。当前服务端没有revision条件，这项预期不能通过，是发布阻塞。
  代理禁止保存Authorization和请求正文；不在生产插入代理或修改路由。
- [ ] 在途请求时切账号：剩余A队列不能用B身份发出；A的pending保留待A重新登录。

### 只读证据查询

SQLite（`:user_id`由调试工具绑定，不在报告中输出payload）：

```sql
SELECT operation_id, entity_type, entity_id, operation, generation,
       retry_count, next_retry_at
FROM pending_upload_operations WHERE user_id = :user_id
ORDER BY created_at, operation_id;
SELECT id, is_archived FROM books;
```

PostgreSQL（psql变量`test_user_id`、`watermark`只填测试账号与基线，不是密钥）：

```sql
BEGIN READ ONLY;
SELECT client_entry_id, count(*) FROM user_entries
WHERE user_id = :'test_user_id' AND client_entry_id IS NOT NULL
GROUP BY client_entry_id HAVING count(*) > 1;
SELECT id, client_entry_id, book_id, source, is_important,
       created_at, updated_at, md5(coalesce(user_input,'')) AS note_digest
FROM user_entries WHERE user_id = :'test_user_id';
SELECT book_id, progress, chapter_index, scroll_offset, updated_at
FROM reading_progresses WHERE user_id = :'test_user_id';
SELECT book_id, title, last_opened_at FROM user_library_books
WHERE user_id = :'test_user_id';
SELECT user_sequence, entity_type, entity_id, operation, changed_at
FROM sync_changes WHERE user_id = :'test_user_id'
  AND user_sequence > :'watermark'::bigint ORDER BY user_sequence;
SELECT last_sequence FROM sync_user_cursors WHERE user_id = :'test_user_id';
COMMIT;
```

仅测试正文可人工比对；正式验收证据保留计数/ID/哈希，不导出完整个人阅读内容。

## 当前封板阻塞与最小后续修复

1. **迟到请求无服务端顺序防护**：generation只有本地清队列条件，没有随HTTP提交，也
   没有服务端持久请求版本。相同ID的新PUT后，旧DELETE仍可以删除新记录；旧PUT也可
   覆盖新值/复活已删除对象。PostgreSQL diagnostic测试明确复现，不计为验收通过。
   最小完整修复是持久化实体上传revision/删除tombstone，在业务事务内校验请求顺序；
   本地revision不能因pending清空而重置，删后重建也必须递增。不能拿随机operation_id
   或客户端时间戳当顺序；还要明确多设备请求版本归属。需要受控新增schema与协议字段，
   不应偷偷塞入已经审查过的004或只用延长timeout掩盖。
2. **彻底删除仅覆盖本机已知数据**：如上所述，需要服务端用户限定按book_id清理能力，
   对云端独有trace也写tombstone，并接入可靠队列。正式破坏性UI继续不开放。
3. **生产漂移与真机未核验**：只读preflight和20项真机checklist尚须在目标环境执行。
4. **既有限制**：单次完整书架快照最多200本，超过会被400拒绝并留队列；多设备完整
   replace快照目前是最后到达者决定书架。历史重复local_id不自动合并；旧版已清掉的
   本地历史无法凭本次归档代码恢复。这些不能由“pending为0”推导已解决。

因此当前结论为：归档改动和常规Reliable Upload回归已具备自动化证据；尚不能宣告
Reliable Upload完全封板，也不应把Obsidian插件上线建立在已完成全链路验收的假设上。

## 本轮验证记录

| 检查 | 结果 |
| --- | --- |
| Flutter队列 + 归档/彻底删除/SQLite升级 | 16/16；使用真实临时SQLite、fake HTTP |
| Backend reliable upload + Phase1A repositories | 19/19 |
| MCP modern/legacy regression | 17/17 |
| 本地PostgreSQL16迁移/并发/ledger | 11/11断言通过，其中1项是迟到DELETE漏洞复现，不是正向验收通过 |
| dart analyze | exit 0，0 error / 0 warning；share_service.dart:64既有info因测试包扫描出现两次 |
| npm run check | 通过 |
| git diff --check | 通过；仅Git CRLF提示 |
| 生产迁移、真机断网、线上MCP验收 | 本轮未执行 |

本地测试容器只绑定127.0.0.1，使用独立空测试数据库，执行后已停止并自动移除。
测试文件额外限制真实PG fixture只能运行在localhost、名称以_test结尾的库；
fixture会清理public schema，绝不能将它指向真实业务数据库。

## 本轮修改文件（不含上一阶段已有工作区改动）

- backend/src/db/migrations/004_reliable_upload_idempotency.up.sql
- backend/src/db/schema.sql
- backend/src/db/checks/reliable_upload_004_preflight.sql
- backend/src/repositories/syncChange.postgres.test.js
- lib/config/constants.dart
- lib/services/database_service.dart
- lib/services/book_service.dart
- lib/services/reliable_upload_service.dart
- lib/l10n/app_en.arb
- lib/l10n/app_zh.arb
- lib/l10n/generated/app_localizations.dart
- lib/l10n/generated/app_localizations_en.dart
- lib/l10n/generated/app_localizations_zh.dart
- test/services/reliable_upload_service_test.dart
- test/services/book_removal_test.dart
- tool/reliable_upload_tests/.gitignore
- tool/reliable_upload_tests/pubspec.yaml
- tool/reliable_upload_tests/pubspec.lock
- tool/reliable_upload_tests/README.md
- tool/reliable_upload_tests/test/reliable_upload_test.dart
- docs/reliable-upload-closeout.md

主App的pubspec.yaml/pubspec.lock未修改，测试包仅复用现有依赖和系统SQLite。
未改MCP协议/工具contract，未添加实体或任何Obsidian功能。
