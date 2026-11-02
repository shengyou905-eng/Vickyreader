# 小U P0b 第二阶段变更报告

日期：2026-10-19。状态：小范围代码开发及离线回归完成，等待下一步确认；不是模型质量盲评或部署完成。

## 1. 实际修改

### 五模式 Prompt 与缓存版本

新增纯模块 `backend/src/services/readingInterpretation.js`，集中维护五种模式及共用证据规则。版本为 `xiaou-reading-v2.20261019`。

| 模式 | 新增/强化的检查目标 |
| --- | --- |
| 自动 | 只抓真正难点，不轮流填满栏目；材料不足的比喻不强定唯一作者意图 |
| 通俗 | 改写后保留量词、否定、让步和条件，不用辅助类比新增事实 |
| 拆解 | 分句层级、修饰/指代、否定作用域、必要/充分条件、反事实；不强套语法标签 |
| 概念 | 本文局部定义优先、相邻概念及反例、不同章节口径；不伪造定义/词源 |
| 论证 | 明示前提与省略桥梁、混杂因素、证据力度、样本/分母/百分点、事实与价值的区分 |

去掉固定最低字数要求，简单问题可以短答；复杂问题保留必要理由与边界，不索取或展示模型内部思维链。模型选择、thinking、temperature、max_tokens 均保持原值，没有新增模式或收费判断。

客户端缓存键加入相同 Prompt 版本，以及书名、作者、章名，并用 JSON 数组编码避免分隔符歧义。相同语境仍可复用答案，但每次主动解读继续保存独立 UUID/trace；不删除旧历史。测试检查服务端与客户端版本一致。

限制：没有增加服务端版本握手协议。仅升级后端不能主动使尚未更新的旧客户端内存缓存失效；以后 Prompt 变更必须同步提升两端版本。新客户端不把旧历史当新缓存，但历史详情仍保留原有回答。

### 证据约束与原文引用核对

模型收到的材料现在明确分为：

- `book_text`：当前确实提供的原文片段；只有它能作为直接原文引用来源。
- `catalog_metadata`：收到的书名、作者、章节；缺失仍为空，不猜测作者。
- `user_question`：用户问题，不直接升格为作者事实。
- `ai_answer_not_source`：首轮 AI 回答，可纠错，不当作书籍证据。
- 共用 Prompt 要求自然标明补充背景、推测及其边界；历史讨论同样不是原文证据。

书籍信息与正文用 JSON 编码的 user 数据消息交给模型，不再把用户提供的书名或 reader-question 正文拼入 system 指令。system 只保留版本化规则和任务。输入分层降低提示注入风险，但不能宣称仅靠角色/JSON 就完全防注入。

显式直接引文约定为 `原文：“逐字片段”`（也接受「」等形式），英文为 `Source quote: "exact text"`。回答流完整完成后、发 completed/DONE 前，服务端检查这些引文是否逐字存在于本次实际提供的书籍片段。支持中文嵌套引号；未知出处、仅出现在旧 AI/用户问题/书籍标题中的文字、未闭合的显式引文，不通过。

失败走原有 SSE `error + status: incomplete`，不发 completed/DONE，不自动重试；新客户端沿用既有逻辑，不保存为成功解读。验证需要暂存已输出文本，上限 32,000 UTF-16 字符；不新增数据库写入或副本。

**明确限制**：这不是完整事实检查器。没有按约定格式标出的引文、意译、背景事实、算术或“真引文支持了假结论”，不能靠子串检查自动判真。HTTP 回归中的正确答法来自合成替身，不能证明真实模型不再犯这些错误。流式内容可能已短暂显示，验证失败后不会标为成功；本轮未新增完整缓冲后一次性显示的 UI。

### 范围与追问历史

继续使用现有 `selectedText/paragraph/contextBefore/contextAfter/pageText/chapterText/scope`，不添加客户端请求字段。

- 明确选区及邻接语境、当前页面片段、章节片段；不把章窗口宣称为整章或整书。
- 每段记录实际截取的 UTF-16 start/end、收到字段长度和 truncated。前文保留靠近选区的尾部，后文保留头部，避免截断 emoji 的代理对。
- 范围仅相对于客户端已经发送的字段。无法知道的整章偏移、客户端更早的截取和书籍版本不编造；现有客户端锚点/预览保存方式不改。
- 阅读追问按完整 user/assistant 轮次组织，丢弃孤立 assistant、未完成问题和空占位，不把失败回答当完成历史。角色白名单及原有输入预算仍执行。
- 在最多 12 轮、32,000 字符中，先保留最近 6 轮，再尽可能保留较早 2 轮明确“纠正/更正/我指的是/未解决”等表达，剩余空间按最近轮次补齐；输出仍按时间顺序。
- 明确表达检测只是轻量优先级，不判断更正是否正确、问题是否真正解决，不对用户作心理推断。过多纠正或长回答超过预算仍可能退出窗口，不能宣称无限记忆。
- Provider 将当前阅读讨论窗口与 UI 最近 20 条显示列表分开。只有完成的轮次进入讨论窗口；新独立解读、换书或账号失效清空当前窗口，历史原始记录不删除。详情与问小U复用同一筛选逻辑。

## 2. 兼容性与未触碰范围

| 边界 | 结论 |
| --- | --- |
| 客户端 HTTP 协议 | 路径、字段、类型、认证、X-Request-ID 不变；无新增必填字段 |
| SSE | 仍为协议 2 的 content/status/error/completed + DONE；新增检查只使用已有失败状态 |
| 旧数据/旧请求 | 作者/上下文缺失不补猜，缺模式仍 auto；旧历史保留，可见原文不足时不能冒称存在证据 |
| 新客户端对旧后端 | 仍发送原字段及 user/assistant 文本，旧后端可读取；不具备新后端的原文核对能力 |
| SQLite/PostgreSQL | 无 schema、migration、真实数据修复、backfill 或数据清理 |
| 安全/账号隔离 | 保留 AuthSessionScope、sessionEpoch、请求取消及异步保存身份校验；旧请求不因窗口保留而复活 |
| 产品边界 | 五模式继续免费；不接随心记，不改发现规则、IAP、Pro、Obsidian、Reliable Upload 协议或长原文预览 |

给供应商的 JSON 材料结构是服务端内部 Prompt 构造，不是新增 Flutter/SSE DTO。没有因本轮引入需要单独批准的新客户端协议或数据库迁移。

## 3. 文件清单

相对于本轮开始的工作区，不相对于旧 HEAD；原有未提交成果保留。

修改 7 个文件：

| 文件 | 内容 |
| --- | --- |
| `backend/src/controllers/ai.controller.js` | 两个阅读接口接统一构造器；流完成前核验显式引文；普通 Agent/发现逻辑不改 |
| `backend/src/controllers/aiReliability.http.test.js` | 保留原有断流、防重断言，将书籍数据检查调整到 user 材料而非 system |
| `lib/providers/ai_provider.dart` | Prompt 版本缓存键、元数据缓存区分、当前讨论窗口与 UI 分离 |
| `lib/services/ai_service.dart` | 仅阅读解释/追问/阅读问题使用整轮历史；普通小U Agent 仍用原方法 |
| `test/providers/ai_reliability_test.dart` | 14轮中途纠正/未决保留、不重复当前问题、独立历史、缓存元数据回归 |
| `tool/xiaou_reading_eval/offline.test.cjs` | 将新 Prompt 模块纳入只读 hash 记录 |
| `tool/xiaou_reading_eval/README.md` | 补第二阶段复跑与证据能力边界 |

新增 7 个文件：

- `backend/src/services/readingInterpretation.js`
- `backend/src/services/readingInterpretation.test.js`
- `backend/src/controllers/readingQuality.http.test.js`
- `lib/services/reading_history.dart`
- `test/services/reading_history_test.dart`
- `tool/reliable_upload_tests/test/reading_quality_test.dart`
- 本报告 `docs/zhidu-xiaou-p0b-stage2.md`

固定的 `cases.v1.json`、`rubric.v1.json` 未修改，没有为通过测试降低标准或改 gold。

交付前逐一对比本轮纳入检查的 297 个已有源码/测试/文档文件：仅上述 7 个文件改变，0 文件丢失；新增也仅上述 7 个文件。原有 IAP、Obsidian、数据库及发现规则源码保持原样。定向 `git diff --check` 通过，Git index 未暂存。

## 4. 验证结果

| 检查 | 本轮实际结果 |
| --- | --- |
| 开发前后端非 PG 基线 | 89 通过 |
| 开发前现有 Flutter harness | 113 通过、2 跳过 |
| 最终后端非 PG 全量 + 离线评测 | **167 通过、0 失败**：原89 + 新51（Node统计含父/子测试）+ 原离线27 |
| 最终 Flutter harness 全量 | **118 通过、2 跳过、0 失败**，新增4项纯窗口测试及1项缓存Provider测试，既有14轮用例增强 |
| diagnostics 编译模式 | **3 通过、1 跳过**，DB/WAL/账号不变断言通过 |
| 本轮6个 Dart 源码/测试定向 analyze | No issues found |
| backend npm run check | 通过 |

数量存在父子用例及模式复跑，不应相加当作独立语义评测数。20例在构造器及 HTTP 层均使用同一固定材料；正确性/证据/不确定性等标准仍用于后续人工评审，**没有模型质量分数**。

HTTP 测试真实运行 controller、HTTP fetch、SSE parser 和 guard，上游请求被强制改到本机 loopback，合成密钥不会发给真实供应商。覆盖：20例材料与模式、推断/AI非原文、引用错误与无自动重试、14轮固定证据和较早纠正、范围字段、截断、非法角色、既有并发防重与取消。

Flutter 测试使用临时合成 SQLite、fake HTTP 与离线约束。覆盖独立 trace、多账号、离线/缓存、异步会话、长原文展开及 UI 既有回归，没有打开用户真实数据库。

复跑：

```powershell
# 项目根目录：离线基准 + 新后端质量契约
node --test tool/xiaou_reading_eval/offline.test.cjs backend/src/services/readingInterpretation.test.js backend/src/controllers/readingQuality.http.test.js

# backend 目录：排除会操作真实 PostgreSQL 的集成测试
$tests = @(rg --files src -g '*.test.js' | Where-Object { $_ -notlike '*.postgres.test.js' })
node --test $tests ../tool/xiaou_reading_eval/offline.test.cjs

# tool/reliable_upload_tests 目录
flutter test --no-pub --reporter expanded
flutter test --no-pub --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=true test/local_diagnostics_mode_test.dart --reporter expanded
```

没有重跑真实 PostgreSQL、iPhone、真实模型、Apple Sandbox 或完整根目录 Flutter 测试。根目录既有 Windows SQLite 加载问题、非本轮文件的 BuildContext warning 和既有键盘 hit-test warning 未顺手重构，不能写成全项目无警告。

## 5. 仍未解决与停止点

1. 没有真实付费模型盲评，不能宣称准确率提高多少或20例语义全部达标。Prompt 规则与契约通过，不等于模型一定遵守。
2. 原文存在核验不能证明逻辑支持；未按约定格式表达的伪引文和其他事实错误仍需人工评测。模型可能未提供任何直接引文，本轮不凭格式缺失给所有答案制造失败。
3. 绝对阅读位置、客户端此前是否已截断、全章检索与全书定义没有新增协议或检索能力，未知就保留未知。
4. 讨论窗口是有预算的显式规则，不是长期语义记忆；大量早期纠正、未显式表达的未决点、重开后的资料不足仍有局限。不生成摘要冒充原历史。
5. 旧客户端内存缓存不能仅靠后端更新强制失效；后续如要在线版本协商，应另提兼容方案并获确认。
6. Token/延迟/成本计量仍停在第一阶段设计，未落表、未扣额度、未改价格。真实质量和费用都不能用 mock 耗时代替。

本轮没有构建、部署、提交、推送、真实迁移或 IAP 推进。到此暂停，等待确认下一步范围。
