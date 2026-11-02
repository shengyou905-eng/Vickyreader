# 知读小U能力审查与升级路线 V1

审查日期：2026-10-16。范围：当前本地工作区，不代表已部署版本或真机安装包。

HEAD 为 `caf7dd6`，工作区已有未提交的 Obsidian、IAP 等改动；本报告包含这些现有文件的实际状态，不把 HEAD 当作全部源码版本。本轮只读取源码、测试和文档，查询官方价格/Flutter 文档，执行纯内存规则验证；仅新增本报告。没有访问生产服务器、数据库或真实用户记录，没有调用付费模型，没有执行迁移、构建、提交、推送或部署。

## 1. 审查发现，按优先级排序

以下“已证实”指源码或纯内存验证支持，不等于已经复现于某个真实用户账号。优先级是修复建议，不代表本轮已获实施授权。

| 优先级 | 已证实的问题 | 影响与证据 |
|---|---|---|
| P1 | 解读追问没有固定保留原文与本轮上下文 | `chatStream` 只提交问题与历史；后端仅取最近 10 条，且追问默认回到 auto 的通用指令。小U详情的首轮原文/解读在已有 5 轮追问后会被全部挤出下一次请求。书名、模式、前后文没有作为稳定上下文随追问提交。见 E1、E2、E5。 |
| P1 | 同章重复文字可能取错位置；旧 EPUB 的章节编号口径不一致 | 文本搜索取首次 `indexOf`，并未使用实际 DOM 选区定位；解读卡保存 `currentChapterIndex`，划线/想法保存 `sourceIndex`。二者在旧 EPUB 过滤目录章节后可能不同。可导致解释借用错误上下文、未来引用跳错章。见 E3、E4、E6。 |
| P1 | 不完整流可能被当成完整回答保存 | 服务端仅转发 `delta.content`，不处理 `finish_reason`、usage，也不要求上游 `[DONE]` 才成功；客户端 EOF 即正常结束。输出长度截断或干净断流且已有文字时，会进入成功保存路径。明确抛出的网络错误有错误处理，不能概括成所有断网都会误保存。见 E1、E2、E5。 |
| P1 | AI 接口缺少任务级输入总预算、并发/次数限额 | `explain` 的 selection、question/history 没有总长度预算，history 的 role 直接传入；其他聊天接口虽规范 role，仍未限制历史逐条/累计长度。8 MB JSON 限制不是模型 token 预算。AI 路由只有登录与同意校验，没有额度中间件。存在滥用费用和提示注入风险，尚未做攻击实测。见 E1、E10。 |
| P1 | 业务记录与 trace 不在同一事务 | `addHighlight`/`addThought` 先写 highlights/notes，再独立写 user_entries；后一步失败可留下原文页可见但缺少 trace 的状态。`insertUserEntry` 自身已将 trace 与可靠队列事务化，这是可沿用的正确基础。没有检查现场数据库，不能说当前存在丢失记录。见 E4、E7。 |
| P2 | “发现”把短时重复行为当成有意义的停留 | 最近 14 天文本前 90 字分桶，桶内两条且最近 72 小时有新记录即可触发；总体至少三条。没有会话间隔、不同日期、独立阅读位置或用户主动想法的必要条件。纯内存验证：同文三条、相隔一秒即产生“已经不像普通摘录”。见 E8。 |
| P2 | 解读模式标签污染主题分析 | trace 保存 `小U解释` 与 `结构拆解` 等模式标签；`actionTags` 仅排除前者等行为标签，未排除模式名称。纯内存验证：三本书的“结构拆解”被输出为跨书共同主题和 long_term_topics。不能据此称为语义主题识别。见 E2、E8。 |
| P2 | 新解读可能直接复用旧答案，缓存不覆盖完整语境 | 缓存 key 是 book/chapter/mode/selection/paragraph，遗漏前后文、历史、语言、账号及模型/Prompt 版本。命中仍生成新 trace，未合并历史，但新行为不一定产生重新分析。新解读还会带入同书最近 6 条消息，而非明确的独立阅读会话。见 E2。 |
| P2 | 回顾缺少可验证引用和长期检索 | 普通聊天取最近 180 条 trace，实际仅拼前 120 条，各字段截为 180 字；不带 trace ID、时间、锚点，也不拼入追问内容。没有按问题检索旧记录，没有全书或跨章证据完整性保证。见 E1、E9。 |
| P2 | 全章范围实际为窗口，保存证据更短 | “本章”输入是当前位置附近最多 24,000 字符，不是任意长章节全文；首次问答保存的 original_text 仅保留前 6,000，page_text 4,000。模型看过的后半段可能没有保存在该 trace 中。界面原文预览长度不应因此缩短，应另存证据范围。见 E3、E4。 |
| P2 | 追问与首页对话尚未进入同等可靠的保存链 | follow-up 使用本地 remote_synced + 直接 POST，读取追问时重试；服务器新建 follow-up 没有 client turn id 幂等约束，也未追加 sync_changes。响应丢失后重试可能重复，后续派生知识也不会仅凭 trace ledger 感知追问变化。首页聊天保存失败显示警告，但未见持久化重试队列。见 E5、E7、E9。 |
| P2 | 缺少知识级来源类型与稳定身份 | 小U书名入口实际打开痕迹列表，并非原文定位；有标题时按标题归组，不能作为知识关系的唯一书籍身份。“小U问我→保存为想法”把 AI 开场问题放入 original_text，虽有 `metadata.origin=xiaou_asks`，普通回顾组装时却统一标为“原文”。见 E1、E11。 |

### 尚未验证的风险

- 本轮没有跑真实模型质量评测，不能宣称现有“概念/论证”一定答错，或切换更大模型一定改善。
- `ai_messages` 仅按 bookId 读取、无独立 user_id；AiProvider 缓存也不含账号。需要换号、同设备保留同一 bookId 的专项测试才能判定是否产生实际跨账号展示，本报告不声称已经泄漏。
- 书籍更新/重导入缺少统一版本锚点与迁移策略，但没有读取用户文件验证漂移比例。
- 源码默认模型不等于当前线上环境变量；本轮按要求没有检查生产实际模型与账单。

## 2. 功能现状表

“已实现”表示存在端到端代码路径，不代表已经达到高级知识分析质量标准。

| 能力 | 状态 | 实际边界 |
|---|---|---|
| 五种划词解读模式 | 已实现 | 独立 Prompt、模式选择、流式输出、保存 trace；模型调用机制共用。 |
| 选中文字/当前页/本章提问 | 已实现，有范围限制 | 页取 WebView 可见文本，失败按滚动比例取窗口；长章节不是完整全文。 |
| 连续追问 | 部分实现 | 解读卡、trace 详情、阅读提问均有；稳定来源上下文与长会话管理不足。 |
| 同文多次独立历史 | 已实现 | 新 UUID，不按原文去重；答案缓存行为需另行确认。 |
| 原文预览与展开/收起 | 已实现 | 小U卡有独立展开；不同阅读面板的预览形式不完全相同。本次不调整。 |
| 离线划线/想法、trace 与同步 | 已实现，存在事务边界缺口 | 首页以用户隔离的本地/远端投影显示，并合并 pending/tombstone；AI 生成本身依赖网络。 |
| 小U聊天与历史 | 已实现，有可靠性边界 | PostgreSQL conversations/messages；当前模型只收到最近消息，历史存得多不等于模型记得多。 |
| 回顾划线与批注 | 部分实现 | 快捷 Prompt 进入通用聊天，最近 trace 摘要作为上下文，不是专用知识回望管线。 |
| 小U发现 | 部分实现 | 时间窗、重复文本、标签频次的规则模板；具备返回空字符串的能力，但触发可信度不足。 |
| 跨书/跨章主题 | 部分实现 | 跨书同标签规则；同章/跨章语义对齐没有专门实现。 |
| 深度回望、高价值问题 | 未实现为独立能力 | `deep_reflection` 与 weekly_summary 都填同一个规则发现文本；high_value_questions 当前总为空。 |
| 原文证据引用与返回位置 | 部分底座，未闭环 | 有 book/chapter/部分 offset/段落索引；没有统一的回答 claim→evidence→reader 路由。 |
| Knowledge Object / AI 思维导图 | 未实现 | 未发现相应模型、生成接口、Flutter 导图页面；embedding 空字段不是向量检索。 |
| 通用 Pro entitlement | 后端已实现 | 008/009、权益查询与 Apple 验证代码存在；AI 权限/额度/模型路由未接入，Flutter 无 IAP 依赖。 |
| Token/成本/每月额度 | 未实现 | 现有流没有采集 usage；无 AI 账本、限额或复杂度路由。 |

## 3. 代码地图与数据流

### 3.1 主要证据位置

以下链接以当前工作区为准；后续修改可能改变行号。

| 编号 | 文件与关键入口 | 本次定位用途 |
|---|---|---|
| E1 | [ai.controller.js](C:/Users/29319/Desktop/reader/backend/src/controllers/ai.controller.js:6)；`explain` 160、`chat` 244、`streamDeepSeek` 294、`readerQuestion` 403、`xiaouAsks` 475、`buildEntryContext` 569 | 全部模型 Prompt、请求、上下文与 SSE。 |
| E2 | [ai_provider.dart](C:/Users/29319/Desktop/reader/lib/providers/ai_provider.dart:34)；`explain` 41、`sendFollowUp` 176、`_persistExplanation` 270；[ai_service.dart](C:/Users/29319/Desktop/reader/lib/services/ai_service.dart:45) | 缓存、同书历史、独立 trace、追问、流结束处理。 |
| E3 | [reader_screen.dart](C:/Users/29319/Desktop/reader/lib/screens/reader/reader_screen.dart:1147)；`_showReaderQuestion`、`_textWindowAtRatio`；[ai_explanation_card.dart](C:/Users/29319/Desktop/reader/lib/screens/reader/widgets/ai_explanation_card.dart:72) | 选区、页/章范围、编号和 UI 发起路径。 |
| E4 | [reader_provider.dart](C:/Users/29319/Desktop/reader/lib/providers/reader_provider.dart:373)；`addHighlight`、`addThought`、`addAiQuestion` | 业务记录到 trace、metadata、来源信息。 |
| E5 | [reader_question_sheet.dart](C:/Users/29319/Desktop/reader/lib/screens/reader/widgets/reader_question_sheet.dart:113)；[xiaou_card.dart](C:/Users/29319/Desktop/reader/lib/screens/xiaou/widgets/xiaou_card.dart:560) | 提问会话、保存回调、历史追问原文、长预览。 |
| E6 | [epub_service.dart](C:/Users/29319/Desktop/reader/lib/services/epub_service.dart:436)；[txt_service.dart](C:/Users/29319/Desktop/reader/lib/services/txt_service.dart:19)；[reader_document_html.dart](C:/Users/29319/Desktop/reader/lib/screens/reader/widgets/reader_document_html.dart:437) | EPUB sourceIndex、文本上下文、TXT 分章、DOM 段落锚点。 |
| E7 | [book_service.dart](C:/Users/29319/Desktop/reader/lib/services/book_service.dart:1762)；`insertUserEntry`、`getUserEntryFollowUps` 1885、`insertUserEntryFollowUp` 1945；[database_service.dart](C:/Users/29319/Desktop/reader/lib/services/database_service.dart:72) | SQLite、事务、可靠上传与追问另一路保存。 |
| E8 | [insight.repository.js](C:/Users/29319/Desktop/reader/backend/src/repositories/insight.repository.js:129)；`buildActiveDiscovery` 166、`findRepeatedText` 209、`findCrossBookTheme` 230、`findInterestShift` 257；[insightRefresh.service.js](C:/Users/29319/Desktop/reader/backend/src/services/insightRefresh.service.js:5) | 规则观察、时间窗、缓存、空输出。 |
| E9 | [entry.repository.js](C:/Users/29319/Desktop/reader/backend/src/repositories/entry.repository.js:200)；`listFollowUps` 314、`createFollowUp` 326；[xiaouConversation.repository.js](C:/Users/29319/Desktop/reader/backend/src/repositories/xiaouConversation.repository.js:49) | 用户隔离、最近记录查询、对话持久化。 |
| E10 | [ai.routes.js](C:/Users/29319/Desktop/reader/backend/src/routes/ai.routes.js:1)；[requireAiConsent.js](C:/Users/29319/Desktop/reader/backend/src/middleware/requireAiConsent.js:1)；[app.js](C:/Users/29319/Desktop/reader/backend/src/app.js:36) | 认证、AI 同意、请求体边界。 |
| E11 | [xiaou_home_screen.dart](C:/Users/29319/Desktop/reader/lib/screens/xiaou/xiaou_home_screen.dart:474)；对话保存 1063、“小U问我”保存 1376；[xiaou_trace_snapshot.dart](C:/Users/29319/Desktop/reader/lib/services/xiaou_trace_snapshot.dart:8) | 按书入口、本地合并、对话来源。 |
| E12 | [schema.sql](C:/Users/29319/Desktop/reader/backend/src/db/schema.sql:51)；[entitlement.service.js](C:/Users/29319/Desktop/reader/backend/src/services/entitlement.service.js:3)；[subscription.repository.js](C:/Users/29319/Desktop/reader/backend/src/repositories/subscription.repository.js:156) | 云端结构、时间/环境约束、通用权益。 |
| E13 | [freeNote.repository.js](C:/Users/29319/Desktop/reader/backend/src/repositories/freeNote.repository.js:115)；[bookIntroduction.service.js](C:/Users/29319/Desktop/reader/backend/src/services/bookIntroduction.service.js:163) | 私人笔记显式授权、另一条 AI 调用成本。 |
| E14 | [pubspec.yaml](C:/Users/29319/Desktop/reader/pubspec.yaml:6)；[app.dart](C:/Users/29319/Desktop/reader/lib/app.dart:38) | Dart ^3.10.8、Provider/ChangeNotifier、现有 WebView/share_plus 等依赖。 |

### 3.2 当前结构

- Flutter：Provider/ChangeNotifier，SQLite schema 17；EPUB/TXT 转章节 HTML，在 WebView 阅读。不是基于 EPUB CFI 的完整定位引擎。
- Node.js/Express + PostgreSQL：REST、SSE；第三方模型调用在服务器，密钥不进 Flutter。
- `POST /api/ai/explain`：新解读与解读追问共用；`POST /api/ai/reader-question`：阅读范围提问；`POST /api/ai/chat`：个人阅读痕迹聊天；`POST /api/ai/xiaou-asks`：开场问题。
- `/api/entries` 及 follow-up 路径保存阅读 trace；`/api/xiaou/conversations` 和 `/:id/messages` 保存首页会话；`GET /api/insights/home`、`POST /api/insights/refresh` 提供规则缓存。`/questions/:questionId/answer` 读取缓存问题，当前新生成缓存没有问题项。
- 小U聊天并没有调用 MCP 工具来动态找资料，当前是控制器查询后拼接文本的模式。MCP 自身是只读关键词/标签检索，代码明确不宣称语义/向量检索。

### 3.3 可以复用的表

| 数据 | 本地 | PostgreSQL | 关联与边界 |
|---|---|---|---|
| 书籍/进度 | books、reading_progress、bookmarks | user_library_books、reading_progresses | book ID、chapterIndex、scrollOffset；不存在统一书籍内容版本锚点。 |
| 划线/想法 | highlights、notes | 当前主要经 user_entries 同步阅读 trace | 划线/想法 metadata.source_record_id 指向本地业务记录。 |
| 阅读行为 | user_entries | user_entries | 独立 UUID/client_entry_id；source、book、chapter、original_text、user_input、ai_explanation、auto_tags、metadata_json。 |
| 追问 | user_entry_follow_ups | user_entry_follow_ups | entry_id；本地与远端 ID 需要稳定映射，当前没有完整的可靠 turn 幂等链。 |
| 解读消息 | ai_messages | 不作为独立 ai_messages 表同步 | 按 bookId 最近 6 条读入，内存最多 20 条；没有明确 interpretation/session ID。 |
| 小U会话 | 页面内存 + HTTP service | xiaou_conversations、xiaou_messages | user_id/conversation_id，completed/cancelled/error；未见本地离线历史队列。 |
| 首页回望 | 首页缓存/投影 | user_insights | 最近统计、规则文本，不是概念图或结构化证据模型。 |
| 可靠同步 | pending_upload_operations、upload_entity_revisions 等 | user_entry_upload_states、sync_changes、sync_user_cursors | 复用 revision/generation、tombstone 和 user_sequence；不得改造成另一套阅读 ledger。 |
| 私人随心记 | free_notes | free_notes、xiaou_free_note_grants | 默认私有，只有显式 grant 的数据进入当前 AI 上下文。 |
| 会员 | 尚无 Flutter IAP 模块 | subscription_accounts、subscription_ownership、subscriptions、entitlement_grants、subscription_events | 008/009；通用 pro 权益与 Apple 验证分层、Sandbox/Production 隔离。 |

## 4. A：解读能力与增强方案

### 4.1 实际 Prompt 与调用参数

共同 system Prompt 位于 E1 的 12 行：解释对象是选中文字，周围文本用于消歧；保留否定/转折/限制/语气；关键判断须有原文依据；材料不足要说明；补充背景要标注；不机械套主谓宾；只输出适用栏目；文本指令只作材料；中文纯文本约 300–700 字；追问不变成泛聊。另有请求级中英文响应指令。

| 模式 | 当前实际差异（Prompt 栏目） | 参数 |
|---|---|---|
| 自动，E1:29 | 难点在哪里、核心解释、文本依据、通俗改写；按实际难点选解释策略 | temperature 0.3 / max_tokens 1400 |
| 通俗，E1:38 | 核心意思、换成日常语言、需要留意；不是简单缩写 | 0.3 / 1400 |
| 拆解，E1:46 | 核心命题、句法骨架、修饰与指代、逻辑关系、论证位置、通俗改写 | 0.3 / 1800 |
| 概念，E1:56 | 关键概念、本文中的含义、容易混淆、概念之间的关系、放回原句；区分日常义与上下文义 | 0.3 / 1400 |
| 论证，E1:65 | 这段的作用、作者主张、前提与依据、推理链、限定/异议、结论边界；省略前提必须标为推测 | 0.3 / 1800 |

调用统一为 DeepSeek 的 `/v1/chat/completions`、SSE、`thinking: {type: 'disabled'}`。模型读取 `DEEPSEEK_MODEL`，未设置时为 `deepseek-v4-flash`。普通小U聊天默认 0.7/1200；阅读提问 0.3/1800；小U开场提问 0.75/420。上游整体 120 秒超时，15 秒心跳；Flutter 等待连接响应 60 秒。

2026-10-16 查询到的官方说明：旧名 `deepseek-v4-flash` 已转接到 DeepSeek-V4.1-Flash，推荐 API 名为 `deepseek-flash`。因此即使配置字符串未变，也不能把它当成固定模型版本。这里只记录模型漂移风险，不修改配置。[官方模型与价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)

### 4.2 上下文能力边界

- 新解读：Flutter 提取前后各约 600 字符、段落最多 1800，再传选区与书名/作者/章名；服务端也有外围字段上限，但未给选择内容总预算。没有读取整书、术语词典或作者其他著作。
- 拆解适合局部复杂句、指代、限定关系；跨段省略和长距离照应受窗口限制。
- 概念适合当前语境辨义；没有检索全书首次定义，不能保证同一术语全书一致，更不能凭模型常识认定作者定义。
- 论证已要求区分明示与省略前提，但未保存 claim/premise/evidence 结构，没有机器验证引文和关系。较长跨章论证不能只靠当前窗口。
- 当前区分“原文/AI解释/推测”主要靠 Prompt 和 UI 文本，不是强类型证据结构。原文引用的真实性没有程序校验。
- 问小U sheet 每轮重发固定阅读上下文，比 explain 追问稳定；但关闭重开是新内存会话，历史详情续问又走通用 explain。两个入口需要共用上下文契约，不需要合并行为记录。

### 4.3 建议：模式与能力等级正交

保留 auto/plain/structure/concept/argument 五种免费模式。新增内部 `analysis_level=standard|enhanced|deep`，不是再增加十种模式；具体 Pro 展示与额度等 P3 决策。

1. **确定材料**：以本次真实选区、锚点和书籍版本构建不可变 context snapshot。每轮固定携带最初问题与核心证据，历史按完整轮次裁剪；压缩旧讨论时保留证据 ID，不用总结取代原文。
2. **增强分析**：先定位难点，再选择所需章节片段；概念查本书定义/对照用法，论证提取主张、依据、论证步骤及反证，拆解恢复指代和作用范围。不能把“用了更贵模型”直接当作质量结论。
3. **深度思考**：为复杂或用户主动选择的任务提供更高能力/思考预算，必要时增加独立证据核对阶段。检查结论是否超出前提、是否遗漏限定、是否有另一种解释；输出结论、必要推理摘要和不确定性，不要求公开模型内部思维链。
4. **结构化结果**：新增版本化 answer envelope，保留当前自然文本展示。每个关键 claim 附 `basis=source|background|inference`、evidence_ids、解释与局限。服务端核对 evidence 是否属于当前用户和提供材料、quote 是否确实匹配；这只能验证出处存在，逻辑支持关系仍须评测/复核。
5. **完整性**：SSE 增加 request ID、显式完成/取消/截断/错误事件及 finish reason；只有完成事件结算成功，部分文本保留并明确状态，不伪造完成。新版本协议兼容旧客户端。
6. **行为与重试区分**：每次主动解读新建 event/trace UUID；同一请求的网络重试复用 request ID。只对传输重试幂等，不按原文去重。全文/结构分析缓存可以共享计算，但必须保留独立行为及新语境；当前答案复用是否保留由产品确认。

## 5. B：稳定阅读关联，尽量不改现有展示

### 5.1 现有锚点强度

- EPUB 按 spine 解析并落为 `ch_N.html`，旧内容通过 sourceIndex 兼容；不是永久章节内容 ID。TXT 按标题正则分章，没有标题则按 5000 字符分段。
- highlight 有 chapterIndex、start/endOffset、前后文；thought 可有 paragraph_index/paragraph_text，但 DOM 段落索引由页面顺序生成，段落摘要最多 600 字符。
- explanation 当前主要保留章与选中文本；ai_question 保存章、滚动比例/位置与截断后的上下文，缺少统一 range。
- 普通导入未提供 bookId 时创建新 UUID；没有自动把相同文件的新导入与旧阅读行为重新绑定的机制。图片文件名的 hash、发布用 sourceBookId 不能替代书籍版本/文本锚点。
- 修改源书会改变 DOM/偏移/TXT 分章。不能仅凭书名或原文前缀自动搬迁记录，也不能把搜索到的第一次出现当作必然正确。

### 5.2 最小可实施关联结构

保持 `user_entries` 为独立阅读行为；优先在已有 metadata_json 增加可选 `reading_context_v1`，旧客户端忽略新字段即可，不改列表、不强制迁移历史：

```text
book_id + content_version_hash
  -> source anchor (chapter source index/href, paragraph/range, exact quote,
                    prefix/suffix, normalization_version, match_status)
  -> user_entries.id / client_entry_id (每次行为独立)
  -> first answer + follow_up turn IDs + user thoughts
  -> derived knowledge references (不替代原行为)
```

锚点至少含 chapter 稳定线索、DOM Range/统一纯文本 offset、exact/prefix/suffix、规范化版本、source_kind。`source_kind` 应区分 book_text、user_note、ai_question、public_annotation，避免 AI 开场问题被当成书籍引文。EPUB CFI 可评估为未来补充，不宜为此替换整个 WebView 阅读器。

定位顺序：同版本结构定位并校验 quote；失败后 quote+prefix/suffix 唯一匹配；多处命中显示候选；无法匹配标为 unresolved，允许跳章但不得假装精准回原文。重导入保留旧证据快照，只有用户确认或严格唯一匹配才建立版本间关联。

后续新增“统一返回原文”服务，复用 ReaderProvider 打开书/章节和 WebView 滚动能力；书已移出书架但文件还在可打开，文件缺失显示证据与重新定位说明，不删除痕迹。阅读原文预览和展开/收起一律保留。

业务→trace 原子性建议后续局部修复：BookService 提供同一个 SQLite transaction 写 business、trace、queue；网络 drain 放到 commit 后。只改本次创建链，不重构 Reliable Upload 的 revision/generation 协议；历史补关联只能显式、幂等、尊重 tombstone，本轮不回填。

## 6. C：解读回望与发现

### 6.1 回望真正用了什么

- “回顾我的划线与批注”是快捷提示：`请回看我最近的划线与批注，告诉我其中有没有值得继续追问的联系。` 进入普通 `/ai/chat`，并没有按 source 严格只取划线/批注，也没有专用综合流程。
- 生成聊天上下文时加载最近 trace、用户明确授权的随心记、最近公开阅读痕迹；来源文本分栏，但不是相关性检索。其他人公开痕迹不可作为用户自身思想证据。
- `user_insights` 基于最近最多 500 条 trace、最多 100 条授权笔记，15 分钟缓存；写入后可延迟 250 ms 调度刷新。规则既不是 LLM 分析，也不是图谱推理。
- 7/30 天是数量/标签/书名统计，summary 为空；long_term_topics 是标签频次排序，未证明长期性；weekly_summary 和 deep_reflection 复用同一个发现文本；high_value_questions 固定空数组。
- 能做到“同标签出现在多书”，不能据此断言识别了跨章节概念、矛盾或论证。已存在 entry→follow-up 和 conversation→messages 的存储关联，但当前回顾组装不读取完整追问/旧对话来建立问题演进关系。
- 规则在无候选时返回空，方向正确；但“刚授权笔记 + 最近有阅读”也能输出一张承认没有关系的观察卡，不符合“没有值得说的话，就不要说”的目标。

### 6.2 解读回望 Pro 的建议输出

复用现有首页入口、痕迹详情、按书/标签浏览和原文预览，不整体重做 UI。结果应包含主题、概念、问题、观点/论证关系五类可展开内容；每项必须能打开对应 trace 和可用的原文位置。

建议生成管线：用户指定范围 → 用户隔离检索 → 来源/时间/会话整理 → 概念和问题抽取 → 候选关系 → 证据校验 → 克制总结。没有足够证据时返回空结果与范围说明，不自动制造“成长”。

- 阅读主题：用概念语义和不同原文位置佐证，不把模式名/行为标签当主题。
- 核心概念：保留各章节定义和用法差异，标出尚不能统一的含义。
- 用户疑问：区分用户原始问题、AI建议问题、已有讨论；“已回应”不等于“用户已经理解”，不自动标为解决。
- 观点/论证：关系类型如 supports、contrasts、defines、depends_on，标明 grounded 或 inferred。不同书之间只建立可解释的关系，不强行证明作者互相影响。
- 引用：回望项→evidence link→trace/follow-up/message→原文锚点；不可只给无法回跳的书名。

### 6.3 观察触发与沉默机制

分析层可将同一锚点在同一短会话的多次行为计为一个“证据组”，但绝不合并/删除历史 trace。区分主动想法、主动提问、被动 AI 生成，AI 输出不能作为用户长期关注的自证循环。

候选至少评估不同日期/会话、独立原文位置、跨章节证据、用户主动输入以及最近是否已有相同发现。具体天数和频率是产品参数，不在本轮替用户定案。候选需说明“新增了什么有证据的关系”；单次测试、重复同文或只有授权行为应沉默。同一事实加冷却与用户关闭能力，证据删除/撤权后失效。

随心记继续默认排除；现有显式授权通道不等于允许所有新高级功能自动读取。新回望/导图建议仅使用阅读数据，是否保留明确授权的例外由产品确认。明台分享仍走主动选择，派生知识不得自动发布。禁止人格、心理状态或思想成长程度推断。

## 7. D：共享知识数据与首版导图

### 7.1 建议共享层

不立即建立庞大 Knowledge Object 平台。P1 可新增一个用户私有 `knowledge_documents` 派生快照表与一个 `knowledge_evidence_links` 关联表（名称为建议，尚未创建）。

- document：owner、scope/book IDs、schema_version、source watermark/hash、Prompt/model/pipeline 版本、状态、生成时间，JSONB 内含稳定 node IDs、主题/概念/问题/claim/edge。
- evidence link：owner、document/node/edge、trace/follow-up/message ID、source revision/hash、anchor snapshot、quote、basis。校验同用户，明确删除/撤权与失效规则。
- edge：类型、起止节点、grounded/inferred、支持证据及局限；AI置信度仅作参考，不等于经过验证的事实。
- recap 和 map 从同一个快照投影；更换布局、展开节点、导出图片不再调用模型。只针对变化的证据重算受影响部分。

复用现有 sync_changes.user_sequence 做 trace 变化水位和失效输入；不复制 ledger，不改 Obsidian v1 DTO/cursor。follow-up 与聊天缺少对应变化事件，需在其写入路径增加专用失效通知或可验证的内容版本，不能只依赖当前 trace 水位。知识对象先用独立读取接口/缓存，不把新实体悄悄塞进旧同步合同。

原始证据删除后，派生快照不能继续作为有效事实提供给模型；账号删除应清除派生内容与向量（若以后引入）。保留用户原文/痕迹，不用 AI 汇总覆盖历史。当前不需要引入 pgvector；后续若关键词与分层索引召回不足，再以评测决定。

### 7.2 Flutter 实现比较

| 方案 | 优点 | 限制 | 建议 |
|---|---|---|---|
| 原生 Tree/List + ExpansionTile | 最轻、文字/无障碍友好 | 更像大纲，不是完整关系图 | 可作无障碍/低性能回退。 |
| GraphView + 原生节点组件 | 有树/分层布局、展开收起；沿用 Provider、原生点击/详情 | 需做大节点限额、字体/边标签/性能验证；不应假定大型图流畅 | 首版优先原型验证，选树布局，不开力导向动画。 |
| WebView + JS 图库 | 现有 WebView 可复用，布局生态丰富 | 多一套 JS bridge、内容安全、导出和无障碍维护成本 | 暂不优先。 |
| 全自绘布局/编辑器 | 自由度高 | 布局、命中、文本与无障碍维护成本高 | 首版不采用。 |

官方包页面显示 GraphView 1.5.1 支持树布局及展开/收起，定位更适合小图；本轮没有安装，依赖兼容与性能仍需原型确认。[GraphView 文档](https://pub.dev/packages/graphview/versions/1.5.1)

交互采用有边界的树图区域，首屏章节层、按需展开概念，节点详情沿用底部阅读层；跨概念关系可先在详情显示，避免首版全图交叉线失控。关系同时使用文字标记和线型，不仅靠颜色表达依据/推断。建议先以约 100 个可见节点、数百个总节点做容量验证，数字不是已测容量。

缩放/平移可用 Flutter InteractiveViewer；导出在独立有尺寸上限的 RepaintBoundary 渲染，通过 toImage 生成 PNG，复用 share_plus。需要限制像素与内存，并按章节/分支导出大图，不能只截当前 viewport 却声称完整导图。[InteractiveViewer](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html)、[toImage](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html)

### 7.3 首版数据范围必须明确

私人 EPUB/TXT 正文主要在设备，本轮未发现“所有私人书全文已在后端可检索”的保证。首版若仅用 trace，应标“基于阅读痕迹的导图”，不能冒充全书主要概念。若要求章节全文导图，需要用户同意后按章节分块上传分析材料、绑定版本、明确保留期限；不要把私人书上传明台，也不要把公共书章节当成同一私人版本。

## 8. E：Pro 与成本

### 8.1 当前计量与会员接入状态

- AI 控制器没有消费/持久化输入、输出、缓存命中或 reasoning token usage；没有模型费用账本、月额度、复杂度路由。bookIntroduction.service 的另一条非流式调用同样未记录 usage，未来统计不能漏掉它。
- 有局部字符上限、max_tokens 与超时，但没有统一 token 预算。字符数不能直接按固定比例当 token。
- IAP entitlement service 按 user + environment 读取有效 grant，数据库时间判断 valid_from/valid_until/revoked，错误不被转换成 FREE。这一层可以复用，不应按 Apple productId 散落判断 AI 权限。
- 当前公开 `/api/me/entitlements` 通过 Apple service 工厂获取配置，`APPLE_IAP_ENABLED` 关闭会阻止该入口。未来 AI policy 应依赖通用 entitlement 读取接口，而不是每次为了判权限启动 Apple 验证或把禁用购买理解成 DB 错误。此处是最小解耦建议，不涉及本轮改开关。
- P0 应先加“仅计量、不限制”的 usage 设计；P3 才在确认权益后实施服务端 quota。免费五模式、本地阅读和已有痕迹读取不得因购买入口不可用而被锁。

建议未来 usage 记录：request_id、user、服务环境、task/mode/level、请求与实际返回 model、Prompt 版本、input/cache-hit/cache-miss/output/reasoning usage、完成状态、延迟、价格版本和估算费用；不存密钥，不默认复制原文与完整聊天。读 usage 失败不能伪造零成本。

额度未来采用事务化 reserve→settle/release，同一 request ID 不重复扣用户次数，多次独立解读各有行为 ID。用户额度与供应商账单分开：失败请求也可能产生供应商费用。复杂度路由和 fallback 需要可解释规则，承诺深度能力时不能静默降档；超过预算应提示等待/调整范围，不伪装成同质量答案。

### 8.2 价格输入与估算假设

2026-10-16 官方人民币标价，单位为每百万 token：Flash 未命中输入 1/2 元、命中输入 0.02/0.04 元、输出 4/8 元；V4-Pro 未命中输入 4.5/9 元、输出 13.5/27 元，前者为空闲、后者为高峰。不是现有服务器账单或用户平均用量。[DeepSeek 官方价格](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)

成本公式：`调用数 × (未命中输入×单价 + 命中输入×单价 + 全部计费输出×单价) / 1,000,000`。下表中的 token 为测算假设，不是字符数；包含所有 Prompt/历史输入，深度任务的输出预算须包含实际计费思考量。用空闲到高峰给范围，不假设所有用户都在低价时间使用。

| 每用户每月场景 | 假设 | 模型成本：空闲 / 高峰 |
|---|---|---|
| 1500 次较短普通调用 | Flash；每次 3000 输入 + 800 输出，无缓存命中 | ¥9.30 / ¥18.60 |
| 1500 次较长增强调用 | Flash；8000 输入 + 1200 输出，无缓存命中 | ¥19.20 / ¥38.40 |
| 1500 次混合路由 | 上述 8000/1200；80% Flash + 20% Pro，无缓存 | ¥31.02 / ¥62.04 |
| 高缓存敏感性示例 | Flash 8000/1200，输入 token 的 80% 真正命中供应商缓存 | ¥9.79 / ¥19.58 |
| 另加 30 次深度任务 | Pro；12000 输入 + 4000 全部计费输出，无缓存 | 另加 ¥3.24 / ¥6.48 |
| 1500 次全部深度任务 | 同上 Pro 12000/4000 | ¥162 / ¥324 |
| Free 300 次成本 | 与第一行相同的 Flash 3000/800 | ¥1.86 / ¥3.72 |

即使输入完全免费，1500×1200 输出在 Flash 仍是 ¥7.20/¥14.40。以上未含重试、二次证据检查、回望/导图、免费用户补贴、存储/服务器、渠道费用和税费。因此“10–15 元 + 1500 次增强解读”尚不能认定可持续；也不能因此自行降低额度或修改价格。

低成本方向：精确检索而非每次塞 120 条痕迹；稳定前缀与章节分析复用；回望/导图共用结构；只在有依据的复杂任务升级模型；避免重复供应商请求；记录真实用量后计算 P50/P95 与高用量用户成本。80% 缓存命中只是敏感性假设，不可作为定价保证。所有路由先通过质量门槛，不能把节省长度当质量提升。

## 9. 分阶段实施路线

建议保留用户提出的主顺序，但把“证据结构与只计量成本”提前到 P0，把“共享知识结构”放在 P1，避免 P2 重算和 P3 才发现成本不可承受。

| 阶段 | 最小开发范围 | 依赖与退出条件 | 主要预期文件范围（未修改） |
|---|---|---|---|
| P0a 可靠性 | 统一 history role/大小预算、SSE 完成状态、请求幂等；修复上下文与 sourceIndex；局部业务/trace 事务 | 先建立回归用例；旧客户端兼容；无数据覆盖 | ai controller/service/provider、reader provider/screen、book service、对应 tests。 |
| P0b 解读质量 | 五模式 Prompt 版本化、阅读会话/context envelope、证据 ID 与原文引用核验、质量基准；usage 只计量 | P0a；连续追问原文不丢；同文多次独立；基础模式不收费 | 新增小型 context/answer/usage 服务与契约，沿用原 UI；计量存储另提 migration 审核。 |
| P1 解读回望 | 修复模式标签与短时重复发现；时间/会话证据门槛；主题/概念/疑问/论证整理；共享知识快照与回原文 | 依赖 P0 锚点/证据；先解决 follow-up 变化感知；无价值沉默 | insight repository/service、entry/follow-up 失效接入、新 knowledge 服务/表、原首页详情的局部入口。 |
| P2 导图 | 同一知识快照投影到树图、展开/收起、证据详情/回跳、PNG 导出 | 依赖 P1；先确认全章材料授权；图布局不触发重新生成 | Flutter knowledge repository/model/provider、独立轻量图页面、GraphView 依赖原型。 |
| P3 Pro | 通用 entitlement policy、任务模型路由、事务额度、成本监控、IAP 客户端与 Paywall | 价格/额度/深度质量承诺确认，Apple 条件完成；Sandbox 隔离 | 已有 entitlement 基础局部解耦、新 AI policy/quota、Flutter subscription/paywall；保持独立授权和同步合同。 |

P0 的首次开发建议再缩成一个可验收批次：先做上下文/证据/流完整性与其测试，不同时上导图、会员或全新首页。发现规则修正可作为独立小补丁，但不能把历史去重当修复。

## 10. 风险与验收

### 10.1 本轮验证结果和覆盖缺口

已执行 5 项纯内存检查：短时同文触发观察、模式标签成为跨书主题、模式标签进入长期主题、问题列表为空、空输入返回沉默。直接载入现有 insight 构建逻辑，数据库调用被禁止，0 次 DB 访问，5 项断言通过；前三项通过表示成功复现缺陷，不是产品通过验收。只使用内存中的合成字符串，没有创建任何测试数据库记录。

已阅读现有测试：ai_service_test 主要覆盖友好错误；reader_question_sheet_test 覆盖范围选项；reader_document_html_test 包含段落锚点；xiaou_card_test 覆盖本地待同步、完整解读、问小U分类、原文展开；xiaou_trace_snapshot_test 覆盖本地/远端合并、删除与用户隔离。后端已有 Reliable Upload、Obsidian、IAP 事务/隔离测试。

未发现针对本轮关键 AI Prompt/长追问/语义质量/发现误触发的完整自动化评测。本轮没有运行全套 Flutter/PG 集成测试，不以历史测试结果冒充本次结果。[Phase 0 历史基线](C:/Users/29319/Desktop/reader/docs/zhidu-pro-phase0.md:173) 记录根目录 Flutter 64 passed、6 个文件 SQLite 加载失败；既有 async BuildContext warning 按用户约定仍列基线，本次未重新验证。它们不是本轮新增 regression，也不在本轮顺手修复。

### 10.2 后续开发验收门槛（建议，需确认）

| 类别 | 必须验证的场景与预期 |
|---|---|
| 独立行为 | 同一原文连续解读 3 次、跨日再读：保留每次 UUID/时间/模式；仅同 request 重投幂等；不覆盖原历史。 |
| 原文 UI | 长原文、展开/收起、不同字体及大字模式：全文仍可见，默认设计不被压缩；返回页面滚动位置不乱。 |
| 上下文 | 同章两处相同句子、跨段选区、特殊空白、旧 EPUB sourceIndex、TXT 编码与重分章；确认引用真实选中位置，无法定位明确失败。 |
| 连续追问 | 至少 12 轮，第一段原文仍作为固定证据；新解读不混入另一段旧会话；重开详情仍能明确来源与模式。 |
| 流可靠性 | 正常完成、length 截断、EOF 无 DONE、取消、断流、重复请求、保存失败；部分文本不能标为已完成或重复扣用户额度。 |
| 存储/同步 | 在 business/trace/queue 每一步注入故障；单事务全部回滚；离线/恢复/重启、local→remote ID、follow-up 响应丢失不重复；旧 Obsidian snapshot/cursor/tombstone 不回归。 |
| 发现 | 三次短时同文、同一模式跨多书、仅授权私人笔记、无新证据：不输出空泛观察；跨会话真实问题有可打开证据；不得推断人格/心理成长。 |
| 回望 | 章前后不同定义、未解决疑问、用户明确更正、相反观点、被删证据；区分回应与解决，保留矛盾，证据删/撤权后派生内容失效。 |
| 质量 | 至少 60 段经许可文本，覆盖五模式、否定/嵌套限定/反讽、翻译长句、概念歧义、跨段论证、证据不足和注入文本；盲评与当前版本对照，不能只用另一个 LLM 当裁判。 |
| 质量量化 | 建议关键引文可定位率 100%；主张支持正确率 ≥95%；复杂子集盲评偏好增强版 ≥65%，基础准确性不得回退；材料不足时能拒绝虚构。阈值是验收提案，不是已经取得的成绩。 |
| 导图 | 节点/关系有稳定 ID；依据与推断同时用文字/线型区分；折叠展开无重复模型调用；100 可见节点在目标 iPhone 测帧时间和内存；导出无裁字/白图，超大图受控。 |
| 会员/成本 | 用户/服务环境隔离，恶意客户端不能自报 Pro；并发 reserve 不超额；重试不重复扣，退款/过期按既有权益模型；DB/Apple 失败不能悄悄把已验证权益改成 FREE。 |
| 隐私/安全 | 未授权随心记不进入任何新知识链；公开他人痕迹不归为当前用户；输入 system role 被拒绝，来源文本不能升级为系统指令；日志无凭证/原文全文；删除账号与撤权测试。 |

### 10.3 主要风险控制

- 数据兼容：先增加可选字段和版本契约；旧数据保留原样；锚点不能唯一修复时标缺失，不猜测、不删除重建。metadata 不允许无限塞入整书与所有历史。
- 性能：当前最多 500 条的规则刷新和每次聊天最近资料拼接会随重度使用变得低效；后续按用户/书/更新时间检索，限制工作队列与图大小，不在主 UI 线程做大规模分析。
- 隐私：私人书全文分析需明确范围、用途、第三方发送与保留策略；知识图是派生私人数据，同样需要删除、撤权和导出控制。不得自动接入随心记或自动分享到明台。
- 安全：用户/公共文本放在隔离的数据材料区，不作为新增 system 指令；严格 role 白名单、总 token/并发预算、证据 owner 校验；这些措施降低风险，不宣称仅靠 Prompt 就能防止注入。
- 成本与质量：供应商模型别名/价格会变；记录实际模型/usage/价格版本，留回归集。没有真实用量与高用量用户测算前，不能承诺 1500 次增强的利润或无限长上下文。

## 11. 需要产品负责人决策

1. 下一批是否仅做 P0a/P0b 的上下文、证据、完整性和质量测试；是否把已证实的发现误触发修正单列。
2. 每次主动解读是否要求重新生成；缓存复用可否显示“基于此前分析”。无论选择哪种，独立行为历史必须保留。
3. 增强/深度各自的质量承诺、等待时间、失败/取消计数；追问是否占一次额度，免费 300 与 Pro 1500 是否包含回望/导图。
4. 新的 10–15 元目标与此前 IAP 月/年商品价格方案如何统一；本轮没有修改任何商品或价格。
5. 首版导图基于阅读痕迹还是章节全文；私人正文上传与保存期限、是否允许跨书整理。
6. 现有“明确授权随心记”例外是否继续仅限旧聊天，还是新高级功能也允许用户逐次主动选择；默认不接入。
7. “发现”的最少独立会话/天数、冷却周期和用户关闭机制；建议默认更克制，不承诺每日必有发现。
8. 锚点多处命中/版本变化时的用户确认方式，以及历史数据是否启动单独、可撤销的关联补全工程。
9. 真实模型评测预算、基准文本来源与验收设备；质量门槛确定前不以“深度思考”名义上线长答案。

**结论：应优先补足稳定上下文、证据链、流完整性和可信观察，而不是新增大量模式。现有五模式、trace、同步、追问和 entitlement 可继续复用；共享知识结构放在回望阶段建立，导图作为同一数据的另一种呈现，商业限制最后接入。审查结束，等待确认下一阶段范围。**
