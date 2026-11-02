# A V2 Flutter 交互精修

日期：2026-11-02。仅原生 Flutter 回望页交互；正式入口保持关闭。

## 文件范围

- `lib/screens/xiaou/book_recap_screen.dart`：导航收纳、48px 触控、证据单一返回操作、非正文位置标记、核验后滚动恢复。
- `test/screens/book_recap_editorial_test.dart`：新增 8 项针对性测试及真实组件截图；继续保留原有 11 项。
- `test/screens/book_recap_screen_test.dart`：已有详情到历史流程增加打开“更多”一步，原断言不变。
- `test/screens/book_recap_visual_test.dart`：相同导航路径适配，原断言及截图流程保留。
- 本报告及 `artifacts/book-recap-b24b2/a-v2-interaction/`：本轮修改前四文件原件、Git 状态、完整日志副本、截图和图册。

未修改 Controller、Repository、DTO、后端、数据库、Prompt、字体、正式展示策略或 Reliable Upload。没有发布、部署、提交、推送或开放入口；没有读取真实资料或调用模型。

## 交互变化

### 导航

详情页保留返回、章节目录和更多；“我的回望”位于更多操作的首项。沿用原 `_historyPage`，没有绕过在线性、会话检查或删除确认。导航壳内图标触控下限改为 48×48，图标大小和 A V2 的正文设计不变。

证据弹层由一个“返回回望”操作关闭，移除原底部重复返回按钮；背景页标题不再重复“阅读依据”。来源类型、章节、用户原话或历史 AI 标签、fragment-only 说明均保留。返回操作采用现有深色链接色，避免浅蓝文字对比不足。

### 返回位置

打开证据前，页面仅暂存 recap ID、bookId、revision、source fingerprint 和逻辑滚动偏移。身份与 origin 仍由原有 workspace session 绑定，不新建账号体系。没有保存正文、引用文本、截图或问答副本，也不持久化偏移。

关闭证据仍执行原 `readForDisplay`，重新核验本地来源、账号、授权及服务器展示许可；之后比对位置标记的 ID、书籍、版本和指纹。不同版本不恢复位置，并撤回正文。标记在读取开始时即消费，失败不会留作后续自动重放。

授权通过后，在实际布局完成时将偏移限制在当前合法滚动范围内，再恢复位置。布局阶段通过 Visibility 暂不绘制或暴露文章语义，恢复后才呈现，避免先显示文首再跳下去。该组件只包含本次新核验的内容，失效时原有 Controller 撤回会移除整个文章子树，不以 maintainState 保留旧正文。

帧回调再次检查页面 epoch、可用性和当前正文许可。退出、账号切换、consent 撤销、来源变化、断网均沿用原撤回链路，并清除位置状态。

### 长文与边界

保留已有连续文章与章节锚点，不建立第二份渲染模型。章节目录跳转、最后引用与固定底栏间距有真实 Widget 坐标断言；恢复偏移误差要求不超过 1 逻辑像素。

位置是同布局条件下的滚动偏移，不是精确书籍锚点。查看证据期间若改变屏幕尺寸或系统字号，仅保证偏移有界，不承诺回到同一个字。没有声称完成低端真机帧率或最大输出性能 profiling。

## 自动化验证

沿用隔离 SQLite、Mock HTTP 和现有 `tool/reliable_upload_tests` harness。下表数字均为本轮真实执行，不借用上一轮 345 通过作为本轮结果。

| 运行 | 总数 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| interaction-targeted | 16 | 14 | 2 | 0 |
| interaction-targeted2 | 16 | 15 | 1 | 0 |
| interaction-full1 | 355 | 352 | 1 | 2 |
| interaction-full2（最终代码） | 355 | 353 | 0 | 2 |

所有失败都保留：

1. 首次定向测试在尚无可点击引用时调用 Finder.first；改为有界滚动寻找可点击引用，不弱化位置恢复断言。
2. 首次故障注入 failNext 在前置核验就失败，未到达预期的 view；改为 view 返回未批准的展示策略，保留“请求实际发生且正文不出现”的断言。
3. 第二次定向测试发现真实的 40px 目录触控区域，已修正为 48px，保留 >=44 的断言。
4. full1 的版本测试把 revision 写为原本已经存在的 2，实际没有模拟版本变化；改为从当前版本严格递增。原“新版本不得显示旧文章”断言保留。

新增 8 项包括：一次完整的导航、阅读位置恢复、章节跳转、底部与 320/200% 字号测试；七种返回失败/竞态（不认可的展示策略、consent、来源、账号、版本、断网、超时）测试。继续运行原有证据打开/关闭、到期、后台、迟到请求、生成/保存/历史/删除及专属问答测试。

两个既有跳过仍为 evidence 模式写保护与 evidence boot/foreground/export/share 的环境相关测试；没有新增 skip。SQLite 迁移失败回滚测试中的预期错误日志不能误算为真实数据库异常；统计以测试协议的 testDone 为准。

最终 19 项 editorial 测试全部通过（原有 11 + 本轮新增 8），包含在 353 中，不重复累计。完整回归指当前 Flutter 隔离 harness；不代表已跑后端或所有平台真机测试。本轮两个完整运行中的旧永久删书测试均通过，风险仍按下节保留。

四个修改文件的 `flutter analyze --no-pub` 最终结果为 **No issues found**（43.9 秒），完整日志见交付目录 `analyze.txt`。没有将这一结果宣称为全仓库静态检查通过。

## 既有 Mock 问题

没有改动 `book_removal_test.dart` 或上传业务。该测试本轮参与完整回归。此前定位的风险仍是 Mock 保存定长列表后 removeWhere，特定 replace/purge 顺序可能失败；偶然通过不能证明问题消失。

独立修复建议（本轮未实施）：仅让 `_Remote.replaceLibraryBooks` 复制输入为自己拥有的可增长列表，再增加 replace→purge 和 purge→replace 两种顺序测试；保留原队列为空断言。不要为了 Mock 修改真实上传协议或重试逻辑，须独立批准。

## 日志、截图与复跑

原始运行日志由上一轮既有 runner 写入 `artifacts/book-recap-b24b2/a-v2-flutter-port/interaction-*.jsonl` 和同名 stderr；本轮交付目录保留完整副本。每次执行使用新标签，不覆盖失败记录。

```powershell
node artifacts/book-recap-b24b2/a-v2-flutter-port/run-tests.cjs review-interaction-unique
node artifacts/book-recap-b24b2/a-v2-flutter-port/summarize-tests.cjs
```

图册：`artifacts/book-recap-b24b2/a-v2-interaction/index.html`。图像均为真实 Flutter Widget、真实项目字体和原创合成材料，不是浏览器原型、AI 重绘或线上截图。PNG 原样复制，文件尺寸与 SHA-256 记录在交付清单中。

重点图为 `navigation-390.png`、`evidence-390.png`、`restored-390.png`、`authorization-failed-390.png`、`navigation-320.png`、`navigation-320-scale200.png`。

## 未验证与停止条件

未进行真机、系统输入法/读屏器、跨设备真实数据或模型联调；200% 字号与语义触控测试不等价于完整无障碍认证。也不承诺不同字体尺寸下的逐字位置恢复。

失败占位仍沿用已有页面错误与 Controller 状态说明，可能显示相同提示两次；本轮没有将其扩大为错误页重构。未隐藏提示或把核验失败伪装为成功。

没有性能优化到数据层，没有修改原授权和失效策略。本轮完成后仅等待人工验收，不进入 B2.4c。
