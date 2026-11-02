# 阅读回望 A V2 原生 Flutter 移植报告

交付整理：2026-11-02。范围仅为已批准的详情页视觉移植及必要局部交互；不是正式上线验收。

## 1. 实际文件与边界

修改：
- `lib/screens/xiaou/book_recap_screen.dart`：详情文章排版、目录与证据页内弹层、脚注、底栏、可编辑问题预填。

新增：
- `lib/screens/xiaou/widgets/book_recap_editorial.dart`：无状态字体样式、编号章节、来源区分引用组件。
- `test/support/recap_editorial_fixture.dart`：原创合成长文、4 条独立阅读记录、8 项证据，复用既有 Mock HTTP 和隔离 SQLite fixture。
- `test/screens/book_recap_editorial_test.dart`：11 项新增交互、撤回及视觉测试。
- `tool/reliable_upload_tests/test/book_recap_editorial_test.dart`：既有隔离测试 harness 的转发入口。
- 本报告及 `artifacts/book-recap-b24b2/a-v2-flutter-port/` 下截图、日志、复跑脚本、图册和核验清单。

没有修改 Controller、Repository、DTO、后端、数据库结构、Prompt、pubspec、字体资源或旧测试。没有移植其他五个页面；专属追问沿用既有页面，仅增加从具体问题安全预填草稿。没有新增入口挂载或改变 API 默认关闭状态。

工作区原有大量未提交/未跟踪成果不算本轮修改。修改前的页面原件及 Git 状态保存在 `baseline/`；对原有 lib、test、backend/src 和两套设计原型中的 385 个文件做 SHA-256 复核，只有上述页面文件改变。新文件不在原清单内。`screen-only.diff` 仅比较本轮页面前后，不把整个 Git diff 当作本轮成果。没有执行 reset/clean/commit/push。

## 2. 已实现的视觉与交互

- 暖白纸面、连续文章、01/02/03 编号、细线、小型蓝色引用，不拆成 Material 卡片网格。
- 390 宽正文左右 26，320 宽左右 20；保留现有最大阅读宽度限制。
- 正文 16 / 1.85；主标题 29 / 1.5；章节 22 / 1.5；条目标题及片段引用 17；用户原话文楷 19 / 1.85；辅助标签 12。均允许系统 TextScaler 生效，letterSpacing 为 0。
- 目录为按需打开的轻量页内弹层；跳转真实章节锚点，支持关闭、返回键和 Escape。
- 保存为次级、继续追问为主要操作；反馈和删除仍使用既有更多操作与确认链路。
- 每条脚注独立绑定真实 evidence ID，触控高度至少 44。不是按句子内容猜来源。
- 点击思考问题后，先读取专属回望讨论，复核会话 epoch、revision 与 fingerprint，再预填可编辑问题。没有自动发送模型请求。
- 弹层背景排除点击和无障碍语义，关闭按钮可获焦点；不额外开启一个会触发页面覆盖撤回的新 Navigator 路由。

## 3. 字体与原型差异

复用项目已声明的 `SourceHanSerifCN` 和 `LXGWWenKaiLite`，没有新字体下载或依赖。现有两个文件分别约 11.6 MB、13.9 MB，本轮字体包体增量为 0；继续沿用仓库内既有 OFL 授权材料。视觉测试显式加载真实字体，不能依赖 Widget 测试默认 Ahem 字体；界面无衬线字在测试机用 Windows YaHei 回退，不代表 iOS/Android 最终系统字形。

与 A V2 的明确差异：

| 项目 | 原生实现与原因 |
| --- | --- |
| 文章标题 | DTO 没有概括性总标题字段，使用已授权本机 bookId 对应书名，不把原型标题写死或用文本猜标题；首屏因此更短 |
| 引用身份 | 行内 quotes 只有 voice，用户引用标为“用户原话”，不伪称“批注/问题”；证据弹层才使用实际 kind 细分 |
| AI 归纳 | 与用户引文分开，显示“小U整理”等归属提示；推断和历史 AI 不冒充用户或原文 |
| 脚注 | 使用编号及“查看依据”，不捏造契约未提供的脚注短标题 |
| 证据背景 | Controller 一次只允许一种可撤回内容。证据打开时文章撤下，关闭后重新在线核验，不复制背景文章追求原型一致 |
| 追问 | 进入既有专属讨论区域，不另造一套浏览器式聊天弹层；保留可编辑草稿及原有发送/取消逻辑 |
| 字体度量 | Flutter 与浏览器换行、字重匹配、基线和行盒不同；采用真实字体渲染，不用图片替代正文 |
| 安全区 | 测试显式使用底部 34 的安全区；真实设备须另验。固定底栏与滚动区域分离 |

深色颜色从现有主题派生；不声称本轮已完成所有设备的暗色视觉验收。

## 4. 来源与撤回机制

继续使用既有 AuthSessionScope、local guard、展示许可和临时内容。新增状态只包括目录开关和章节 GlobalKey，不持久化私人正文、证据或问答。

目录和证据弹层从当前受控展示内容构建。断网、来源变化、consent 变化、会话变化、到期或页面退出时，旧内容及弹层撤下，已有问题输入框清空。异步预填使用发起时身份与版本，迟到响应不能恢复草稿。展示期限及服务器策略未改；fixture 的 120 秒仅是显式测试值，不是生产默认值。

后台测试经过 inactive 时撤回，再验证 paused/resumed 不恢复内容。paused 阶段 Flutter 停止绘帧，不能把该时刻的旧 Element 树误称为新绘制的屏幕。真实 OS 任务切换快照、VoiceOver/TalkBack、输入法及系统截图保护仍需真机验收，不能由 Widget 测试保证。

## 5. 测试与失败记录

环境：Flutter 3.38.9 / Dart 3.10.8，沿用 `tool/reliable_upload_tests` 的隔离 SQLite harness。这里“完整回归”指该 harness 全集，不是仓库所有后端及所有平台测试。未读取真实数据库、未调用模型、未建立线上连接。

| 执行 | 实际用例 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前 baseline-full | 336 | 334 | 0 | 2 |
| full-run1 | 347 | 338 | 7 | 2 |
| full-run2 | 347 | 344 | 1 | 2 |
| full-run3 | 347 | 345 | 0 | 2 |
| full-run4（相同代码重复验证） | 347 | 345 | 0 | 2 |

最终两轮完整运行均成功，结构化汇总见 `test-summary.json`，不能用最后成功掩盖前述失败。full-run4 的 5 行非 JSON 前导诊断也原样保留。图册采用该次成功运行的 `screenshots-1793581034523/`，不是早期失败截图。

对页面、局部组件、合成 fixture 和新增 Widget 测试四个文件执行 `flutter analyze --no-pub`，最终 **No issues found**（71.4 秒），完整输出在 `analyze-verified.txt`。早期 lint 输出仍保留。未宣称整个仓库静态检查零问题。

新增 11 项涵盖：真实来源归属显示、问题预填与专属发送；证据在断网/来源修改/consent/到期/账号/后台六种情况下撤回；目录 Escape 及过期；迟到草稿与迟到证据；390/320、长文、200% 字体、目录、证据、输入区域与占位的真实渲染。既有 screen/controller/display/local guard、上传和普通会话测试仍原样运行。正式设备、Apple、真实模型和线上服务均未验证。

两项既有 skip：`evidence mode refuses queue writes and business database initialization`；`evidence boot, foreground, timers, export and share leave DB/WAL and account unchanged`。未新增 skip，未修改既有断言或 SQLite 配置。

### 本轮调试失败，均保留原始日志

- first-widget：部分运行 14 通过、2 失败，页内 Semantics 缺少 explicitChildNodes；已修复，不算完整成功运行。
- editorial-attempt1/2/5、diagnostic：新 fixture 异步 SQLite 操作尚未排空，提前交互/拆卸导致等待；中断/超时日志保留，不计通过。改为有上限的就绪等待与正确拆卸，不降低业务断言。
- attempt3/4：测试 runner 工作目录/Windows 参数引用错误，未形成有效测试运行；改为直接调用本机 Flutter tools snapshot，保留错误日志。
- attempt6：单项预填测试 1 通过；editorial-run1：2 通过、7 失败。ensureVisible 后未等待布局完成，测试点击落到旧坐标；增加布局等待和 hitTestable 检查，未删除断言。
- visual-run2：真实截图用例 1 通过。
- full-run1 的 6 项新失败为上述点击驱动问题；full-run2 剩余 1 项为测试直接跳到 paused 后仍要求新渲染，已按真实生命周期验证 inactive 和 resume 两个可绘帧状态。

### 单独发现的既有间歇失败

full-run1 的第 7 项失败是原有 `book_removal_test.dart` 的 `only explicit permanent deletion removes known history and queues tombstones`。其 Mock `replaceLibraryBooks` 直接保留上传层传来的定长 List；若 replace 先于 purge，Mock 的 removeWhere 抛 UnsupportedError，上传器按既有错误逻辑安排重试，因此队列非空。

原测试与对应业务文件都未改。`probe-existing-mock.dart` 不导入 App、不访问 DB/网络，复现同样的定长列表异常；日志在 `existing-mock-probe.txt`。这是本轮定位到的既有 Mock 缺陷，不足以证明就是更早那次未定位失败的同一个原因。没有为取得全绿去改上传业务或原断言。建议另行批准仅修复该 Mock 对输入集合的所有权处理并补两种顺序测试。

### 复跑

在项目根目录运行（每次使用新标签，脚本拒绝覆盖旧日志）：

```powershell
node artifacts/book-recap-b24b2/a-v2-flutter-port/run-tests.cjs review-repeat-unique
node artifacts/book-recap-b24b2/a-v2-flutter-port/summarize-tests.cjs
```

runner 用 `--no-pub --concurrency=1 --reporter json`，stdout/stderr 分开完整保存；8 分钟超时仅终止自己启动的测试进程树。未完成运行不计成功。原始 JSONL、stderr、超时记录保留；统计排除加载器和隐藏 hooks，但计入真实跳过用例。baseline 中的非 JSON 前导诊断行也原样保存。

## 6. 截图交付

统一目录：`artifacts/book-recap-b24b2/a-v2-flutter-port/screenshots/`。图册 `index.html` 可直接打开，无需服务器；左为浏览器原型、右为真实 Flutter，不混用来源。

| 文件 | 内容 |
| --- | --- |
| flutter-390.png / flutter-320.png | 390×844 / 320×640 首屏 |
| flutter-390-full.png / flutter-320-full.png | 对应宽度的实际文章完整 RenderRepaintBoundary |
| flutter-390-thinking.png / flutter-390-questions.png | 我的思考 / 继续思考 |
| flutter-390-contents.png | 目录 |
| flutter-390-evidence.png | 实际授权 evidence DTO 弹层 |
| flutter-390-ask.png | 可编辑的预填问题 |
| flutter-390-keyboard.png | 模拟键盘占用 280 高度后的操作可见性 |
| flutter-320-scale200.png / flutter-320-scale200-contents.png | 200% 字号正文 / 目录 |
| flutter-320-withdrawn.png | 失效无正文占位 |

所有 PNG 保持原始字节和分辨率，尺寸、来源目录、SHA-256 在 `screenshots-manifest.json`。长文图不是扩大手机视口或浏览器替代，而是真实文章组件完整捕获；固定导航与底栏请看首屏。历史失败运行的截图目录仍保留，不纳入最终图册。

本轮完整文章尺寸为 390×3886 和 320×4331；其他图片为对应的 390×844 或 320×640。图册中的缩放只用于浏览，不改变原 PNG。

## 7. 已知限制及停止点

- 已完成代码及模拟组件验证，不等于真机或线上可用。
- 需要人工确认书名标题、原型/Flutter 行距差异、用户引用标签及证据背景遮蔽是否符合预期。
- 详情文章目前完整布局以支持章节锚点；合约内最大输出在低端真机上的内存/滚动性能未 profile。长文截图不是性能证明。
- 专属追问沿用已有视觉，没有借本轮重做整套聊天界面；安全占位和其他页面亦未批量精修。
- 截图对合成文本与指定尺寸进行检查，不承诺所有 Unicode、字体回退和动态类型级别均已覆盖。
- 正式展示策略、后端挂载、可信环境/真实模型和真机验收仍需后续单独授权。未进入 B2.4c，未开放入口、构建发布、部署或上传 TestFlight。
- 保留所有原有成果、备份与测试基准，等待人工视觉验收。
