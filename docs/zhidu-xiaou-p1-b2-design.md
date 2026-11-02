# 知读小U P1-B2 详细设计与实施审批稿

日期：2026-10-21。状态：**设计草案，未实施、未执行 SQL、未验证 PostgreSQL DDL**。

依据：P1 产品契约、`zhidu-xiaou-p1-b1.md`、`zhidu-xiaou-p1-b2-storage-proposal.md` 及本轮源码核对。此前草案中关于云端权威、未同步草稿、离线占位、删除专属追问和私有反馈的产品选择，已由用户确认；本稿不再将这些选择列为待决问题。

## 1. 交付范围与不变量

- 完整保留知识整理、我的思考、可选继续思考、证据引用、继续追问、保存、删除、基础反馈；本稿只细化存储和接口，不交付 UI。
- 云端为账号级权威，本地为可失效缓存。未同步或不能确认所有权的材料只能生成本机草稿，不显示账号保存成功，不触发隐式上传。
- 云端缓存离线重新打开只显示通用占位；书名、问题、摘要、引文、反馈等私人内容都不放在占位中。
- 不复制原始阅读历史；不合并同文独立阅读行为；不接入随心记，即使曾授权其他小U功能也排除。
- 删除回望不修改原始记录；删除原始依据后，派生结果及专属追问不能从旧缓存、通用对话接口或迟到响应恢复。
- 五种免费模式、原文长预览、IAP、Pro、Obsidian 协议、明台分享规则不变。不开放额外权限或付费能力。

## 2. 本轮核实的现状与适配点

| 源码位置 / 函数 | 已核实事实 | 对 B2 的影响 |
| --- | --- | --- |
| `lib/services/epub_service.dart` import、`txt_service.dart` import | 未传 bookId 时使用 UUID v4 | 同文件在不同设备独立导入不保证相同 ID，不能按标题、文件名猜配 |
| `lib/services/book_service.dart` publicShelfBookId / borrowMingtaiBook | 明台书架 ID 为 `mingtai_<publicId>` | 是既有来源身份，不把 PostgreSQL `books.id` 当成本地 bookId |
| `backend/src/db/schema.sql` user_library_books | `(user_id, book_id)` 主键，只有书架元数据 | 可查身份/展示信息，不是完整原书证据；不能强制依赖该行存在 |
| `backend/src/repositories/entry.repository.js` upsertEntryByClientId | `(user_id, client_entry_id)` 唯一，已有关联书籍不可变校验 | 解析本地身份到云端 UUID；不能只凭客户端传来的 remote ID |
| 同文件 createFollowUp | 锁父 trace，但不更新父时间/同步版本 | 仅看父 updated_at 会漏掉追问变化；需要追问集合指纹和失效钩子 |
| `uploadState.repository.js` lockUploadUser / beginEntryWrite | 基于 sync_user_cursors 的用户级锁和 writer/revision | 可复用锁顺序，不复用上传 revision 作为回望请求序号 |
| `bookDeletion.repository.js` permanentlyDeleteBookData | 永久删书围栏 + 删除 trace/progress/书架；原注释明确普通私有聊天不动 | 需增加仅针对回望专属对话的清除，不扩大到普通聊天 |
| `mcp.repository.js` syncLibraryBooks / deleteLibraryBook | 书架元数据可移除，与永久删书分开 | 移出书架不等于删除阅读依据，不直接清除回望 |
| `xiaouConversation.repository.js` create/list/get/append/delete | 创建只接受 chat/xiaou_asks；列表含 last_message，读取无来源失效检查 | 不能直接把回望当 chat；必须隔离通用入口与新受控入口 |
| `xiaouConversation.controller.js` appendMessage | 客户端能提交 role=assistant 的普通对话消息 | 回望专属入口只能提交问题，助手回答只能来自服务端生成流程 |
| `lib/services/xiaou_conversation_service.dart` _send | 捕获 AuthSessionScope 并在返回时 check | 复用 epoch 机制，新增保存/展示前再次核对，不仅靠 HTTP 返回校验 |
| `bookRecapContract.js` / `bookRecapGeneration.js` | B1 的指纹、引用、范围和预算为纯函数 | 保留；新增服务端证据解析适配器。指纹不是认证或书籍真伪证明 |
| `backend/src/db/init.js` | 直接执行 schema.sql | 不能拿此脚本当存量库迁移器，它包含已有 UPDATE/DDL |
| migrations 目录 | 当前已有 001–009，部分有 down | 候选下一编号 010，实施时再核对；本轮不创建迁移文件 |

## 3. 跨设备书籍身份与可信边界

### 3.1 身份规则

权威键为部署环境 + 认证 userId + 原有 bookId；数据库通过测试/正式独立实例隔离环境，不接受客户端设置 environment。客户端缓存必须另加 API origin。

1. 同一账号设备 B 可从回望列表打开设备 A 已保存的回望，不要求 B 已有原书。
2. 只有本地同 bookId、可核对文档版本和位置时才启用精确跳转；否则展示合法存留的依据并说明原书不可定位。
3. B 独立导入同名/同内容文件产生另一 ID 时不自动合并、不重写 trace bookId。本轮不建立书籍同一性猜测服务。
4. `client_entry_id` → 云端 `user_entries.id` 必须经 userId + bookId 查询得到；旧记录无 client_entry_id 时只允许已授权云端 UUID，不用时间/文本猜测映射。
5. follow-up 使用云端 UUID，并核对父 entry 及双方 owner；本地无 remote_id 的追问不具备账号保存条件。
6. 永久删除围栏不可绕过。重新导入使用新的书籍身份，不能复用已删除 bookId 恢复旧回望。

因此“跨设备可再次查看”可以实现；“任何设备独立重导入后自动跳回相同版本”现有身份体系不支持，本轮不宣称支持。

### 3.2 客户端不能自证

新云端接口接收选择的来源 ID 和期望版本，不接收完整 snapshot、任意 result_json、is_valid、用户 ID 或自报完成状态作为可信事实。服务端重读所属资料、分类和计算快照/引用 ID，再调用 B1 契约。客户端 checksum 仅用于发现偏差。

- `user_entries` 的文本和 metadata 最初也来自客户端。服务器能证明它属于当前账号且版本一致，**不能证明它是正版全书或作者原话**。
- 有明确保存的阅读上下文时，可作为“用户阅读记录中保存的原文片段”；provenance 仍为 reader_context，来源视图标明这一事实。客户端文档匹配不能冒充服务器亲自核对原书。
- 云端没有本地 highlights/notes 业务表：不能仅凭 source_record_id 或 original_text 就复制 B1 的 business_record 证明。缺乏来源依据的旧片段保持 unverified，不补造。
- 本地当前文档补充、待上传修改/删除、未同步追问只参加本机草稿。云端生成前，客户端必须比较选中资料的本地状态；发现 pending 时不退回分析旧云端文本冒充最新版本。
- B1 本地指纹和云端规范化指纹不保证相同：云端按 `client_entry_id || remote UUID` 生成稳定内部身份，返回经 owner 校验的映射及覆盖范围；不为匹配哈希而改写原历史。
- 默认拒绝混合“可验证云端来源 + 不可验证本地材料”的账号保存。用户可以明确重新选择仅云端部分，覆盖范围需重新告知。
- 仅私有记录、合法来源类型和明确 reader/xiaou_asks 分类进入；xiaou_asks 开场白仍为 AI，不认作书籍原文。未知归属或私密来源不能靠补 metadata 认领。

## 4. 持久化结构

建议 **4 张新表 + 现有对话表一个关联字段及约束**。比上轮三表方案增加无正文的 operation 表，用于生成/追问等请求防重、取消及迟到结果围栏，不是第二套历史。

- reading_recaps：派生结果、状态、范围；生成预览可暂存，只有 is_saved=true 才显示账号收藏保存成功。
- reading_recap_sources：所有实际发送给模型的依赖，而不只是答案最终引用的依赖。记录父 trace、追问集合和书籍身份。
- reading_recap_feedback：账号私有反馈。
- reading_recap_operations：请求 ID、HMAC、状态和生成代次，不保存 Prompt、输入正文、回答或完整错误。
- xiaou_conversations.recap_id：一份回望对应一个专属私有会话；继续使用 xiaou_messages 保存实际对话，不复制到 user_entry_follow_ups。

### 4.1 PostgreSQL DDL 草案

以下 SQL **仅文档草案**；不是已执行或可直接上线的 migration。省略 IF NOT EXISTS 是为了不掩盖同名异构结构；正式 migration 应先做目录核对，已应用则跳过，部分结构存在则拒绝并人工审查。复用已有 pgcrypto / gen_random_uuid，不引入新扩展。

```sql
CREATE TABLE reading_recaps (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  book_id TEXT,
  state TEXT NOT NULL CHECK (state IN (
    'prepared','generating','ready','stale','invalidated','deleted',
    'failed','cancelled','expired')),
  is_saved BOOLEAN NOT NULL DEFAULT false,
  revision BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
  schema_version INTEGER NOT NULL DEFAULT 1 CHECK (schema_version > 0),
  prompt_version TEXT,
  source_fingerprint TEXT CHECK (source_fingerprint ~ '^[a-f0-9]{64}$'),
  selected_sources_json JSONB,
  coverage_json JSONB,
  result_json JSONB,
  requested_model TEXT,
  returned_model TEXT,
  input_tokens BIGINT CHECK (input_tokens >= 0),
  output_tokens BIGINT CHECK (output_tokens >= 0),
  elapsed_ms BIGINT CHECK (elapsed_ms >= 0),
  cost_amount NUMERIC(18,8) CHECK (cost_amount >= 0),
  cost_currency TEXT,
  pricing_version TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  UNIQUE (id, user_id),
  UNIQUE (id, user_id, book_id),
  CHECK (book_id IS NULL OR
    (length(book_id) BETWEEN 1 AND 200 AND btrim(book_id) = book_id)),
  CHECK (state IN ('deleted','invalidated') OR book_id IS NOT NULL),
  CHECK (state <> 'ready' OR
    (result_json IS NOT NULL AND source_fingerprint IS NOT NULL
     AND prompt_version IS NOT NULL AND coverage_json IS NOT NULL
     AND selected_sources_json IS NOT NULL)),
  CHECK (state = 'ready' OR result_json IS NULL),
  CHECK (coverage_json IS NULL OR jsonb_typeof(coverage_json) = 'object'),
  CHECK (selected_sources_json IS NULL OR
    (jsonb_typeof(selected_sources_json) = 'array'
     AND octet_length(selected_sources_json::text) <= 65536)),
  CHECK (result_json IS NULL OR
    (jsonb_typeof(result_json) = 'object' AND octet_length(result_json::text) <= 131072)),
  CHECK ((state = 'deleted') = (deleted_at IS NOT NULL)),
  CHECK (NOT is_saved OR state IN ('ready','stale','invalidated')),
  CHECK (state NOT IN ('deleted','invalidated') OR
    (book_id IS NULL AND source_fingerprint IS NULL AND coverage_json IS NULL
     AND selected_sources_json IS NULL
     AND prompt_version IS NULL AND requested_model IS NULL AND returned_model IS NULL
     AND input_tokens IS NULL AND output_tokens IS NULL AND elapsed_ms IS NULL
     AND cost_amount IS NULL AND cost_currency IS NULL AND pricing_version IS NULL))
);
CREATE INDEX idx_reading_recaps_owner_list
  ON reading_recaps (user_id, updated_at DESC, id DESC) WHERE is_saved;
CREATE INDEX idx_reading_recaps_owner_book
  ON reading_recaps (user_id, book_id, state);
CREATE INDEX idx_reading_recaps_expiry
  ON reading_recaps (expires_at) WHERE NOT is_saved AND expires_at IS NOT NULL;

CREATE TABLE reading_recap_sources (
  recap_id UUID NOT NULL,
  user_id UUID NOT NULL,
  book_id TEXT NOT NULL,
  evidence_id TEXT NOT NULL CHECK (length(evidence_id) BETWEEN 1 AND 256),
  entry_id UUID NOT NULL,
  follow_up_id UUID,
  client_entry_id TEXT,
  source_field TEXT NOT NULL CHECK (length(source_field) BETWEEN 1 AND 128),
  source_kind TEXT NOT NULL CHECK (source_kind IN (
    'book_excerpt','highlight','user_note','user_question','historical_ai','ai_prompt')),
  provenance TEXT NOT NULL,
  source_digest TEXT NOT NULL CHECK (source_digest ~ '^[a-f0-9]{64}$'),
  follow_up_set_digest TEXT NOT NULL CHECK (follow_up_set_digest ~ '^[a-f0-9]{64}$'),
  observed_revision BIGINT CHECK (observed_revision >= 0),
  observed_writer_id UUID,
  locator_json JSONB NOT NULL DEFAULT '{}'::jsonb
    CHECK (jsonb_typeof(locator_json) = 'object' AND octet_length(locator_json::text) <= 2048),
  PRIMARY KEY (recap_id, evidence_id),
  FOREIGN KEY (recap_id, user_id, book_id)
    REFERENCES reading_recaps(id, user_id, book_id) ON DELETE CASCADE
);
CREATE INDEX idx_recap_sources_entry ON reading_recap_sources(user_id, entry_id);
CREATE INDEX idx_recap_sources_follow ON reading_recap_sources(user_id, follow_up_id)
  WHERE follow_up_id IS NOT NULL;

CREATE TABLE reading_recap_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recap_id UUID NOT NULL,
  user_id UUID NOT NULL,
  client_request_id UUID NOT NULL,
  item_id TEXT CHECK (length(item_id) BETWEEN 1 AND 256),
  category TEXT NOT NULL CHECK (category IN ('inaccurate','low_value','wrong_relation')),
  comment TEXT NOT NULL DEFAULT '' CHECK (length(comment) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, client_request_id),
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE
);
CREATE INDEX idx_recap_feedback_owner ON reading_recap_feedback(user_id, recap_id);

CREATE TABLE reading_recap_operations (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_id UUID NOT NULL,
  recap_id UUID NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('prepare','generate','save','follow_up','feedback')),
  request_mac TEXT CHECK (request_mac ~ '^[a-f0-9]{64}$'),
  mac_key_version TEXT,
  expected_revision BIGINT NOT NULL CHECK (expected_revision > 0),
  generation_id UUID NOT NULL DEFAULT gen_random_uuid(),
  status TEXT NOT NULL CHECK (status IN (
    'running','succeeded','failed','cancelled','interrupted','expired','revoked')),
  result_id UUID,
  error_code TEXT,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  deadline_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, request_id),
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE,
  CHECK (status <> 'running' OR finished_at IS NULL)
);
CREATE INDEX idx_recap_ops_recap ON reading_recap_operations(user_id, recap_id);
CREATE UNIQUE INDEX idx_recap_ops_one_model_request
  ON reading_recap_operations(user_id, recap_id)
  WHERE status = 'running' AND operation IN ('generate','follow_up');

ALTER TABLE xiaou_conversations ADD COLUMN recap_id UUID;
ALTER TABLE xiaou_conversations ADD CONSTRAINT xiaou_recap_owner_fk
  FOREIGN KEY (recap_id, user_id) REFERENCES reading_recaps(id, user_id) ON DELETE CASCADE;
ALTER TABLE xiaou_conversations ADD CONSTRAINT xiaou_recap_kind_ck CHECK (
  (recap_id IS NULL AND kind <> 'book_recap') OR
  (recap_id IS NOT NULL AND kind = 'book_recap')
) NOT VALID;
CREATE UNIQUE INDEX idx_xiaou_conversation_recap
  ON xiaou_conversations(recap_id) WHERE recap_id IS NOT NULL;
```

约束说明：

- 不引用公共 `books(id)`，也不 FK 到可移出书架的 user_library_books。删除书架元数据不能误级联删除回望。
- source 不 FK 到原 trace/follow-up：硬删原记录时不能被依赖阻断，也不能 CASCADE 掉依赖却留下正文。依赖归属由**服务端解析 + 同一用户锁内查询**验证，来源删除钩子须在原事务中先清理派生正文。这里只对派生 parent 使用 owner/book 复合 FK。
- 应用数据库角色仍需具备这些表的最小所需权限；当前方案不假设已经启用 PostgreSQL RLS。任何 raw SQL/repository 入口都必须显式带认证 user_id，测试应直接覆盖 repository 而不只测 controller。
- locator_json 只允许章节 sourceIndex、文档版本摘要、offset、定位状态等白名单，不允许原文、文件路径、任意 metadata；provenance 和 result JSON 由严格应用 schema 校验，SQL 类型检查不能替代它。
- selected_sources_json 只保存经授权解析的 trace/追问 UUID、选择模式和版本摘要，最多80条 trace；不含书名、问题、原文或答案。它保留显式空追问选择及无可用片段记录的范围语义，不能拿任意客户端JSON直接落库。
- user_entries legacy updated_at 不是唯一版本。source_digest 覆盖所有参与生成的内容/来源/时间；follow_up_set_digest 覆盖排序后的追问 ID、内容及时间，捕获新增、删除、修改；observed_revision/writer 仅在既有 ledger 存在时填入。
- request_mac 是服务端独立密钥的 HMAC，不存低熵问题的裸哈希。不得复用 Apple/JWT 私钥。key version 支持轮换；密钥丢失时旧 key 请求拒绝重放，不重新执行。
- result_id 只指向本操作的回望/助手消息/反馈 ID；绝不在 operation 中存可回放的正文。读取操作结果始终重新授权、检查回望有效性。
- 原 xiaou_messages 已有 conversation FK 和 user FK；B2 写入强制同一 owner，来源只从受控会话读取。数据库并无消息 owner 与 conversation owner 的复合约束；本期通过专属 repository 保证，合成测试必须注入错 owner 并验证拒绝。可选补强复合 FK 必须先单独审查旧数据，不静默修改历史。
- deleted / invalidated 保留极小防复活标识（id、owner、状态、版本、时间及保存标记），不保留 bookId、指纹、覆盖信息或私人正文；先删 sources 后才能清空 bookId。账号删除级联清理。
- 对话 kind 约束 NOT VALID 仍约束新增/更新行；实施前只读查旧 kind 分布，若有不兼容旧值则停，不重命名用户历史。通过后再单独 VALIDATE。

### 4.2 生命周期与保留期限建议

- prepared → generating → ready；ready + save → is_saved=true。两次用户主动生成用不同 recap ID，不按文本去重。
- 取消/失败/超时结果不得进入 ready；缺乏发现可以 ready 且结构数组为空，不伪造成功正文。
- edited → stale：清除 result_json 和专属对话正文，保留非正文依赖用于提示/重新选择；不提供旧正文入口。
- source deleted → invalidated：删除来源依赖、反馈、专属对话，清空正文和身份快照；is_saved 可保留，只显示通用失效占位。
- user delete → deleted：同样清理，并 is_saved=false、deleted_at=now()；旧 ID 永不复用。
- 建议 prepared 30 分钟、未保存 ready 24 小时有效；过期读请求立即拒绝正文，清理由显式后台任务处理。数值为待审批配置，不是当前行为。
- operation HMAC/模型元数据建议 30 天后清除；只保留 request ID / recap ID / revoked 或 expired 状态到账号删除，防旧请求再次执行。deleted recap 最小围栏同样保留到账号删除。无正文标识仍是账号数据，需要说明保留用途。
- 未保存预览也在受控服务器短暂保存，UI 必须区分“临时结果”与“已保存到账号”；不把自动预览写入收藏。

## 5. API 契约草案（全部新增，尚不可调用）

基础路径 `/api/xiaou/recaps`；沿用 App auth 的 req.user.id，拒绝 MCP / Obsidian token。生成和追问额外复用 requireAiConsent，并绑定一次明确的单书资料范围确认。模型名称、价格、权限不从客户端请求中指定。

请求/响应使用现有 snake_case envelope，内部 B1 result_json 保持原 camelCase schema，不改 B1 原协议。BIGINT revision 以十进制字符串传输。错误沿用 `{error,error_code}`；不得包含证据正文、SQL 或上游原始错误。

所有读取/生成响应 `Cache-Control: no-store, private`；不借助 HTTP 304 绕过来源复核。客户端显式私有缓存独立管理。ETag 仅作 If-Match 写入前置条件，不作为长效展示授权。

| 方法 / 相对路径 | 请求要点 | 成功和重试语义 |
| --- | --- | --- |
| POST `/prepare` | recap_id(UUID，由客户端生成)、request_id、book_id、selected_sources(1..80) | 201 返回 plan、范围、不可验证原因、revision、source_fingerprint、expires_at；同请求同内容 200，同 ID 异内容 409；不调用模型 |
| POST `/:id/generate` | request_id、If-Match、source_fingerprint、consent_scope_fingerprint | 202 operation；固定一次上游尝试，无自动重试；已有请求返回同 operation；结果经 GET 获取 |
| GET `/:id/operations/:requestId` | 无请求体 | 200 状态及无正文结果指针；finished 不等于当前仍有效，正文另查 |
| POST `/:id/operations/:requestId/cancel` | 无请求体 | 204 幂等；已经完成返回 409 RECAP_ALREADY_COMPLETED；取消不是删除 |
| PUT `/:id/save` | request_id + If-Match；不接受 result_json | 200 `{recap:{id,is_saved:true,revision}}`；仅 ready 且来源仍有效可保存 |
| GET `/` | book_id 可选、limit默认20上限50、cursor | 200 `{recaps,next_cursor}`，只列已保存；不返回摘要/引文/问题；有效项书名也需权限复核 |
| GET `/:id` | 无请求体 | 200 `{recap:{...,result,coverage},validation:{revision,source_fingerprint}}`；重新核验全部依赖 |
| GET `/:id/evidence/:evidenceId` | evidenceId 必须来自该回望依赖 | 200 `{evidence:{kind,text,source,location}}`，从现存原记录读取最小对应字段；未精确定位时明确 status |
| GET `/:id/conversation` | 私有专属入口 | 200 `{conversation:{...,messages}}`；每次核验回望和来源，不复用无校验的通用读取 |
| POST `/:id/follow-ups` | request_id、If-Match、item_id可选、question(1..4000字符) | 202 operation；客户端不能指定 assistant/历史；服务端加载当前结果、来源和完整历史轮次 |
| POST `/:id/feedback` | request_id、If-Match、category、item_id可选、comment(<=1000) | 201 `{feedback:{id}}`；同请求重复返回同 ID，异内容409 |
| DELETE `/:id` | 认证账号 + recap UUID | 204；同账号重复204，其他账号404；包含删除先于迟到 prepare 的围栏语义 |

prepare source 格式：`{entry_id, expected_digest, follow_up_ids}`；entry_id 与 client_entry_id 只选一个。expected_digest 为先前服务端返回的版本摘要，首次无摘要则 prepare 返回新摘要供确认。请求不接受私密正文上传。HTTP 输入体建议上限 64 KiB；超过返回413，不截断。

prepare 在服务端枚举所选 trace 的当前追问，核对客户端列出的 follow_up_ids 与实际选择。默认包括选中 trace 的完整已有追问；任何明确选择子集须反映 coverage。客户端报告有 pending 或缺失远端身份即返回 `RECAP_LOCAL_DRAFT_ONLY`，不自动上传、不暗中舍弃这些资料。

省略 follow_up_ids 表示包含当前全部追问；显式空数组表示用户选择不包含追问，两者不能混淆。范围确认必须包含这一差异；无效/越权 ID 全部拒绝，不自动过滤后成功。prepare 失败不留下可生成的 prepared 记录。

覆盖说明必须包含已选择 trace 数、实际发送证据数、追问数、排除项及 fullBook=false。依赖缺失/冲突不自动缩小请求范围；返回冲突供用户重新选择。非正文 header 不代表服务器读过完整书。

示例（所有 UUID 均为占位合成身份）：

```json
{
  "recap_id": "11111111-1111-4111-8111-111111111111",
  "request_id": "22222222-2222-4222-8222-222222222222",
  "book_id": "synthetic-book-v1",
  "selected_sources": [{
    "entry_id": "33333333-3333-4333-8333-333333333333",
    "follow_up_ids": []
  }]
}
```

```json
{
  "operation": {
    "request_id": "44444444-4444-4444-8444-444444444444",
    "recap_id": "11111111-1111-4111-8111-111111111111",
    "status": "running"
  }
}
```

```json
{
  "error": "回望依据已发生变化，请重新整理",
  "error_code": "RECAP_SOURCE_CHANGED"
}
```

分页使用已签名且绑定账号/过滤条件的 `(updated_at,id)` keyset cursor；不复用 Obsidian cursor/snapshot，不往 sync_changes 加 recap entity_type。列表移动导致的重复由 ID 消除，显式刷新新页；不承诺任意变动期间完整快照遍历。

错误：401登录失效；403未同意AI范围；404不存在/他人资源；409请求内容冲突、来源变化、另一生成进行中；410来源删除、回望删除/过期；412 If-Match版本过旧；422范围过大、证据不足或仅本机草稿；429并发/频率限制；503暂时不可用。无论哪种错误，都不能从旧缓存恢复正文。

generation/follow-up 初版采用202 + 状态查询，不把半段流保存为成功。既有 SSE 接口完全不改；以后若增加流式展示仍以服务端完整完成、来源复核和状态提交为准。

## 6. 事务、幂等与删除竞态

### 6.1 锁顺序

所有回望与涉及依赖的写操作统一：

`lockUploadUser(userId) → 原 trace/追问（按 UUID 排序）→ recaps（按 UUID 排序）→ operation → 专属 conversation → message/feedback`。

模型网络请求绝不持有事务。B2 createFollowUp 必须先取得用户锁，再锁父记录；否则其现有父行先锁顺序会与回望流程死锁。这是一处必要且需审批的既有 repository 修改，不改变 HTTP 或同步协议。

用户级锁由现有 sync_user_cursors 承载，不推进游标、不增加新 sync_changes 类型。它会短暂竞争现有上传，应限制候选数、查询时长并测试锁等待。超时回滚返回可重试错误，不持锁等待模型。账号删除依靠 FK 防迟到写入，并在保存时重读有效 users；与账号删除交错导致的死锁/序列化失败必须整体回滚，不能重放模型调用。

### 6.2 prepare / generate / save

1. prepare 短事务：认证、查永久删书围栏、解析 owner/book/trace/follow-up；建立 prepared 记录和全输入依赖；不调用模型。recap UUID 已是 deleted/invalidated 则410，不复活。
2. generate 短事务：拿用户锁；验证 If-Match、范围同意、全部版本和无 operation 冲突；保存 operation running + 随机 generation_id；recap 转 generating 并 revision+1；提交。
3. 事务外：只使用此份已验证内存快照构造请求，执行 B1 预算。最多一个上游尝试，不自动重试；不发送账号 ID、token、locator 路径、反馈或随心记。
4. 完成短事务：再次认证有效性、拿同一锁、确认 operation running/generation_id/recap revision、重读全部来源及追问集合。只有完整 finishReason=stop 且 B1校验通过才能写 ready/result；任何删除、取消、编辑或超时则拒绝保存并清理内存。
5. save 独立短事务：只接受服务器 ready 结果，不接受客户端上传答案；再次检查依赖，设 is_saved=true、revision+1。两设备同一 request_id 同内容返回同结果；同请求异内容409。

prepared 必须保存 selected_sources_json 的规范化选择描述、sources 的逐项依赖和生成时 coverage，而不是整份正文快照。重建只从当前原记录取字段，在所有依赖 digest 一致后使用已保存的范围统计；不因未选中记录后来新增而声称本次分析过它们。若无法按相同 schemaVersion 重建相同 source_fingerprint，拒绝继续生成/保存/展示，不依赖客户端补回旧正文。服务端验证输出前还要确认每个 evidenceRef 确实属于本次实际发送集合。

必须登记 **所有实际发送的来源**。未最终引用的某条批注也可能影响模型推断，删除该条仍须失效。所选 trace 的新增追问会使集合摘要变化；与本次未选择的其他痕迹新增不自动废弃历史范围，但 UI 明确“基于生成时选中的记录”。

### 6.3 崩溃、取消与防重边界

- 请求键 `(user_id, request_id)` + 操作名/recap/版本/规范化内容 HMAC；并发先查重，再读状态，避免成功重试被旧 If-Match误拒。重放也要先查删除/失效状态，不能返回旧正文。
- 请求行在调用上游前提交。进程在提交后、发送前崩溃可能造成一次未执行的失败；宁可显示 interrupted，不自动接管重发。
- 上游已收费但服务端未保存的崩溃无法保证供应商 exactly-once。超时记录转 interrupted/expired，原 request ID 不重新执行，用户明确重试用新 ID；客户端提示“结果未完成，重试可能再次调用”，不隐式循环。
- cancel 短事务取得用户锁，改 operation 状态并递增回望 revision；尽力 AbortController 停止网络，迟到完整响应也不能保存。不能保证供应商立即停止计费。
- 跟踪 operation 到 deadline 后仅改变状态、释放并发槽，不自动模型重试。旧 generation_id 永远无法提交。
- 回望删除即使先于 prepare 到达，也可为该账号申请的随机 recap UUID 建立无正文 deleted 围栏；同 UUID 属于其他账号返回404。限制此类删除请求速率，防围栏滥用。
- operation result_id 不是授权凭证；每次返回都要复查回望状态，不保存可回放的成功 HTTP 正文。

### 6.4 编辑和删除流程

| 操作 | 同事务行为 | 返回/缓存 |
| --- | --- | --- |
| 保存中用户编辑来源 | accepted 的原写入之后标记全部关联 recap stale，清除结果和专属对话/反馈，operation revoked，revision+1 | 旧结果409，无正文；新生成使用新 recap ID |
| 原 trace / follow-up 删除 | 删除前找依赖并标 invalidated；清除 result、sources、feedback、专属 conversation（级联messages）；再完成原删除 | 410；仅通用占位，禁止离线旧文回退 |
| 永久删书 | 同一事务按 user/book 找全部回望，执行上述 invalidation；已有原始删除逻辑继续，其他普通聊天不受影响 | 围栏阻止未来生成；丢失本地文件不走此流程 |
| 用户删回望 | 清空所有派生私密内容和依赖，删除专属conversation/反馈；operations revoked并清除MAC/result指针；保留最小deleted行 | 204；不删除任何原始 trace/note/highlight |
| 本地原书缺失 | 不修改云端回望或来源记录 | 依据可查看，跳转降级，不伪造位置 |
| 退出/切换账号 | 不删除云端结果；旧请求对新session无效 | 清内存及渲染授权；本地磁盘缓存按owner隔离，不回落旧账号 |

来源编辑清除旧正文比仅挂 stale 标志更保守，避免缓存/普通会话绕过。无需为全部业务表增加软删除。重复上传被 ledger 判为 replay 且实际内容未变时，不重复失效。

来源失效钩子拟落点：entry create/upsert/deleteByClientId/delete/importance/createFollowUp、bookDeletion 的永久删书；源写权限和 Reliable Upload 原逻辑不重写。仅实际变更且存在依赖时执行；新增普通 trace 不影响未选择它的旧回望。未来若增加 follow-up update/delete，必须纳入同一钩子。正常书架移除不调用永久删除逻辑。

读取也重新查依赖，作为漏钩子后的拒绝展示防线，但不能替代同步清除。实现上线条件包含完整写入口枚举；运维直接改 SQL 不在应用事务保障内，未来操作手册必须包含派生清理，不声称任意外部写库都自动安全。

### 6.5 专属追问

只经 `/recaps/:id/follow-ups` 生成，服务端从当前回望+现存证据+已完成历史轮次组装上下文；不能调用会扫描其他书籍/授权随心记的通用 chat 上下文构造器。

同一回望只允许一个模型 operation运行；请求开始时绑定 history revision，完成时复核。原问题与完整回答原子写入 xiaou_messages，status=completed，随后回望revision+1。取消/失败仅留无正文操作状态，不把半截回答加入成功历史。问题可暂存在当前进程内存；进程崩溃不从 operation 恢复私人问题重发。

通用 conversations 的 list/get/append/delete 对 recap_id 非空记录一律排除/404，含 last_message 子查询；通用 create 收到 recap_id 或 book_recap kind 返回400，不改变既有 chat/xiaou_asks 行为。所有创建回望关联只由专属 repository 完成。旧客户端既看不到新专属会话，也不能用普通 append 注入助手答案。

## 7. 缓存、离线与删除保证的准确边界

- 本地 key：origin + userId + recapId + revision + sourceFingerprint + schemaVersion。操作捕获 userId/sessionEpoch，发起、返回、写缓存、进入页面和继续追问前都检查。
- 优先不把云端结果正文落盘，只缓存 ID/无正文状态；确有性能需要的正文缓存也不能成为离线 fallback。专属对话同样处理。
- 打开页面、App回前台、断网恢复、保存/追问/查看依据时必须在线复核；失败即撤掉正文并显示通用占位，不展示上一次书名/摘要。
- 本地已知编辑/删除立即失效，不能因服务器暂未收到删除而重新授权展示。删除请求失败也保留本地撤回围栏，待用户可见的正常重试完成。
- 本机未同步草稿与云端缓存分开命名；草稿只依赖本地仍有效、同账号原记录，删除来源/退出后清理或隔离，绝不显示为已云端保存。
- **分布式限制**：服务器无法撤回已经送到另一设备内存/截图的字节。读事务返回后恰逢另一设备删除，也无法承诺零毫秒消失。建议在线展示采用短期内存许可（候选15秒），显示期间定期复核，到期/失联立即遮蔽；不持有可跨离线重开的许可。此期限需技术审批，不能宣传“所有设备瞬时擦除”。
- 服务器保证删除事务提交后的新读取/保存/追问都拒绝；客户端保证获知撤回/本地编辑后不复活，并且离线重新打开不展示私人正文。更强实时撤回需单独增加推送/订阅机制，不是本轮已具备能力。
- 服务端日志、HTTP/APM body、错误堆栈上下文不得记录证据/问题/完整输出。反馈不进模型材料。备份是独立受控介质：恢复后必须先应用删除围栏/清理记录，才能重新开放读取；保留期限和恢复程序需部署前审查。

## 8. 迁移、版本和回滚计划

本轮没有迁移文件、连接数据库或运行 schema 初始化。以下为未来执行步骤，均需另行授权。

1. 冻结并核对届时 Git diff、现有未提交成果与备份；确认最新 migration 编号。候选 `010_reading_recaps.up.sql`，编号不提前占用。
2. 在合成空库与合成旧 schema 副本测试。读取目录、列、约束、kind分布和 ownership异常；发现差异停，不清洗真实数据。
3. 新增四表及索引、对话 nullable关联和 owner FK；事务设置有限 lock_timeout/statement_timeout，失败整体回滚；不批量回填旧对话/历史。
4. 若生产索引规模需要 CONCURRENTLY，则拆成单独、不可放事务的受控步骤并验证残留索引状态；未经规模检查不直接选择此方案。新增空表索引正常创建即可。
5. 010 对已应用结构通过逐项catalog核对判定 no-op，不能仅用 IF NOT EXISTS跳过。现有仓库未发现统一migration执行记录器；实施需沿用受控SQL流程记录版本/checksum，是否新增执行记录器须另议，不顺手建新框架。
6. 未来只在 fresh schema 同步新增DDL，不重排/修改008、009。存量库禁止执行整个 schema.sql替代迁移。
7. 分离 `RECAP_GENERATION_ENABLED`、`RECAP_READ_ENABLED`、`RECAP_DELETE_MAINTENANCE_ENABLED`，默认关闭用户入口；一旦存在回望数据，删除/失效维护必须常开，不能随入口flag关闭。
8. 部署兼容版本先支持可选表探测和通用对话过滤，再迁移，再核验约束，再开放独立测试。schema缺失/版本不支持返回503或隐藏新入口，不能影响原阅读接口。不得在每次普通请求执行DDL。

回滚：关闭生成/用户入口，保留数据与失效维护代码。**不能回退到完全不认识 recap_id 的旧后端**，否则普通对话列表会泄露专属正文、源删除不会清理派生结果。旧 Flutter 客户端可兼容运行，但服务端回滚最低版本必须包含过滤及失效防线。

若必须回到旧后端，先在获批维护窗口导出并验证派生备份，清除专属对话及全部派生私人正文，确认无泄露路径后再切换；属于额外不可逆操作，需要单独批准。默认 down 不DROP已有用户派生数据。开发合成库的 down 可按conversation关联→operation/feedback/sources→recap顺序撤销新增结构，不触碰原始历史。

本地缓存可采用新独立版本文件，不需要再次升级SQLite历史表；如果实施选择SQLite缓存表，必须另交迁移设计，不能复用18版本号。未知结果 schemaVersion 不尝试解释/展示，保留服务器记录，提示客户端升级。

## 9. 实施拆分与验收计划（尚未执行）

| 步骤 | 拟修改/新增范围 | 通过标准 |
| --- | --- | --- |
| B2.1 契约与合成DB | 新 recap repository/service/routes、010候选DDL、离线契约测试 | 新旧schema兼容、owner约束、失败事务回滚、重复migration核验 |
| B2.2 失效与并发 | entry.repository、bookDeletion.repository最小钩子；通用conversation过滤 | 所有来源写入口覆盖，锁顺序一致，不影响原sync ledger/Obsidian |
| B2.3 私有保存与追问 | 四表、专属conversation关联、服务端证据adapter、无自动重试executor | 服务器重读/保存、scope consent、删除/取消防迟到写入 |
| B2.4 客户端适配 | 新 recap API/cache 模块、AuthSessionScope复用 | A→B→A拒旧响应、离线占位、草稿不假保存、无静默上传 |
| B2.5 完整产品UI | 选择书籍、结果/依据、追问、保存、删除、反馈 | 完整产品目标不缩减；单独确认UI范围后实施 |

必须新增的测试矩阵：

1. A/B相同bookId、猜测recap/source/conversation/request ID：全部无越权正文；复合FK拒绝错owner。
2. 同账号跨设备列出/查看保存结果；无本地书、同名不同ID、独立重导入、mingtai身份、未知旧映射均不假跳转。
3. 未同步trace、pending修改/删除、本地追问无remoteID：本机草稿，不创建账号保存成功，不发生上传请求。
4. 客户端伪造来源、result JSON、完成状态、hash、bookId或userId：服务器拒绝或重建；private/free-note来源始终排除。
5. 两连接并发同request同内容一次执行；异内容409；重启后同request不自动重发；上游收费但提交失败有明确interrupted状态。
6. prepare/generate/save/feedback/follow-up分别与source edit/delete、永久删书、账号删除交错，用barrier控制真实事务顺序；无复活、无部分写入、无锁顺序死锁遗漏。
7. 删除先于prepare、生成完成先于取消、取消先于完成、重复删除、删除后旧operation重放，均符合明确状态表。
8. 未被最终引用但已送入模型的批注被删，同样清除派生正文；新增追问改变集合指纹；不靠updated_at猜测。
9. 来源编辑返回stale无正文；来源删除清除结果、会话消息、反馈、依赖和操作正文指针；删除回望后原始记录逐字段不变。
10. 通用对话list/get/append/delete及last_message均无法访问专属回望；旧客户端不能注入assistant消息。
11. 离线重新打开/回前台/失效后重连只占位；磁盘遗留缓存、内存旧响应、A→B→A均不恢复正文；本地pending删除优先于旧服务器快照。
12. 超限拒绝而非截断、请求次数/输出预算生效、取消/断流/JSON不完整不记完成、Token未知为null；模拟模型足够，不需要真实付费验证。
13. 反馈仅账号可见，不进入模型/公开接口/日志；删除联动清理反馈自由文本。
14. SQL与HTTP层分别验证，跨语言B1契约回归；使用隔离合成PostgreSQL验证锁与FK，不能仅用内存mock宣布并发正确。
15. 基线重新采集后再跑P0a/P0b、账号隔离、Reliable Upload、Obsidian、IAP离线回归；B1上轮193后端/134 Flutter+2既有跳过仅作历史参考，不冒称本轮复跑。
16. 迁移事务中途失败、schema异构、NOT VALID检查发现坏数据、回滚维护模式、备份恢复后删除围栏重放，全部有可重复用例。

## 10. 风险、审批与本轮结果

高优先风险：旧通用对话泄露旁路、仅追踪最终引用导致间接泄露、源写入口遗漏、用户锁顺序、崩溃后重复模型请求、旧服务端回滚丢失删除维护。这些必须在任何真实数据试用前通过合成集成测试。

仍需审批的具体技术操作/参数：

- 是否批准本稿四表及conversation关联方案、短事务失效钩子和通用入口过滤，进入B2.1开发；不等于批准部署或真实库迁移。
- prepared 30分钟、未保存结果24小时、请求MAC30天及最小防复活标识保留到账号删除的保留策略。
- 在线展示许可候选15秒与复核频率；接受其为有界撤回而非瞬时全设备擦除。离线重新打开只占位这一产品决定不变。
- 独立 `RECAP_REQUEST_MAC_KEY`/版本的凭证配置，合成测试可使用固定测试值；真实环境生成/配置必须另行授权。
- 未来独立合成PostgreSQL实例/容器、实际迁移、服务器配置/发布、备份恢复/清理均另行明确审批；不使用现有IAP Sandbox或生产库代替。

本轮只读取源文件并新增本设计报告；没有创建.sql文件、调用API/模型、读取用户数据库、运行迁移或构建/部署/commit/push。DDL尚未在PostgreSQL执行验证，测试矩阵是计划，不是已通过结果。完成设计后暂停，等待确认实施范围。
