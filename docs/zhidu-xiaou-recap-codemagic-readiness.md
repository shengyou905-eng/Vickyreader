# 阅读回望：Codemagic 构建准备与提交审批

日期：2026-11-05，北京时间。用户自行在 Codemagic 构建 IPA、自行上传 TestFlight。本轮没有构建、上传、部署、Git 暂存/提交/推送，没有连接生产数据库、改变回望开关或调用付费模型。

## 结论边界

Flutter 客户端接线可进入 Codemagic 的编译验证，不能将 Windows 自动化测试称为 Xcode 签名构建或 iPhone 验收。真实模型质量、原生网络切换及完整真机流程仍未验证。正式开关关闭时新包不显示回望入口，这是预期行为，不是构建失败。

用户本轮确认 App Store Connect 已上传的最高 build 仍为 13，下一候选版本确定为 **1.0.0 (14)**。若在本次构建前又上传了其他包，须重新确认编号。

推送前还有一项历史安全事项必须单独处理：`backend/.env` 已存在于当前 HEAD，含两个非空敏感配置字段，没有明显占位标记；本轮没有输出、验证其有效性或改动其值。建议批准提交时停止跟踪该文件但保留本机副本，并由负责人判断相关凭证的轮换需要。停止跟踪不能清除 Git 历史。本轮没有执行 `git rm --cached`、密钥轮换或历史改写。

## 接线审查

| 环节 | 实际代码与结论 |
| --- | --- |
| 入口 | `lib/app.dart` 将服务端资格入口注入现有小U页，不新增Tab。`recap_pilot_entry.dart` 仅iOS启用，GET `/api/recaps/capability` 成功且policy匹配才显示，点击前再次核验。没有单账号UUID白名单。 |
| 鉴权 | `AuthSessionScope` 绑定账号、epoch和origin，`AuthService.token` 提供当前账号Bearer；API不跟随重定向，不把身份放到客户端可伪造的body里。会话变化拒绝迟到结果。 |
| 授权 | 资格接口复用服务端AI consent；页面生成与追问复用 `AiConsentGate`。未授权时入口隐藏，可在既有隐私设置完成授权后返回小U页。 |
| 来源 | `BookRecapMaterialCatalog`、`BookRecapLocalGuard` 按owner/book/远端ID读取，阻止pending编辑、删除、未知追问及永久删书。不按书名合并、不自动上传。 |
| 请求 | prepare、generate、save、cancel、feedback、delete沿用真实HTTP adapter。生成结果以operation状态处理，没有虚构的operations GET。请求重放保留原ID与body。 |
| 展示 | 旧GET只取元数据；正文必须经过display/view，校验policy/recap/book/revision/fingerprint。服务端45秒许可与客户端60秒上限取更短值，并扣除请求耗时。 |
| 证据 | display/evidence使用真实evidence ID和来源分类，保留reader_context、historical_ai及fragment_only限制；关闭后重新在线核验，再恢复非正文滚动定位。 |
| 追问 | 独立回望follow-ups通道，不走普通小U聊天；每次校验原始来源、revision及许可，问答有序展示。 |
| 历史 | display/history有界分页，仅元数据；scope恢复严格依赖本地稳定ID。缺少本地来源不能自动恢复私人正文，但可删除自己的云端结果。 |
| 撤回 | Controller、页面继续监听账号、来源、consent、网络、路由与App生命周期；旧正文/证据/追问不能因缓存重新出现。NWPathMonitor只证明网络路径，不保证互联网可达，HTTP错误仍失败关闭。 |

## 本轮最小修复

确认原入口只在initState发现资格：第一次离线、consent未完成、服务关闭后，即使回到IndexedStack中保留的小U页，也可能无法重新发现入口。

本轮增加：

- 入口接收小U已有isActive/refreshSignal；回到页签和恢复前台时重新发现资格，不轮询。
- 网络路径恢复、账号和consent变化触发重新核验；隐藏旧入口并取消旧请求。
- discovery epoch加原会话校验拒绝A→B→A及后台迟到响应。
- 点击时仍复核资格；过时点击响应不能清掉更新会话中的入口。
- 更新两处过时的“仅隔离测试组合”注释，没有改变页面排版或业务协议。
- `pubspec.yaml` 只新增版本行修改：1.0.0+13 → 1.0.0+14。该文件原有图标配置改动保留但不属于本轮提交。
- `.github/workflows/ios-unsigned.yml` 移除push自动触发，保留既有手动工作流但不执行。此后合并main也不会自动构建其他CI的IPA。

## Codemagic 配置

仓库没有 `codemagic.yaml`。用户成功构建截图来自网页 Workflow Editor 的 **Default Workflow**；本轮不添加YAML来覆盖已有签名、Publishing或环境组。

| 项目 | 本次选择 |
| --- | --- |
| 分支 | `codex/reliable-upload-acceptance`，批准提交推送后选择包含本轮文件的新commit，不要重跑旧的e0d5d13 |
| Workflow | 现有 `Default Workflow`（Flutter Workflow Editor） |
| 平台 / 模式 | iOS / release |
| Version / Build | 1.0.0 / 14 |
| Bundle ID | `com.youxugarden.zhireader`，以实际Xcode配置为准，不是历史产品ID示例中的zhreader |
| API | `https://api.youxugarden.com` |
| 诊断模式 | `ENABLE_LOCAL_SYNC_DIAGNOSTICS=false` |
| 签名及凭证 | 保留用户现有Apple Distribution、profile和发布集成；本轮不查看或更换 |

Build arguments需确认没有残留13或12，推荐明确填写：

```text
--build-name=1.0.0 --build-number=14 --dart-define=API_BASE_URL=https://api.youxugarden.com --dart-define=ENABLE_LOCAL_SYNC_DIAGNOSTICS=false
```

命令行版本参数会覆盖pubspec版本，所以仅改pubspec不能抵消网页中旧的build-number。[Codemagic版本文档](https://docs.codemagic.io/knowledge-codemagic/build-versioning/)。保留Workflow Editor是受支持的方式，不要求新增YAML。[官方构建文档](https://docs.codemagic.io/flutter-configuration/flutter-projects/)。

本机验证SDK为Flutter 3.38.9 / Dart 3.10.8，未升级依赖或锁文件。可在Codemagic固定相同Flutter版本；若沿用网页的stable，实际SDK可能不同，必须查看构建日志。当前网页配置未登录核查，不声称已远程更新。

仓库Xcode deployment target仍为13.0，Info.plist版本取FLUTTER_BUILD_NAME/NUMBER，未改target。之前成功日志的实际target为15.0，且日志显示Flutter自动升级工程；不能把当前源码13.0当成新包仍支持iOS13的证明。仓库没有Podfile/Podfile.lock，本轮没有添加；之前成功构建在Mac侧生成并安装pods，本次仍须由Codemagic验证。Windows无法验证Swift编译、签名与SDK生成行为，不更改证书来绕过问题。

用户启动前还需检查Default Workflow的自动触发和Publishing：若只想先拿IPA，请在网页自行关闭自动发布；如果选择构建后上传，仍由用户主动执行。不要在Flutter dart-define中放入DeepSeek/JWT/MAC密钥。

## 待批准的最小客户端提交清单

以下包含此前未提交的正式接线，不将它们全部算作本轮新增。完整文件提交清单：

```text
.github/workflows/ios-unsigned.yml
ios/Runner/AppDelegate.swift
lib/app.dart
lib/providers/book_recap_controller.dart
lib/screens/xiaou/book_recap_screen.dart
lib/screens/xiaou/xiaou_home_screen.dart
lib/screens/xiaou/recap_pilot_entry.dart
lib/services/book_recap_client_api.dart
lib/services/book_recap_client_contract.dart
test/screens/book_recap_screen_test.dart
test/screens/recap_pilot_entry_test.dart
test/services/book_recap_client_test.dart
tool/reliable_upload_tests/test/recap_pilot_entry_test.dart
docs/zhidu-xiaou-recap-codemagic-readiness.md
```

部分文件：`pubspec.yaml` **只提交version行**，不整文件加入暂存。另行批准的历史安全处理：停止跟踪 `backend/.env`（保留本机文件；不展示删除diff中的旧值）。提交前必须复核实际暂存内容，不能使用 `git add .` 或 `git add -A`。

明确排除：

- 所有图标/无关图片、Android颜色、web manifest、macOS图标、桌面生成插件文件。
- `backend/node_modules`（历史已有818个被跟踪文件，本轮不清理、不收进新提交）。
- `backend/ops/recap-pilot/**`、`artifacts/**`、备份、运维记录、凭证、临时PG/SQLite文件。
- 本轮未改动的后端发布接线与011/012候选迁移等累积成果，保留在工作区。生产代码已由独立受审流程部署，不需要为构建IPA再次更新后端。它们的源码归档提交另审，不能把本次客户端提交当作完整生产版本归档。
- 本机HTTP联调工具及其他历史未提交测试目录保留，不把测试服务带入正式构建。

本轮14个代码/测试候选文件检查未发现私钥头、常见长API Key及JWT字面量；人工核对没有密钥文件或运维脚本纳入清单。模式扫描不是仓库历史无秘密的证明。Flutter assets只引用assets及字体目录，不包含backend或ops。暂存区为空，未执行提交或推送。

## 有限真实模型验收：仅离线准备

新增本地运维模块和离线测试，**不在客户端提交清单内，不部署**：

- `backend/ops/recap-pilot/finite-model-validation.js`
- `backend/ops/recap-pilot/finite-model-validation.test.js`

复用B1原始合成材料、prepareGeneration、prepareFollowUp及正式结果/引用验证器。模块不查找密钥、不读.env、不连接数据库、不监听HTTP，直接执行只输出“需要单独批准”，没有可立即消费余额的CLI。

固定最多2次：一轮生成，只有结构与证据合法后才做一次追问；每次0.08元、批次0.16元上限，75秒超时，无重试。固定材料/模型/限额/过期时间的计划摘要必须与审批摘要一致。独占创建并fsync的永久execution.lock在请求前预留整个批次额度，异常和崩溃不退款、不解锁、不续跑；每次请求前还保存单次预留。输出和用量仅写入受限批次目录，不向普通日志打印Prompt或回答；缺失usage为未知，按最高费率计算的费用不是供应商实际账单。

当前只有依赖注入的离线执行核心。真正运行前仍须审查Linux root-only host：确保所有父目录、属主与ACL安全；绑定唯一审批批次，不能换目录重获额度；读取现有Key仅放内存；绑定固定DeepSeek HTTPS transport、关闭状态验证及当前价格有效期。这个host尚未编写/批准，不能把调用方传来的verifyClosed=true视为生产证明。Windows临时测试权限不代表Linux生产ACL已验证。

本轮没有生成正式批准批次。测试的2030年到期时间只是合成时钟测试，不是生产费率延期；已有正式费率11月11日到期策略未改变。正式API、模型开关继续关闭；该任务也不验证真实用户resolver、落库和iPhone流程。

## 验证记录

完整日志保留在 `artifacts/recap-codemagic-review-20261105/`，禁止提交原始日志目录。

- 修改前Flutter隔离harness：355通过、0失败、2既有跳过。
- 新增入口6项：全部通过。首次测试编译因测试误await void失败；第二次测试因debug平台变量和跨用例原生流清理失败；修正测试生命周期后6/6通过。没有修改断言来隐藏失败，各轮日志保留。
- 改后第一次Flutter全集：360通过、1失败、2既有跳过。失败为原有截图用例 `render actual synthetic reading flow at phone and small viewport sizes` 10分钟超时，不冒充全绿。
- 受影响8个Dart文件静态检查：最终0问题；初次新增代码有2条花括号lint，已修复。
- 后端离线：234通过、0失败、0跳过。
- 全新合成PostgreSQL：192通过、0失败、0跳过；已停止并保留新测试数据目录，不接触业务库。
- 本轮真实loopback HTTP：20通过、0失败、0跳过，271次HTTP请求，20次模拟模型调用，真实费用0。HTTP和PG已停止；证据目录 `artifacts/book-recap-local-http/1793841937735-fb38152a/`。
- 有限模型执行核心离线测试：11通过、0失败、0跳过，包含独占并发、重复批次、崩溃预留、超时、断流、非法输出、版本/预算修改及关闭状态变化。没有真实网络调用。

串行Flutter全集复核：`flutter test --no-pub --concurrency=1 --timeout=2m --reporter json`，361通过、0失败、2既有跳过，210秒完成。没有排除截图用例，没有降低断言；前一轮并行截图10分钟超时原因尚未完全定位，不能只引用最后一次成功。

两项既有跳过分别为 evidence mode拒绝队列写入/业务初始化，以及evidence启动、前台、计时器、导出分享对DB/WAL及账号不变性场景；它们依赖独立的诊断构建条件，本轮没有新增跳过。未验证：iPhone NWPathMonitor、Swift/Xcode签名编译、Codemagic当前网页设置、真实模型结构化输出、付费账单与真实账号端到端。既有book_removal Mock问题在本轮基线和两次复测中均未报错，未修改上传业务，也不能因此宣称根治。

复跑入口：

```powershell
# Flutter SQLite仅使用既有隔离harness；不改主工程SQLite配置。
cd tool/reliable_upload_tests
flutter test --no-pub --concurrency=1 --timeout=2m --reporter json
# 在仓库根目录：仅离线合成模型测试。
node --test backend/ops/recap-pilot/finite-model-validation.test.js
```

HTTP与PG沿用 `backend/test-support/runRecapSynthetic.js`，二进制路径为本机已有的Temp PostgreSQL工具；每次新建随机数据目录，最终停止，不接受业务DATABASE_URL。完整命令及结果保留本轮日志；不是新建预发布服务器。

## 下一步

1. 审阅最小文件清单、版本14及历史.env停止跟踪方案，批准后再暂存、重新扫描暂存内容、commit/push。
2. 用户在Codemagic选择上述分支最新commit、Default Workflow及1.0.0(14)，检查旧build参数、HTTPS地址、签名和Publishing后自行构建/上传。
3. 正式开关仍关闭，新包不会因安装而开放回望；真实模型限次验收与最终开放仍需独立批准。不要用全账号开闸冒充有限测试。

## 提交授权补记（2026-11-05）

负责人已批准按上述最小清单提交推送，并停止跟踪backend/.env、保留本机文件。本次只提交pubspec的1.0.0+14版本行，不包含原有图标配置。此前“等待批准”及“暂存区为空”记录描述审查完成时的状态。

本次授权不包含IPA构建或上传，不使用其他CI。IPA尚未构建，仍由负责人在Codemagic选择新提交及Default Workflow主动执行。移除.env不会清除历史，凭证是否有效及是否需要轮换仍须独立处理。
