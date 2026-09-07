# Reliable Upload: progress revision closeout

本轮只处理 reading_progress 的请求版本和发布兼容性。没有 commit、push、deploy、生产
migration 或生产配置修改。未修改 MCP contract、free_notes、完整聊天或书架冲突协议。

## A. 根因与修复范围

旧 upsert 只比较业务字段是否变化，不知道请求的新旧。事务与 ledger 能保证原子性，
不能单独防止迟到的旧位置覆盖新位置。旧诊断用例已替换为正向版本安全回归。
合法用户操作可以降低 progress，所有版本判断均不使用 max(progress) 或请求时间戳。

另修复同一进度链路的 GET 回写：未带版本的远端进度不能按服务器 updated_at 覆盖本地
已拥有 revision 的状态，否则下次本地 snapshot 可能将旧位置当作新修改上传。

## B. 版本协议

沿用 trace 的 writer_id + client_revision，共用 validateVersion / compareRevision。
服务端新表 reading_progress_upload_states 主键 (user_id, book_id)，包含：

- writer_id（UUID，首次有效请求认领）
- latest_revision（BIGINT，客户端限制正安全整数）
- deleted
- request_hash（规范化业务位置和操作的 SHA256，不复制原文/笔记）
- updated_at（审计时间，不用于排序）

SQLite复用 upload_writer 和 upload_entity_revisions，entity_type='reading_progress'、
entity_id=book_id。pending 的 client_revision 是请求版本，generation 仍只用于本地
ACK/失败回写的条件。新位置递增版本；相同状态快照/同一请求重试沿用版本；counter 在
ACK 清除 pending 后仍保留。队列合并和重启不重置它。

| 输入 | 处理 |
| --- | --- |
| 同 writer，更高 revision | 接受，即使 progress 数值变小 |
| 相同 revision、相同规范化位置/操作 | 幂等 replay，不重复 ledger |
| 低 revision | 409，无写入 |
| 相同 revision、不同位置/操作 | 409，无写入 |
| 不同 writer | 409，保留待处理操作，不自动抢占/加号 |
| 无版本/非法版本 | 428，不降级为旧写入 |
| book 已永久删除 | 410，包括旧进度精确重放 |

同一 book 的不同设备不共享计数时不能把两个 revision 比大小。本轮选择 writer 绑定、
冲突保留而非隐式 last-write-wins；writer 交接与跨设备位置合并不在本轮。

## C. delete / recreate

update1 -> delete2：canonical 行硬删除，版本墓碑长期保留。
迟到 update1 或 delete1 返回409，不复活也不误删。
同 writer 的 update3 允许在 delete2 后重建；之后迟到 delete2 返回409。
删除不存在的 canonical 行也保留墓碑，但不伪造 ledger deleted 事件。
墓碑不做TTL/GC；只有账号物理删除时由 users 外键级联删除。

## D. 事务与永久删除

progress 写入先获得既有 sync_user_cursors 用户行锁，再检查 book marker 和版本。
业务字段、版本墓碑、sync_changes、user_sequence 同一个 withTransaction 提交。
不同用户不使用全局锁。stale、replay、业务值相同的高版本不制造无意义业务 ledger。
高版本相同业务值会推进 revision，以继续阻挡中间迟到请求。

permanentlyDeleteBookData 复用 permanently_deleted_books。它在原事务内把 progress
版本状态标记 deleted，再删除 canonical progress，按实际删除写 ledger。book marker
使未到达过服务端的旧上传也不能恢复该书。普通 removeFromLibrary 不删除 progress。

客户端 GET 回写在SQLite事务中检查 revision、pending、permanent marker 和当前账号。
本地 progress 是 book-only 主键，因此只要该book已有任一账户的本地版本就不自动
覆盖；无本地版本时仍允许当前账号/当前book的初始远端进度读取。

## E. Migrations

新增 006_progress_upload_revisions.up.sql；本轮没有修改003/004/005。
schema.sql同步增加同样定义。006仅新建版本表并为现存progress建立revision0的未认领
baseline。不变更历史progress、ID、created_at/updated_at，也不生成历史ledger。
CREATE IF NOT EXISTS + INSERT ON CONFLICT DO NOTHING可对预期schema重复执行，保留
高版本和墓碑。schema漂移需要先审计，不能依赖IF NOT EXISTS修复。

006自带BEGIN/COMMIT及5秒lock_timeout；FK/DDL有关系锁，回填有行锁及扫描成本，需在
恢复库测量并低峰执行。5秒限制锁等待，不是执行总耗时。没有改大业务表的列。

SQLite17只回填既有 progress pending 的client_revision和独立counter/hash；旧generation
作为一次性种子，保留operation_id、重试时间、retry_count、writer。已有counter不覆盖。
JSON损坏会使升级报错/回滚，不清除队列。验证了SQLite16真实文件升级至17及旧14/15升级。

## F. 本轮文件

- backend/src/db/migrations/006_progress_upload_revisions.up.sql
- backend/src/db/schema.sql
- backend/src/repositories/uploadState.repository.js
- backend/src/repositories/readingProgress.repository.js
- backend/src/repositories/bookDeletion.repository.js
- backend/src/controllers/readingProgress.controller.js
- backend/src/routes/readingProgress.routes.js
- backend/src/controllers/reliableUpload.http.test.js
- backend/src/repositories/reliableUpload.repository.test.js
- backend/src/repositories/syncChange.repository.test.js
- backend/src/repositories/syncChange.postgres.test.js
- lib/config/constants.dart
- lib/services/database_service.dart
- lib/services/reliable_upload_service.dart
- lib/services/bmob_api.dart
- lib/services/book_service.dart
- test/services/reliable_upload_service_test.dart
- test/services/book_removal_test.dart
- docs/reliable-upload-progress-revisions.md
- docs/reliable-upload-revision-fences.md（仅补充本轮后续报告链接）

## G. 自动回归

| 检查 | 结果 |
| --- | --- |
| Flutter可靠队列、进度、书籍移除/永久删除 | 27/27 |
| Backend reliable upload / HTTP / ledger | 21/21 |
| MCP regression | 17/17 |
| 真实独立PostgreSQL16并发/ledger/版本/migration | 19/19 |
| dart analyze | exit0，仅既有share_service.dart:64的BuildContext info |
| npm run check / check:reliable-upload | 通过 |

真实PG用例覆盖迟到旧值、合法新版本降低进度、同版本冲突/重放、删除重试、墓碑重建、
永久删除后写入、用户/writer隔离、版本状态失败回滚、ledger失败回滚和并发等待。
SQLite用例覆盖重启、丢失ACK、合并、在途请求、版本升级、晚到GET和已确认/已删本地状态。
PG中的BIGSERIAL诊断仍是原有内部主键问题演示，生产增量源继续使用user_sequence。
并发锁等待不保证调用顺序FIFO：低版本可以先提交，但绝不能在高版本之后覆盖状态。

## H. Rollout compatibility

### 当前API

新版客户端读写使用 `/api/reading-progress/versioned/:bookId`：GET、PUT、DELETE。
PUT/DELETE携带writer_id和client_revision；bookId来自路径，user_id来自认证。
旧POST `/api/reading-progress` 和 DELETE `/:bookId` 仍经过版本校验，无版本返回428。
旧GET `/:bookId` 返回428，避免旧客户端在上传暂停时按时间戳拉取云端旧进度覆盖本地。
GET错误在现有BookService捕获，继续使用本地位置。新版客户端不fallback到旧进度路径。

1. **migration后旧backend能否工作？** 表结构是附加式，旧SQL仍能执行，005/006不破坏
   旧canonical表。但旧backend忽略版本和墓碑，不能在版本协议启用后继续接写流量。
   migration本身不是安全切换；禁止新旧写入backend混跑或无保护回滚。
2. **旧客户端会怎样？** 进度读写返回428；trace无版本写入也由005实现拒绝。不是整个
   登录/阅读App被禁用。当前可靠队列实现catch后保留pending并退避；本地阅读继续。
3. **新客户端能否先发？** 不推荐，也不能保证整条Reliable Upload安全。新progress路径
   在旧backend为404（HTTP测试已验证），不会被假确认；但是上一阶段trace路径旧后端
   可能忽略version，因此必须backend先就绪，不依赖progress路径单独保护所有实体。
4. **兼容窗口？** 可以有“本地继续、云端排队等升级”的安全暂停窗口，不能无损兼容
   无版本且任意乱序的旧写入。未加入无版本覆盖或自动重新编号来伪装兼容。
5. **准确发布顺序：**
   - 在非生产恢复库、开发签名真机验证003/004/005/006与SQLite17。
   - 准备客户端包和更新说明；正式版先完成审核准备但不要自动对用户放量。
   - 备份并验证可恢复；维护窗口暂停旧同步读写流量、排空在途旧请求/旧进程。
   - 确认003/004/005已应用，再006；先升级全部backend实例，不能混跑。
   - 在恢复用户同步流量前验证旧进度读写428、新进度版本规则、认证及MCP回归。
   - TestFlight先给专用测试账号小组；通过真机流程后再放正式客户端更新。
   - 监控聚合错误率/队列计数（不记录正文/token），提醒未升级用户原地升级、不要卸载。
   - 出现问题暂停同步写入、修复前进；不能退回忽略版本的backend或删除墓碑。
6. **未升级会丢本地数据吗？** 对已具备持久队列的14/15/16客户端，428失败路径不会删除
   pending；原地升级17保留并补种版本。进度旧GET被暂停，避免发布窗口回写污染。
   但不能保证更早的best-effort版本：未入队的历史删除无法凭当前状态重建。卸载、清除
   App数据也会丢SQLite。当前实际已安装build/队列版本分布未访问生产，标为UNKNOWN；
   正式放量前必须核对。若仍支持无队列老版本，需先做存量数据保护/桥接升级，不能声称
   仅本轮migration即可保证它们无损。

## I-J. 验收边界

本轮支持的“新版backend + SQLite17客户端 + 同identity同writer”范围，已知progress
stale overwrite及GET旁路已修复，可以进入**非生产真机最终验收**，不是生产封板承诺。
正式放量仍以安装版本盘点和真机验收为门槛。不同writer冲突保持pending，不自动覆盖；
需要writer交接的设备不能承诺自动同步成功。

200books上限、完整library replace的多设备/旧快照冲突、CRDT等仍是用户明确排除项，
未修复，也未作为多设备全功能安全验收通过。不能把本轮结论扩展成所有同步场景安全。

## K. 真机 checklist

- [ ] 在非生产环境用专用账号/测试书；记录SQLite版本、book_id、writer/revision，不导出secret。
- [ ] 旧可靠客户端在线确认baseline，断网改进度、杀App，保留安装原地升级至17。
- [ ] 确认operation_id、writer、revision、retry_count保留；联网重启后重试同版本并清队列。
- [ ] rev1=0.2、rev2=0.8；延迟rev1到rev2提交后释放，409且PG/MCP保持0.8。
- [ ] 新rev3=0.2成功，证明可合法向前翻页。
- [ ] 相同rev/同payload重放不增ledger；同rev/不同payload返回409。
- [ ] delete rev4后放行旧rev3，不能复活；recreate rev5后放行旧delete rev4，不能删除rev5。
- [ ] 连续离线变更多次、在途请求期间修改，最终只留下最新位置，无旧ACK误清新pending。
- [ ] pending及已ACK状态下释放晚到GET，不能按服务器时间戳覆盖本地版本。
- [ ] 普通移出书架保留progress；永久删除后旧PUT/DELETE返回410且PG/MCP无已删数据。
- [ ] 切换账号、另writer同book冲突不会写入别人账户，不假确认失败操作。
- [ ] 旧客户端连接新backend：进度GET/POST/DELETE为428，本地与pending仍保留；升级后恢复。
- [ ] 新progress路径访问旧backend为404，客户端不fallback、不清pending；禁止以此作为提前
  发布整个新版客户端的理由。
- [ ] PG业务行/墓碑/ledger/user_sequence一致；只真实canonical变化产生ledger。
- [ ] 对照MCP书籍/历史查询核验PG；检查无新错误日志，再单独决定是否生产发布。
