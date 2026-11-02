# Zhidu Pro: Phase 0 审查与实施边界

日期：2026-10-02。状态：审查完成，订阅功能尚未实现。

本次按要求先执行 Phase 0，没有修改业务代码、安装订阅依赖、运行数据库 migration、构建 IPA、提交、推送或部署。本文中的新表、API、环境变量和文件均为后续实施方案，不是已经交付的功能。

## 1. 审查基准

- HEAD：`caf7dd675322153bc1ee3c09747619510151d08d`。
- 工作区已有大量未提交修改，包括 App 图标、小U错误处理、Obsidian 后端及插件；本次审查的是这些改动在内的当前工作区，不是仅 HEAD。
- App 版本：`pubspec.yaml:4` 为 `1.0.0+12`。
- 本机 Flutter 3.38.9 / Dart 3.10.8；项目 Dart constraint 为 `^3.10.8`。
- 本机 Node v24.15.0；后端声明 Node `>=20`。
- 本机为 Windows，不能在此完成 Xcode 编译、签名或真实 StoreKit/TestFlight 验收。

## 2. 已核实的架构

| 项目 | 当前实现与证据 |
| --- | --- |
| Bundle ID | `com.youxugarden.zhireader`；`ios/Runner.xcodeproj/project.pbxproj:387,567,590` |
| iOS 最低版本 | 13.0；上述文件 `:364,491,542` |
| Flutter 状态管理 | Provider + ChangeNotifier；`lib/app.dart:38` 起注册 Auth/Bookshelf/Reader/AI/Settings Provider |
| App API origin | `lib/config/constants.dart:12`，编译期 `String.fromEnvironment('API_BASE_URL')`，缺省为 `https://api.youxugarden.com`，release 要求 HTTPS |
| 本地数据 | SQLite 17，`lib/config/constants.dart:44`；业务表、user_entries、reading progress、revision/writer 和 pending queue 已存在 |
| 客户端认证 | AuthProvider -> AuthService -> BmobApi；BmobApi 名称是历史命名，实际调用现有知读后端 |
| 服务端认证 | `backend/src/middleware/auth.js` 校验 JWT、数据库用户状态、token_version；不能将客户端本地 token 非空当作会员凭据 |
| Apple 登录 | 已有 Sign in with Apple；不是 IAP 验证，不复用其密钥配置冒充 App Store Server API credentials |
| 后端 | Node/CommonJS、Express 4、pg、PostgreSQL、zod；routes/controllers/services/repositories 分层 |
| 数据库事务 | `backend/src/config/db.js:12` 的 withTransaction，BEGIN/COMMIT/ROLLBACK |
| Migration | `backend/src/db/migrations/001...007` 版本化 SQL；无自动版本登记 runner；001 有 down，后续大多只有 up |
| Schema 初始化 | `backend/src/db/schema.sql`；`src/server.js:7` 非生产启动初始化，生产显式升级 |
| 阅读同步 | ReliableUploadService + 持久化 pending/revision/generation；`sync_changes.user_sequence` 为阅读数据增量账本 |
| Obsidian | 独立 PKCE S256、grant、snapshot/cursor、只读 Sync API；不得因订阅新增而更改协议 |
| MCP | 独立令牌和只读工具，不应被 Apple IAP 验证逻辑替代 |
| 法律页面 | 已有隐私、AI、账号删除等页面；未发现完整订阅服务条款入口 |
| 当前订阅 | 未发现 IAP 依赖、正式 subscription/entitlement 表或 Pro 购买功能 |

现有只读取证模式在 `lib/app.dart:28` 提前返回。将来的订阅监听器、会员 refresh、购买恢复不得在该模式下初始化，以保持 DB/WAL 和 pending metadata 不变。

### 现有权益候选，不虚构产品能力

- 已有阅读、书架、划线/想法、小U解读/提问、阅读痕迹及进度同步、Obsidian 只读同步。
- 小U已有 insight 缓存；`insight.repository.js:143` 将 deepReflection 设为 activeDiscovery，不等于已完成独立的收费“深度回望”。
- 未发现完整思维导图、Knowledge Object 高级模块或独立 Pro 能力模型。
- 本轮不把既有用户同步突然改为收费，不修改现有 API 权限。先交付购买与服务器权益闭环。
- 上架前必须明确至少一项真实可使用的 Pro 权益、免费/付费边界及老用户策略；不能仅销售未来功能或会员标记。

## 3. 商品与兼容性

建议在 App Store Connect 创建同一 Subscription Group：`Zhidu Pro`，中文本地化“知读 Pro”。月付和年付授予同一 `pro` 权益等级。

| 周期 | Product ID | 定价配置 |
| --- | --- | --- |
| 月付 | `com.youxugarden.zhireader.pro.monthly` | 在 App Store Connect 设置目标价格 ¥18/月 |
| 年付 | `com.youxugarden.zhireader.pro.yearly` | 在 App Store Connect 设置目标价格 ¥128/年 |

Flutter 只显示 StoreKit 商品的 localized display price（插件为 `ProductDetails.price`），年付月均价用 rawPrice/12 和货币元数据计算。不会把上述人民币金额写入 UI。

依赖候选：`in_app_purchase 3.2.4` 与 `in_app_purchase_storekit 0.4.13`。已检查其发布元数据要求 Dart ^3.10.0、Flutter >=3.38.0，与当前 SDK 匹配；尚未安装或完成 iOS 构建验证。当前上游 3.3.1 要求更高 SDK，不能直接升级到 latest。

StoreKit 2 需要 iOS 15+。最小侵入方案是保留现有 iOS 13/14 阅读支持，旧系统不初始化 SK2 购买入口并明确提示系统要求；不暗中切换 StoreKit 1，也不擅自抬高整个 App 最低系统版本。实际能力检查与插件精确版本源码将在 Phase 3 验证。

## 4. 后端权益与归属设计

### 数据结构（拟新增 migration 008）

- `subscription_accounts`：当前 user 与服务器生成的稳定 UUID appAccountToken 的映射。
- `subscriptions`：provider、environment、product_id、original/latest_transaction_id、owner、status、purchase/expiry/grace/revocation、autoRenew、Apple signedDate、last_verified_at、timestamps。
- `entitlement_grants`：通用 `pro`、来源 `apple_app_store`、订阅引用、有效期和撤销状态。业务只读取权益，不判断 Apple productId。
- `subscription_events`：notificationUUID、type/subtype、environment、original_transaction_id、received/processed、处理结果及安全错误码；记录重复、归属冲突、未知订阅待对账等状态。

核心唯一约束：`(provider, environment, original_transaction_id)`；notificationUUID 幂等键；appAccountToken 唯一；entitlement grant 对来源订阅唯一。为 user/effective expiry、待处理事件、订阅链建立索引和明确外键。

`FREE/PRO` 是当前有效 entitlement 的结果，不能靠一个永远为 true 的用户字段。真实到期由服务器时间及 Apple 已验证 paid/grace deadline 判断，不依赖用户再次打开 App 或某个 webhook 必达。通知、订阅记录与权益变化必须在同一业务事务提交；Apple 请求不放进长时间持有行锁的事务。

### 账号绑定与删除

- 购买前由后端签发属于当前用户的稳定 appAccountToken，交给 SK2；验证已签名 transaction 的 token，不能只凭任意 transaction ID“先到先得”。
- original_transaction_id 一旦属于其他账号，返回明确业务错误，不静默迁移；同账号换设备/重装/restore 不改变归属。
- `user.repository.js:82` 当前硬删除账号。订阅链不能随 `ON DELETE CASCADE` 消失，否则删除后重注册可能重新认领交易。
- 拟采用用户外键 SET NULL、保留最小必要的交易归属占用记录，拒绝自动绑定新账号；保存期限、隐私披露及人工恢复政策需单独确定，不保留无关阅读或登录数据。

### Apple 验证与时序

- 使用 Apple 官方 Node `@apple/app-store-server-library`，通过 SignedDataVerifier 验证证书链、签名、Bundle/environment/appAppleId，以及通知内嵌 transaction/renewalInfo。
- 可信根使用 Apple 官方公开 CA；私钥只在服务器环境，不进入客户端、日志或 Git。
- 对允许商品、auto-renewable 类型、归属、环境再次校验，拒绝未知商品和不受支持的家庭共享归属。
- notificationUUID 去重；不能按 HTTP 到达顺序直接覆盖状态。按订阅链序列化协调，结合 Apple 当前 subscription status 与已验证版本防止旧事件覆盖新事件。
- refund 针对具体交易处理，不能用旧周期退款直接误撤销后续仍有效的新周期；REFUND_REVERSED 等当前 Apple 生命周期也需纳入对账。
- 取消自动续费只改 autoRenew，paid period 内仍 PRO。grace 只按 Apple 验证的 deadline 授权；billing retry 不等于无限免费延长。
- 未绑定交易的早到通知需要持久化待对账，不可记“成功”后永久丢弃。失败不误授予，已有有效权益不因一次网络错误写为永久 FREE。
- 提供可重复执行的有限对账任务，处理通知丢失、Apple 暂不可用及后续恢复；不为本任务引入复杂消息平台。
- Sandbox 通知不会像 Production 一样自动重试，必须在验收和恢复方案中明确覆盖。

### 环境隔离

- 测试 backend + 测试 DB + Sandbox credentials/config 独立；禁止为了测试连接生产 DB。
- 所有 subscription/grant/event/query 都带可信 environment；不能接受客户端传入 environment 就改变生产授权范围。
- Sandbox 记录永不授予 Production entitlement，不进行“生产验证失败便默认接受 sandbox 并授予生产”的回退。
- TestFlight 用 Sandbox。App Review 也需要 Sandbox 购买路径：不能简单让正式 App 的 backend 拒绝所有 Sandbox 交易而导致审核无法购买。需配置受控审核账号/测试授权命名空间，不给普通生产账号发放正式权益。
- 真实 ASC 商品、数字 appAppleId、独立 key 和 reviewer/test 账号目前未验证，不能宣称上线可用。

## 5. 拟新增 API

| API | 用途 |
| --- | --- |
| `GET /api/me/entitlements` | JWT 用户的服务器有效权益与 freshness；复用统一 entitlement service |
| `POST /api/subscriptions/apple/purchase-context` | JWT 用户获取稳定 appAccountToken 和商品配置 |
| `POST /api/subscriptions/apple/verify` | 提交 transaction 线索，由服务器验证并绑定，不能信任客户端 expiry/isPro |
| `POST /api/apple/notifications` | 无 App JWT，但必须验证 Apple V2 签名；幂等处理 |

这些接口未创建，具体响应 envelope 将沿用现有 API 风格。Obsidian 独立授权令牌不得直接冒充 App JWT；以后服务端以已认证 grant 的 user_id 调用同一 entitlement service，插件不接触 Apple。

## 6. Flutter 最小接入

- SubscriptionService 封装 SK2、product query、purchaseStream、restore/finish，不让 UI 直接调用 StoreKit。
- SubscriptionRepository 封装认证请求、transaction 验证、会员 refresh。
- SubscriptionProvider 跟随 AuthProvider 切换用户，废弃过期异步响应，避免 A 用户结果污染 B 用户。
- 独立持久化待验证交易线索，不复用 reading pending queue，不改变 revision/generation。
- 购买成功但后端不可用：显示“购买已完成，正在确认会员状态”，防止重复付款；恢复后继续服务器验证。不能把本地 success 直接变成永久 PRO。
- StoreKit complete/finish 的时机围绕服务器验证及持久化处理结果，覆盖 App 被杀、未 finish 重投、验证成功但 finish 前崩溃。可恢复失败与终结拒绝分开处理，避免无限交易重投。
- 登录/启动查询会员，restore 用当前 Apple ID 的交易恢复同一知读账号；不能假设 secure cache 在重装后仍存在。
- 缓存按 user + API origin + environment 隔离；记录 verifiedAt/refreshAfter/validUntil。短暂 refresh 失败保留已验证且仍有效的权益，不无限越过 expiry/grace；超过有效边界显示待确认状态，不伪造新的有效期。
- 沿用设置页与主题，新增 Pro 页面，选择月/年、真实商品价格、pending/loading/cancel/error、恢复、官方管理订阅入口和法律链接。
- 不新增自动后台 Obsidian 同步、不改变阅读同步权限、不向取证 build 挂载订阅网络或监听器。

## 7. 拟修改文件

后端新增：

- `backend/src/db/migrations/008_app_store_subscriptions.up.sql` / `.down.sql`
- `backend/src/config/subscriptions.js`
- `backend/src/repositories/subscription.repository.js`
- `backend/src/services/appleSubscription.service.js`
- `backend/src/services/entitlement.service.js`
- `backend/src/controllers/subscriptions.controller.js`
- `backend/src/routes/subscriptions.routes.js`
- `backend/scripts/reconcile-subscriptions.js`
- 订阅策略、API、通知、签名失败、隔离及独立 PostgreSQL transaction/concurrency 测试

后端局部修改：`package.json` / lock、`.env.example`、`src/config/env.js`、`src/app.js`、`src/db/schema.sql`；必要的法律页面、账号删除审计测试。不会改 001-007 的历史 migration 或阅读 ledger。

Flutter 新增：

- `lib/config/subscription_config.dart`
- `lib/models/subscription_product.dart`
- `lib/models/subscription_entitlement.dart`
- `lib/repositories/subscription_repository.dart`
- `lib/services/subscription_service.dart`
- `lib/providers/subscription_provider.dart`
- `lib/screens/subscription/pro_screen.dart`
- 对应 service/provider/repository/paywall 测试

Flutter 局部修改：`pubspec.yaml` / lock、`lib/app.dart`、设置页、现有认证 API 的最小调用适配、zh/en ARB 与生成文件。只有插件实际需要时才改 iOS 项目配置；不升级 SQLite 17、不改阅读业务表。

文档：实现后新增部署、回滚、ASC 手工配置与 A-W TestFlight 验收矩阵，逐项注明操作、客户端、服务器、DB 和实际验证状态。

## 8. 拟新增服务器配置

尚未创建或读取真实密钥。建议独立前缀：

- `APP_STORE_BUNDLE_ID`
- `APP_STORE_APP_APPLE_ID`（ASC 数字 App ID，Production JWS 校验所需）
- `APP_STORE_ISSUER_ID`
- `APP_STORE_KEY_ID`
- `APP_STORE_PRIVATE_KEY`（服务器注入的 p8，禁止 Git/Flutter）
- `APP_STORE_ENVIRONMENT`（部署端控制，不信任请求参数）
- `APP_STORE_ROOT_CA_PATHS`（公开可信证书，不是私钥）
- 月/年商品配置集中于 subscriptions 配置模块，不散布在业务逻辑

是否增加审核账号 allowlist 配置由环境隔离实现决定，不创建用户可自选的 sandbox/pro 开关。客户端仅需要公开商品信息与 API origin，不需要任何 Apple Server API key/issuer/private key。

## 9. 修改前测试基线

以下均是在未修改订阅业务代码的当前工作区实跑。测试数量不可作为上线保证。

| 检查 | 结果 |
| --- | --- |
| Backend 全部非 `.postgres.test.js` 的 Node tests | 53 passed / 0 failed / 0 skipped，含 Apple 登录、MCP、Reliable Upload、Obsidian |
| `backend npm run check` | 通过 |
| `check:obsidian` / `check:reliable-upload` | 通过 |
| `check:legal` / `check:mingtai-parser` | 通过 |
| 根目录 `flutter test --no-pub --reporter expanded` | 64 passed，6 个测试文件加载失败，不能标为全绿 |
| Windows harness 全套 Flutter tests | 64 passed / 2 按模式 skip；不是与根目录完全互斥的额外 64 项 |
| harness 开启 `ENABLE_LOCAL_SYNC_DIAGNOSTICS=true` 的 mode tests | 3 passed / 1 正常模式测试 skip；DB/WAL 不变和禁止自动上传检查通过 |
| `flutter analyze --no-pub` | 1 条既有 info：`lib/services/share_service.dart:64:43`，use_build_context_synchronously，exit 1 |
| `plugins/zhidu-sync npm test` | 20 passed / 2 integration skipped |
| `plugins/zhidu-sync npm run typecheck` | 通过 |
| 真 PostgreSQL 集成/并发测试 | 未运行，本机 Docker Desktop engine 未启动 |
| iOS build / 真实 Apple 验证 / TestFlight | 未运行 |

根目录 SQLite 加载失败原因：项目 sqlite3 hook 使用 `source: process`，Windows 测试进程找不到 `sqlite3_initialize`。已有 `tool/reliable_upload_tests` 使用 Windows 系统 SQLite，可运行相关业务用例。本次不为消除基线失败而无关修改客户端 sqlite3 配置。harness 另有已有 widget tap warning，未被记作测试失败。

真实 PG 测试包含 `DROP SCHEMA public CASCADE`；Obsidian 测试还要求数据库名 `zhidu_obsidian_phase1_test`。不能针对用户当前人工验收库执行。后续需启动全新隔离 PostgreSQL 实例/端口，用同名的临时测试库运行这些用例，绝不复用或清空既有验收数据。

## 10. 下一阶段与上线条件

1. Phase 1：新增 008、归属与通用 entitlement 模型；先完成独立 PG 并发/约束/回滚测试。
2. Phase 2：官方 Apple verification、V2 通知、重复/乱序/失败恢复、环境隔离；拒绝伪签名。
3. Phase 3：精确锁定兼容插件、SK2 adapter、会员状态与交易恢复；Mac/Xcode 验证构建。
4. Phase 4：现有视觉体系的 paywall、Restore、Manage、法律链接与中英文状态。
5. Phase 5：小游手工配置 ASC，真实商品/TestFlight/Sandbox A-W 验收；不可用 mock 代替完成声明。
6. Phase 6：完整回归，对照本基线区分新增回归与既有环境问题；修复新增 regression。
7. Phase 7：输出真实部署顺序、rollback 限制、公开 HTTPS 通知、对账任务运行和 ASC 手工菜单清单。

当前尚无真实 Apple 凭据/商品/通知 URL 验证，未定义上线售卖权益，PostgreSQL 集成基线未跑，iOS 构建未跑。因此当前不具备“订阅已完成/可上线”的条件。

## 官方依据

- Flutter 兼容版本：[in_app_purchase 3.2.4](https://pub.dev/packages/in_app_purchase/versions/3.2.4)、[in_app_purchase_storekit 0.4.13](https://pub.dev/packages/in_app_purchase_storekit/versions/0.4.13)。
- [Flutter 官方 IAP 源码](https://github.com/flutter/packages/tree/main/packages/in_app_purchase)：SK2 默认路径、appAccountToken 映射、localized display price；实施时复核锁定版本，而非假定 main 与发布版完全相同。
- [Apple 官方 App Store Server Library for Node](https://github.com/apple/app-store-server-library-node)：Server API 和 SignedDataVerifier，公开根证书配置及 Production appAppleId 要求。
- [Apple notificationType](https://developer.apple.com/documentation/AppStoreServerNotifications/notificationType)：当前事件定义与续费/退款生命周期。
- [Apple subscription status](https://developer.apple.com/documentation/appstoreservernotifications/status)：active、expired、billing retry、grace、revoked。
- [Apple 通知响应与重试](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications)：Production 与 Sandbox 重试差异。
- [Apple appAccountToken](https://developer.apple.com/documentation/storekit/product/purchaseoption/appaccounttoken(_:))：应用账号与交易关联。
