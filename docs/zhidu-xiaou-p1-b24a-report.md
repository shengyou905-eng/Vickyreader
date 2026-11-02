# 知读小U P1-B2.4a：Flutter同步、安全与授权协议

日期：2026-10-27。交付层级：关闭入口下的客户端基础实现与模拟验证，不是正式联调、页面完成或上线批准。

## 1. 结论与实际范围

本轮新增账号/会话/书籍绑定的Flutter控制器、严格DTO、只读SQLite来源检查、可注入HTTP传输及回归测试。支持现有未挂载adapter的prepare、范围确认、generate、GET、save、follow-ups、feedback、cancel、delete及原request ID显式重放。

没有接入app.dart、正式页面、Provider启动树或生产服务。HTTP客户端默认enabled=false，不内置生产回望地址，不自动获取凭证；只有显式构造的合成测试启用。原后端adapter仍未挂载，关闭router与功能开关未改变。

本轮没有修改任何既有文件。没有修改schema、迁移、模型Prompt、原五种免费模式、普通小U会话、Reliable Upload、IAP、Pro、Obsidian、明台、随心记。没有真实数据库连接、付费模型请求、真实账号/凭证访问、发布构建、部署、commit、push或备份清理。

**边界：客户端可以检测本机已记录的pending/删除、阻止迟到展示，但不能证明另一设备没有未同步变更。现有服务端缺少来源恢复、独立证据读取与展示失效协议；本轮不通过虚构端点补齐，不声称已具备正式产品验收条件。**

## 2. 实际新增文件

路径相对于项目根目录；全部为本轮新增。

| 文件 | 职责 |
| --- | --- |
| lib/services/book_recap_client_contract.dart | ID/revision/覆盖范围/结果/追问结构校验，来源选择、无正文header、客户端状态与安全中文错误 |
| lib/services/book_recap_local_guard.dart | 显式注入Database，单事务只读来源、pending、tombstone与追问；本机指纹及云端实际选择校对 |
| lib/services/book_recap_client_api.dart | 默认关闭的HTTP客户端；显式baseUri/token/clientFactory，有限响应、超时、中止、拒绝重定向、零自动重试 |
| lib/providers/book_recap_controller.dart | ChangeNotifier控制器；会话绑定、确认、操作序列、精确重放、取消/删除、临时正文撤回 |
| test/services/book_recap_client_test.dart | 43个新增合成SQLite、模拟HTTP、真实loopback HTTP和跨语言契约测试 |
| tool/reliable_upload_tests/test/book_recap_client_test.dart | 复用系统SQLite harness的测试入口 |
| docs/zhidu-xiaou-p1-b24a-report.md | 本报告 |

开工对lib、backend/src、backend/test-support、docs、test、tool中349个既有文件记录SHA-256，排除node_modules/.dart_tool/build/.git；收尾核对349个均未改变、无缺失。本轮不把原有Git dirty的96个tracked文件冒认成本轮修改。该核对不是新建完整可恢复备份；没有覆盖或删除此前备份。Dart自动格式化和lint修正仅作用于上表新Dart文件。

## 3. 与实际服务端契约的对照

以下路径均相对于显式注入的测试adapter baseUri，**不是已经部署的生产端点**。

| 客户端操作 | 实际请求与处理 |
| --- | --- |
| prepare(selection) | POST /prepare；只发recap_id、request_id、book_id、selected_sources，不发原文、userId、结果或provenance |
| confirmScope | 再GET /:id，核对调用方明确确认的revision/source fingerprint；同时重新核对本机资料 |
| generate | POST /:id/generate，使用已确认的revision和两个相同范围指纹；未确认拒绝 |
| refresh / readForDisplay | GET /:id；前者只留无正文header，后者返回可撤销临时正文对象 |
| save | POST /:id/save；显式请求ID及expected_revision |
| followUp | POST /:id/follow-ups；问题、可选item_id、request_id、expected_revision |
| followUpsForDisplay | 先GET回望，再GET /:id/follow-ups；两份响应必须同revision/源指纹/覆盖范围；只接收完整有序问答 |
| feedback | POST /:id/feedback；inaccurate/low_value/wrong_relation及可选私有comment，不发额外原文 |
| cancel | POST /:id/operations/:requestId/cancel，空对象；同时撤回本机等待及正文 |
| delete | DELETE /:id，空对象；不读取或修改原始记录 |
| replay | 重新POST同一路径、同request ID、同序列化请求体；不虚构GET operation端点，不自动重试 |

状态严格区分：服务器回望state是prepared/generating/ready/failed/cancelled；operation的running不是回望state；saved只读取is_saved。stale/invalidated在当前HTTP契约里主要通过409 RECAP_SOURCE_CHANGED或410 RECAP_UNAVAILABLE表达，映射为客户端状态，不假装服务端返回这些正文对象。412要求重新读取/确认，不能自动用新revision重发旧意图。

response必须包含selected_cloud_records_only、server_selected_records、fullBook=false、local_pending_verified=false。未知枚举/额外字段、错误书籍/回望ID、倒退revision、换源指纹、错误结果指纹、半组问答、普通聊天DTO均拒绝。

结果按B1结构防御性校验知识、关系端点、思考/问题、basis、引用和引文voice；不改变B1。客户端没有收到完整可信证据文本，**不能独立证明引文逐字准确或论断成立**，仍以服务器B1/resolver验证为基础。返回的结构不是重新获得可信provenance的途径。

## 4. 本机pending与来源范围

BookRecapLocalGuard只读已经由调用方提供的Database，不调用DatabaseService.database，不初始化真实数据库，不调用getUserEntryFollowUps（该旧方法可能上传/写缓存）。没有新增第二套历史表。

复用当前SQLite表、uploadStateHash删除标记、XiaouTraceSnapshot的metadata解析；不直接使用其远端缓存合并作为“已同步证明”，因为回望准备需要更严格的明确身份与pending拒绝。

检查流程：

1. 固定userId+sessionEpoch+origin+bookId，只按明确本地trace ID读取所属行。
2. 要求bmob_id为可用远端UUID；缺失、不合法、同账号别名冲突、其他bookId/owner直接拒绝。不按书名、文本、metadata.local_id或时间猜配。
3. 检查pending_upload_operations的trace操作，以及upload_entity_revisions的保留删除hash。任一待修改/待删除阻止整个选区，不悄悄只发其余资料。
4. 检查locally_deleted_books；普通书架移除和本地文件缺失不等于永久删书。模块不打开图书文件，也不要求书架行存在。
5. 追问只读同owner及所选父的本地/远端别名。remote_synced!=1、缺remote_id、未知归属追问、冲突的同remote ID内容均拒绝；不删除、自动认领或上传。
6. 随心记来源标记，包括嵌套授权标记，拒绝；不查询free_notes、ai_messages、普通conversation。
7. 本机指纹包含所属原行、版本围栏、完整本地追问集合及选择方式，覆盖内容和元数据改变，不只看updated_at。它只是本机变化检测，不作为服务端expected_digest发送，也不是真实性证明。

全部追问、省略；空选择，[]；部分选择，明确UUID数组。服务端返回的实际trace必须与本机选择一一对应，显式空/子集必须完全相符。全部追问可包含其他设备已同步到云端的新追问，但不能漏掉本机已确认的追问ID，且生成前仍须用户确认实际范围。header暴露解析后的来源ID与覆盖数量供后续范围页使用。

保守边界：即便用户选空追问，只要该父记录存在本机未同步追问，也先阻止云端操作。来源或父集合发生变化后必须重新prepare，不静默缩减材料。B1本机草稿模块继续保留，本轮未开发草稿UI或暗中保存云端。

跨设备：已存在合法本机映射的同账号资料可使用；只有远端回望ID、但本机没有相应trace映射时，当前实现拒绝。后续应由受授权的来源恢复接口与现有下载同步协作补齐，不能为了查看回望自动上传整个历史。

本机检查每次在SQLite事务内完成；HTTP在事务外执行，返回后再次读取并比较。没有持有SQLite锁等网络。服务器local_pending_verified=false被视作“必须执行本机检查”，绝不当作已同步许可。

## 5. 会话、缓存与展示撤回

控制器构造时捕获现有AuthSessionScope，绑定userId/epoch/origin/bookId；复用现有账号和token变更通知。请求前、数据库读取后、HTTP返回后、状态更新及正文序列化时均校验。A→B→A不会恢复旧控制器。切换会撤回正文、清除header/选择/重放请求并中止等待；不修改认证代码。

RecapHeader不含结果/问答正文，可用作占位；BookRecapController不写SharedPreferences、磁盘缓存、普通AI历史或普通聊天接口。内存最多保留一个临时RecapOnlineContent和一个重放命令，不累积无界回望缓存。

每次readForDisplay需要新的成功在线GET，再做本机检查，才签发**本机临时展示对象**。toJson仍检查会话、操作代次、在线标记和有效期。下一次操作、本地变更通知、退出、断网通知、suspend、dispose或期限结束均清除对象内部正文；旧对象不能再次序列化。已复制到外部UI的Map无法被Dart自动抹除，后续页面必须订阅通知并清除自己的渲染状态，不得另存正文副本。

displayLifetime为构造器必填参数，**没有生产默认值**。测试使用30秒或2秒，仅为合成策略；不是批准的产品政策，不是Apple或服务器签发的许可，也不是定时轮询周期。Timer只负责到期撤回并要求重新确认，不发HTTP。离线重新打开只能留下无正文header/提示。

**接入前提**：现有阅读写入没有统一Listenable。本轮要求调用方显式传入localChanges，提供invalidateSources/suspend/setOnline等边界，但没有顺手重构BookService、同步队列或页面生命周期。真实入口开放前必须接入所有相关已提交编辑、删除、追问集合变化、同步落库及网络/前后台事件。未接入通知时，只能在下一次只读复核或展示到期时检测/遮蔽，不能宣称任意SQL写入立即撤回。

远端另一设备删除在已返回GET之后发生时，客户端也不能凭本机Timer立即知晓。后续需明确服务器展示失效/刷新协议及允许窗口；当前临时对象只是客户端防无限缓存基础，**不是跨设备删除即时性的完成证明**。

## 6. 重放、取消与并发

- 每个主动新操作使用新UUID，不按原文或问题去重。同一控制器只允许一项普通请求，save/追问不会在客户端互相覆盖。
- 一次失败不自动重发。网络/超时/坏响应等结果不确定时，阻止新写入意图，引导显式重放原命令；重放保留原expected_revision/问题/请求ID，不能变成第二次模型调用。
- 重放只保留当前会话内最后一个命令，有可配置的一小时测试默认有效期；超过期限不再发送。最多一个有界问题/反馈体，退出和dispose清除。不承诺跨进程/重装恢复请求：没有未经审批新增持久化命令队列。
- 取消独立于普通请求锁，先撤回本机展示/等待，再发送真实cancel。服务端已经完成时的冲突不伪装成取消成功；离线取消只表示本机停止，不能保证供应商没有收到请求或扣费。
- HTTP使用每请求独立client，超时或取消finally关闭；不关闭现有AppHttp全局连接。旧Future返回不能越过操作epoch。
- 删除不依赖本机来源仍存在，也不以AI consent为前提。删除请求发起后本控制器阻止旧正文再打开；离线/失败不宣称服务器已删除，可重试DELETE。没有跨重启离线删除队列，后续必须明确恢复和提示策略。
- 其他设备造成412、来源变化或revocation时撤回展示，等待重新确认，不盲目将旧问题改绑到新source fingerprint。

安全中文提示只反映登录变化、尚未同步、来源已变、资料不足、预算达到、网络异常等；不展示SQL、HMAC、内部指纹、供应商正文或技术堆栈。UI仍需使用message而不是直接展示调试DTO。

## 7. 本轮实际测试

| 测试组 | 实际总数 | 通过 | 失败 | 跳过 |
| --- | ---: | ---: | ---: | ---: |
| 修改前Flutter系统SQLite基线 | 136 | 134 | 0 | 2既有 |
| 最终Flutter完整harness | 179 | 177 | 0 | 2既有 |
| 其中本轮新增客户端测试 | 43 | 43 | 0 | 0 |
| 后端非PostgreSQL回归 | 228 | 228 | 0 | 0 |

新增测试包括：混合pending/缺远端ID、保留tombstone、永久删除、缺本地文件、A/B同bookId、别名冲突、独立同文历史、全/空/子集追问、未知归属与未上传追问、随心记排除、内容无时间戳变更、默认关闭、完整请求流程、saved属性、非法覆盖及JSON、14组问答及普通聊天拒绝、A→B→A迟到、GET期间本机编辑、离线撤回、变更通知、会话变化及428授权撤销、409/410/412、token变更、保存/追问并发、丢响应重放、取消迟到、防旧正文重开、origin不匹配、展示期限、坏/超大HTTP正文、重放过期以及全部追问不得漏掉已同步身份。

实际loopback HttpServer测试经过真正http.Client，覆盖成功、302不跟随、超时、主动abort，计数4次且无自动重试；其他业务场景用MockClient加真实SQLite核心判断。无公网模型流量，匿名合成材料没有真实用户内容。

Dart到Node测试将本次控制器实际生成的7类变更请求体交给当前bookRecapHttpContract/Zod校验，并校验服务端响应fixture；只加载纯契约，不连接PostgreSQL。这能防止两端各写一套自洽但互不兼容的请求，**不等同于真实JWT+数据库+Flutter端到端联调**。

只读检查比较total_changes、原记录和队列，确保guard本身不写入。合成SQLite由现有openForTesting在新系统临时目录创建；各测试只清理自己刚创建且经过路径校验的合成目录。不打开真实SQLite，不删除备份。

开发中出现两次新增测试问题：HttpOverrides的null参数不符合当前Dart签名，以及契约测试在feedback替换最后命令后仍尝试cancel。前者改用独立HttpOverrides实例，后者将取消放在追问命令之后；未改变业务校验、旧断言或评测标准。最终43项全部通过。

Dart针对本轮五个源码/测试文件分析：No issues found。git diff --check返回0，既有CRLF提示仍在。已有SQLite factory、widget hit-test警告、2项跳过及故障注入SQL日志未改；根工程SQLite asset-loading和既有BuildContext问题未顺手修复，不宣称已经解决。

本轮未重跑PostgreSQL集成套件，因为未修改后端或DDL；B233的164场景/165项是上一阶段结果，不列为本轮通过数。未做真实模型、Apple、真机、生产服务和发布构建验收。

### 可复跑方式

从tool/reliable_upload_tests目录：

```powershell
flutter test --no-pub test/book_recap_client_test.dart --reporter expanded
flutter test --no-pub --reporter compact
```

从仓库根目录：

```powershell
dart analyze lib/services/book_recap_client_contract.dart lib/services/book_recap_local_guard.dart lib/services/book_recap_client_api.dart lib/providers/book_recap_controller.dart test/services/book_recap_client_test.dart
```

从backend目录（排除依赖数据库的套件）：

```powershell
$tests = @(Get-ChildItem src -Recurse -Filter '*.test.js' | Where-Object { $_.Name -notlike '*.postgres.test.js' } | ForEach-Object { $_.FullName })
node --test @tests
```

## 8. B2.4b前置接口与接入事项

1. **账号私有历史列表/恢复入口**：现有adapter没有list。需要最小分页无正文列表及删除/失效状态，不能调用普通小U对话列表代替。路径/字段待审批，当前没有虚构调用。
2. **证据读取和映射恢复**：GET现仅给远端entry/follow-up ID、覆盖与结果，没有evidenceId到可展示片段/定位的独立DTO，也没有跨设备本机缺记录时的受控恢复流程。需要基于现有resolver的所属/版本复核、字段白名单和隐私范围，不上传完整图书。
3. **展示有效性协议**：现有no-store和GET复核不等于长期许可。需确定低成本的失效通知/再验证方式、租期上限、并发删除语义及断网遮蔽策略，不能把测试30秒或旧建议15秒当作生产政策。
4. **调用成本**：当前每次正文读取1次GET；追问历史读取2次GET以校对revision；范围确认1次GET；generate/followUp成功后1次GET。没有定时请求。每个普通操作本机约2–3次只读事务，guard按所选trace逐项查询；上限80条，尚未做真实设备p95/大数据基准。后续可先批量化纯查询，但不得跳过删除/pending保护。
5. **本机写入与生命周期适配**：将阅读编辑/删除/新增追问及同步落库接到localChanges；页面离开、App后台、网络和consent事件撤回渲染内容。API tokenProvider必须取现有AuthService当前token并配合AuthSessionScope，不能另建认证系统。
6. **本机和云端内容版本确认**：当前本机fingerprint只能检测本机前后变化，不等于服务端source_digest。已确认远端身份且队列为空也不能证明另一设备内容没有变化，或一段绕过现有写入机制的本机编辑已被正确同步。后续需要与受授权来源版本响应建立可比较的确认依据；不能把客户端hash当作真实性证明。
7. **失败恢复**：跨进程重放、未完成命令恢复、离线删除意图恢复需单独明确最小无正文元数据或受保护的私有存储方案。本阶段仅会话内重放，不新增SQLite表或无限重试。
8. **接入流程**：先补接口/通知契约和合成验证，再组合页面。现有关闭adapter未来怎样挂载、真实认证联调、服务端限流、展示策略以及任何部署/付费模型调用仍须单独批准。

P1完整产品目标保留：知识整理、我的思考、可选继续思考、证据、专属追问、保存、历史、删除和反馈。轻提示、跨书、思考轨迹和思维导图不在本轮。当前交付不以UI可见作为完成依据。

本轮停在B2.4a，等待审核，不自动开始B2.4b。
