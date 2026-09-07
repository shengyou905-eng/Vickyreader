# Reliable Upload: revision 与永久删除

后续进度版本修复及最新验收结论见 [progress revision closeout](reliable-upload-progress-revisions.md)。
下文保留上一轮审计历史，包含当时尚未修复的progress blocker。

本轮仅实现 trace 的持久化版本，以及服务端按用户/书籍永久清理。
未 commit / push / deploy，未执行生产 migration，未修改生产配置、MCP contract 或前端 UI。
旧的 closeout 文档保留为历史记录，本文件描述本轮结果。

## 根因与版本规则

旧 pending.generation 随队列行清除而丢失，而且没有发给服务器。
服务端硬删除后没有版本记录，所以旧 DELETE 能删除新实体，旧 PUT 也能复活已删除实体。

现在客户端同时保留两套计数：

- generation：仍用于本地在途请求 ACK / retry 更新的条件，防止误清新 pending。
- client_revision：独立 `upload_entity_revisions` 表按(user_id, entity_type, entity_id)长期保存，
  pending被确认删除后仍然存在。实体新状态递增；同一操作重试、相同快照复发沿用原值。
- upload_writer：SQLite中持久化的安装写入UUID，不是token或授权secret。
- state_hash：操作类型和规范化payload的SHA256，仅用于判定同一状态；不保存第二份正文。
- SQLite16升级时给已有pending填入client_revision并保存原payload指纹；不会清队列。
  generation仅作为旧队列首次版本的种子，之后两个计数的生命周期分离。

### HTTP

`PUT /api/entries/client/:clientEntryId` 的完整实体body增加：

```json
{
  "writer_id": "11111111-1111-4111-8111-111111111111",
  "client_revision": 6,
  "source": "thought",
  "book_id": "example-book-id",
  "user_input": "test example only"
}
```

DELETE使用同一路径，JSON body仅需writer_id和client_revision。
user_id始终取JWT认证上下文；body、query里的user_id不参与权限选择。
revision必须为1至9007199254740991的整数，writer_id必须是UUID。

服务端 `user_entry_upload_states` 主键为(user_id, client_entry_id)，保存writer_id、
latest_revision、deleted、book_id、request_hash、updated_at。没有正文、想法或AI答案副本。

| 请求 | 处理 |
| --- | --- |
| 首次有效revision | 锁定该identity的writer并执行 |
| 大于latest_revision | 执行完整新状态，允许跳号（合并掉的中间状态不必上传） |
| 等于latest_revision且request_hash一致 | 幂等重放，不重复业务变更/ledger |
| 小于latest_revision | 409 Stale upload revision；不改变任何数据 |
| 同版本但payload/操作不同 | 409；不允许版本复用 |
| 不同writer | 409；不把不同设备各自的计数当作同一时钟 |
| 缺少/非法版本 | 428；旧客户端必须升级，不能无版本写入 |
| 永久删除的book_id | 新写入410；永久删除前的精确重放也不会恢复实体 |

一个稳定client_entry_id不能迁移到另一book_id。旧UUID删除/重要标记接口不能绕过已绑定
client identity的版本保护；带local_id的旧POST也要求改用版本化PUT。

多设备写同一client_entry_id、恢复旧数据库造成版本落后时，选择拒绝覆盖而非自动加号
重试。失败保留pending和退避，不自动改writer/版本、不假装成功。writer交接/冲突解决UI
本轮不实现。不同设备新建的不同UUID trace正常独立上传。

## recreate 与 tombstone

普通trace删除：canonical row硬删除，upload state保留latest_revision和deleted=true。
同writer以更大的revision PUT可重建同一client_entry_id；新canonical UUID可能不同。
例如create1 → delete2 → create3后，迟到delete2返回409，新记录保留。
delete3之后迟到update2同样返回409，不复活。删除不存在的实体也保留版本墓碑。

墓碑长期保留，仅账号物理删除时通过users外键级联移除。本轮没有TTL/GC。
未来GC必须证明旧客户端、旧备份、重试请求都不可能重新到达；不能按日期直接删状态。

## 事务与永久删除

新增 `DELETE /api/library/books/:bookId/data`，要求正常App JWT，不是MCP token。
输入只有book_id；客户端不枚举远端trace，所有权仅来自认证用户。

所有三个canonical实体的repository写入先取得同一用户的sync_user_cursors行锁，再取业务
锁；版本操作和永久清理遵循相同顺序。不同用户不使用全局锁。
业务数据、版本状态/永久删除标记、sync_changes和user_sequence在同一个pg transaction中。
版本落后/重放不会制造ledger；只有真实canonical创建/修改/删除才写对应事件。
revision-only元数据变化或删除从未存在的实体不会伪造trace deleted事件。

永久清理会：

1. 插入(user_id, book_id)永久删除标记。
2. 标记该书已有trace版本状态为deleted，保留版本信息。
3. 删除该用户该书全部user_entries，包括其他设备独有的四类trace及manual。
4. user_entry_follow_ups按现有FK随canonical entry删除，不扩展聊天同步。
5. 删除reading_progresses及user_library_books，对每条实际删除写ledger。
6. 重复请求无新增业务删除事件。未知book_id只建立防复活标记，不伪造不存在的删除。

本地service清理本机划线、notes、canonical traces、对应follow-up、书签和进度，随后在
同一SQLite事务入队一个book:purge；断网/重启后继续调用上述事务。取消本机该书旧trace/
progress pending，但不依赖这些ID来决定云端清理范围。

PostgreSQL当前没有独立的私人highlights/thoughts/bookmarks表：前两者是user_entries
subtype，bookmarks只有SQLite。因此不会虚构云端书签删除，也不能远程抹除其他设备尚未
同步的本地书签。其他设备旧trace/进度重传会被服务器书籍标记拒绝。

永久删除后的同一个book_id不可恢复。旧书架快照会过滤该ID，旧trace/进度写入被拒绝。
重新导入产生新book_id才允许作为新书保存；无需书架CRDT或新的同步实体。
客户端本地也保留书籍删除标记，防止同ID重新入架、重新写历史导致假同步成功。

普通removeFromLibrary保持不变：只归档/移出书架，保留trace和progress，MCP仍可读取。
permanent操作后MCP看不到这些已删除canonical对象。个人文件保留既有策略；本地保留
归档元数据锚点，以免完整私有聊天被本地book FK误删。
free_notes、完整小U聊天、公开发布/评论/社区实体均不在本次清理与同步范围。

## Migration 005 与上线约束

- 新增005_upload_revisions.up.sql，没有修改本轮之前的003/004。
- 新建upload state和permanently_deleted_books两张元数据表及(user_id,book_id)索引。
- 从003/004状态升级；已有非空client_entry_id仅建立revision0、writer尚未认领的状态。
  不删除历史实体、不改created_at/updated_at、不生成baseline ledger。
- CREATE IF NOT EXISTS + INSERT ON CONFLICT DO NOTHING支持对预期schema重复执行，
  已有高版本和墓碑不会被覆盖；意外schema漂移仍需先审计，不能依靠IF NOT EXISTS修复。
- 005自带BEGIN/COMMIT和5秒lock_timeout。DDL及外键会取得关系锁，回填也会持有行锁；
  需在恢复库测量耗时、低峰执行。5秒只限制等待锁，不是总耗时上限。
- 正确顺序：备份/恢复演练 → 确认003/004 → 停止并排空旧写入进程 → 005 → 新后端
  → API回归 → SQLite16客户端灰度 → 真机验收。不能新旧后端写入代码混跑。
- 旧无revision客户端会收到428，必须升级；不能为“兼容”放开无版本DELETE。
- 不回退到不懂版本/墓碑的后端，不DROP这些表做回滚；否则旧请求会再次合法化。
- 本轮仅在127.0.0.1独立Docker PostgreSQL16空库执行迁移/测试，未访问生产。

## 验证与尚存阻塞

本轮最终执行结果：

| 检查 | 结果 |
| --- | --- |
| Flutter可靠队列 + 删书测试（真实临时SQLite） | 21/21 |
| Backend reliable upload / ledger / HTTP | 20/20 |
| MCP regression | 17/17 |
| 独立PostgreSQL16并发、版本、永久清理、migration回归 | 16/16断言；含一项确认尚存progress缺陷的diagnostic，不代表该缺陷通过验收 |
| dart analyze | exit 0；仅既有share_service.dart:64的BuildContext info |
| npm run check + check:reliable-upload | 通过 |

自动测试包括真实SQLite重启/升级、revision不重置、退避重试、云端未知trace永久清理，
真实PostgreSQL旧PUT/DELETE拒绝、writer隔离、墓碑重跑、事务失败回滚、并发清理与上传，
HTTP认证与参数校验，以及既有MCP17项回归。MCP五工具的schema/transport/auth未改变；
mcp.repository.js改动只在私有书架写入路径增加统一锁与永久删除过滤。

本轮指定的两个blocker已经关闭。但是**整个Reliable Upload仍不能封板**：真实PG核验
发现，未永久删除书籍的reading_progress upsert仍未使用request revision。0.8先提交，
迟到的旧0.2请求随后提交，会把进度退回0.2。新增diagnostic断言确认的是这个问题存在，
不是成功验收。此风险位于readingProgress.repository.js的普通upsert，不是book永久
删除路径；依照“只解决两个blocker”的范围，本轮没有增加第三套实现。

最小后续修复：给progress持久化请求版本/删除状态并在相同用户事务内校验，重试沿用
原版本；阅读进度可以合法向后移动，不能简单取max(progress)掩盖旧请求问题。

其他登记边界：200本快照限制、多设备完整replace冲突（含过时快照覆盖）、writer交接、
旧备份恢复冲突、墓碑GC、其他设备本地历史清理通知，均未扩展。
409/410/428保留待处理操作并退避，尚无新冲突处理UI；单条失败不会阻塞其他到期实体。

## 下一步真机 checklist

仅专用测试账号和测试书，先在非生产环境进行；不输出token、正文或完整数据库副本。

- [ ] 开发签名真机从SQLite15升级16，原pending、writer_id、revision正确保留。
- [ ] 正常上传create1，确认pending清空；断网delete2，强杀App并重启，仍为revision2。
- [ ] 连续失败/响应丢失重试，发送的writer_id和revision保持不变。
- [ ] delete2后同client_entry_id recreate3；受控延迟旧delete2至create3提交后再放行，
  返回409，MCP/PG仍为新trace，ledger没有第二次删除。
- [ ] delete3后释放迟到update2；返回409，PG只保留tombstone，MCP不可见。
- [ ] update2后释放update1；最终内容保持update2。
- [ ] A设备上传该书四类trace；B设备无对应本地trace，调用服务方法永久删除该book_id。
- [ ] B离线调用后杀进程，联网重启：一个book:purge成功，全部目标远端数据消失，
  MCP get_book_traces为空、get_trace不存在，其他用户和其他书数据不变。
- [ ] 重放永久删除：无重复ledger；A旧trace/进度上传被拒绝，旧书架快照不能恢复书籍。
- [ ] 普通移出书架只产生book删除事件，trace/进度仍可被MCP读到。
- [ ] 相同writer不同revision、不同writer相同ID冲突符合规则，冲突操作不被假确认清空。
- [ ] 本地SQLite队列核验与服务端ledger核验遵循原closeout文档，只导出ID/计数/状态。
- [ ] 修复独立的progress迟到回写问题并增加真机复测后，才能重新评估整体封板。

## 本轮文件

- backend/package.json
- backend/src/db/migrations/005_upload_revisions.up.sql
- backend/src/db/schema.sql
- backend/src/repositories/uploadState.repository.js
- backend/src/repositories/bookDeletion.repository.js
- backend/src/repositories/entry.repository.js
- backend/src/repositories/readingProgress.repository.js
- backend/src/repositories/mcp.repository.js
- backend/src/controllers/entries.controller.js
- backend/src/controllers/library.controller.js
- backend/src/routes/library.routes.js
- backend/src/controllers/reliableUpload.http.test.js
- backend/src/repositories/reliableUpload.repository.test.js
- backend/src/repositories/syncChange.repository.test.js
- backend/src/repositories/syncChange.postgres.test.js
- lib/config/constants.dart
- lib/services/database_service.dart
- lib/services/upload_revision.dart
- lib/services/reliable_upload_service.dart
- lib/services/bmob_api.dart
- lib/services/book_service.dart
- test/services/reliable_upload_service_test.dart
- test/services/book_removal_test.dart
- docs/reliable-upload-revision-fences.md
- docs/reliable-upload-closeout.md（仅增加指向本轮报告的说明）
