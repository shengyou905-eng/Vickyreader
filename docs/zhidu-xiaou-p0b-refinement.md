# 小U P0b：真实评测后的代码精修

日期：2026-10-19。状态：小范围代码精修与离线回归完成，暂停等待确认。没有调用付费模型；不把第三阶段 v2 回答重新标为 v3 结果。

## 修改内容

### 条件逻辑

将条件方向从拆解模式的简短提示提升为五种模式共有规则：

- “只有 A 才 B”：B 成立须有 A，不能反推 A 保证 B。
- “只要 A 就 B”：A 推出 B，不能反推 B 必然来自 A。
- 原文明确给出两个方向（包括“当且仅当”）时才按双向条件理解，不一概否认充分条件。
- 用“已预约但仍不可入馆”的假设反例说明必要不等于充分；反例不作为书籍事实，不要求模型抄进回答。

新增三组逻辑反例及 AUTO-01 构造/纠错回归。原有 20 例的材料、参考答案、禁止误读和评分标准未修改。真值表只验证测试反例自洽，不代表已经检验模型实际推理。

### 证据分层与读者表达

保留原有原文、元数据、历史 AI、用户问题及范围结构。Prompt 明确这些分类只供内部识别，不向读者清点 `book_text`、空历史、JSON/UTF-16 封装等信息；证据不足时只说解决本次问题还缺什么。

没有加删词过滤器：技术类书籍原文本身包含这些术语时，仍可正常解释和逐字引用。新增本机 HTTP 分块 SSE 测试，确认这类原文的回答原样传输且能通过原文核对。

### 输出与范围

- 五种模式保留各自分析目标，取消把目标当成必填栏目：简单问题自然直答，复杂问题才分层；追问尤其纠错先给更正与必要依据。
- 默认首轮请求不再无条件要求“结合已提供前后文”。根据构造后实际存在的原文片段生成内部范围提示，区分无相邻材料、仅前文、仅后文、两者都有及仅有所在段落。
- 空串/纯空白不算有效上下文；所在段落可用于核对，但不能据此宣称掌握完整前后文。旧请求缺少原文时，不以书名或旧 AI 回答补作原文。
- 页面和章节仍只称片段，不升级成整章、整书。没有增加任何请求字段或修改 SSE。
- 分母、百分比与比例检查只在材料或问题确实涉及数值比较时适用；“全部改善”不再作为机械讨论分母的理由。
- 保留并强化未知人物身份不猜、概念缺定义不编造也不过度排除、旧 AI 可以被原文纠正等约束。

### 缓存版本

后端 Prompt 和 Flutter 缓存常量同步提升到 `xiaou-reading-v3.20261019`，避免新版客户端复用 v2 缓存键。没有删除历史、合并独立解读或缩短原文预览。

限制仍然存在：仅升级后端不能使尚未更新的旧客户端内存缓存自动失效；本轮未新增版本握手协议。已保存历史仍显示原先回答，不会被重写成新版本。

## 文件范围

相对于本轮开始的工作区，仅修改 5 个已有文件，新增 2 个文件：

| 文件 | 内容 |
| --- | --- |
| `backend/src/services/readingInterpretation.js` | 公共逻辑约束、自然表达要求、精简五模式指令、实际来源范围提示、v3 版本 |
| `lib/services/reading_history.dart` | 仅同步缓存版本常量，不改历史筛选或保存逻辑 |
| `backend/src/controllers/readingQuality.http.test.js` | 新增范围、技术原文原样传输、AUTO-01 纠错三个本机 HTTP 子测试 |
| `tool/xiaou_reading_eval/live.test.cjs` | 预算测试独立核算实际请求字节，不再把 v2 的字节预留当成所有版本的固定金额 |
| `tool/xiaou_reading_eval/README.md` | 当前版本、离线复跑方式及真实验证边界 |
| `backend/src/services/readingInterpretation.refinement.test.js`（新增） | 15 项规则、反例、范围、原文保护、14轮与基准不变检查 |
| 本报告（新增） | 变更、测试结果与未解决问题 |

没有修改 controller 业务实现、模型/参数、客户端 API、SSE、账号隔离机制、数据库 schema、IAP、Pro、Obsidian、小U发现或阅读 UI。

预算测试说明：Prompt 字节变化使新构造计划的预留不再等于第三阶段 v2 的 ¥0.419896。测试改为按实际消息 UTF-8 字节、8192 封装余量和原高峰单价独立计算，仍严格检查 12 次及低于 ¥2，不调整这些上限；没有执行真实请求。第三阶段原始 plan、用量、金额、回答及锁文件均不变。

## 离线验证

| 检查 | 结果与边界 |
| --- | --- |
| 修改前后端非 PostgreSQL + 离线基线 | 178 项通过 |
| 定向构造/HTTP/20例回归 | 96 项通过 |
| 最终后端非 PostgreSQL + 离线全量 | 196 项通过，0 失败；相对基线新增 15 项纯测试和 3 个 HTTP 子测试 |
| Flutter 独立 harness 全量 | 118 项通过、2 跳过、0 失败；包含账号隔离、独立历史、14轮、取消、原文预览等已有回归 |
| `dart analyze lib/services/reading_history.dart` | No issues found |
| `backend` 的 `npm run check` | 通过 |

数量包含 Node 父/子测试，不应当作 196 条真实模型质量样本。所有模型 HTTP 均使用本机合成替身；测试中的“正确回答”不是本轮实际模型生成。未读取 DPAPI 凭证，未运行 `live.cjs --execute`。

首次定向测试中新增的技术原文断言未正确拼接分块 SSE，已改为解析事件后拼接内容再逐字断言；没有为通过测试改业务传输或放宽核对。全量回归还发现并修复了上述预算测试固定 v2 金额的问题。最终均通过。

Flutter 初次启动等待较久，随后正常完成；使用临时 `--no-version-check --suppress-analytics` 参数复跑也通过，未升级 SDK 或修改项目 SQLite 配置。输出中的合成迁移失败信息来自既有事务回滚用例的故意注入，最终断言通过；既有键盘 hit-test warning 仍在。根目录 Windows SQLite 加载失败、其他文件 BuildContext warning 未顺手修复，也未宣称全项目无警告。

复跑：

```powershell
# 项目根目录：定向离线回归
node --test tool/xiaou_reading_eval/offline.test.cjs backend/src/services/readingInterpretation.test.js backend/src/services/readingInterpretation.refinement.test.js backend/src/controllers/readingQuality.http.test.js

# backend 目录：不运行 PostgreSQL 集成测试
$tests = @(rg --files src -g '*.test.js' | Where-Object { $_ -notlike '*.postgres.test.js' })
node --test $tests ../tool/xiaou_reading_eval/offline.test.cjs ../tool/xiaou_reading_eval/live.test.cjs
npm run check

# tool/reliable_upload_tests 目录
flutter --no-version-check --suppress-analytics test --no-pub --reporter expanded
```

没有运行真实 PostgreSQL、iPhone、Apple Sandbox 或生产回归；Flutter 测试只打开临时合成数据库。

## 尚未解决

1. Prompt 规则和请求契约通过，不等于真实模型已经稳定消除逻辑错误、字段外露或机械模板。需要另行授权的小样本真实复测和人工评分，本轮不调用。
2. 引文门禁仍只查约定格式的逐字出处，不检查必要/充分条件、人物指代、背景事实或“真引文支持假结论”。未新增脆弱的关键词语义裁判，也未对输出作静默删改。
3. 14 轮离线测试证明固定证据及讨论窗口契约保留，不证明真实模型 14 轮语义表现。窗口长度和预算仍有上限。
4. 旧客户端内存缓存、历史回答和绝对阅读位置的既有限制未扩大处理；没有改数据库或协议。

完成后对本轮登记的 326 个源码、测试、文档和第三阶段结果逐文件核对：仅上表 5 个已有文件改变，0 个丢失，新增仅上表 2 个文件。固定语料和 rubric 哈希不变，第三阶段原始回答哈希仍为 `2f103e9973a655c70d9de8e2a71ff51293a5bffbdd3f66a3cd1efcb2b298851f`；Git index 为空。

未调用付费模型，未操作真实用户数据、数据库或服务器；没有构建安装包、部署、commit 或 push。到此暂停。
