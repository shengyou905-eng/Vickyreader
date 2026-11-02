# Zhidu Pro Phase 1: storage, ownership and entitlement foundation

日期：2026-10-03。范围：migration 008、内部持久化模型和测试。

没有接入 Apple verification、公开购买/通知 API、Flutter IAP、Paywall 或功能收费门槛。没有修改 iOS deployment target、SQLite schema、阅读同步、MCP 或 Obsidian 协议。没有提交、推送、构建或部署，也没有访问现有人工验收数据库或生产数据库。

## 1. 先澄清 iOS 13 / StoreKit 路径

本轮下载并检查了 pub.dev 的精确发布包，而不是根据最新 main 分支猜测：

- in_app_purchase **3.2.4**：依赖 in_app_purchase_storekit **^0.4.0**，本身并不唯一确定最终 StoreKit 实现版本。项目尚未安装 IAP，也没有相应锁定记录。
- 候选精确实现版本 **in_app_purchase_storekit 0.4.13**，包的 SHA256：
  `bb87b9003fd77da6f23f82c09b1891b28f7bf2520cfa1881a266a9601e675bf0`。
- 两个包分别要求 Dart ^3.10.0 / Flutter >=3.38.0，与当前 SDK 匹配；未进行 Mac/Xcode 构建。

精确发布包中的路径：

| 文件 | 实际行为 |
| --- | --- |
| in_app_purchase 3.2.4 / lib/in_app_purchase.dart:39 | 注册 StoreKit 实现，没有按系统版本自动选择 SK1 的逻辑 |
| storekit 0.4.13 / lib/src/in_app_purchase_storekit_platform.dart:34 | _useStoreKit2 默认 true |
| 同文件 :60、:71、:94 | registerPlatform / transaction stream / isAvailable 依据该标志走 SK2 |
| darwin/.../InAppPurchasePlugin.swift:61 | 只有 iOS >=15 才注册原生 SK2 API |
| 同文件 :417 | supportsStoreKit2 返回真实系统能力 |
| darwin/in_app_purchase_storekit.podspec:25 | 插件 deployment target 仍为 13.0；这不等于 SK2 支持 iOS 13 |

因此，**保持 App deployment target 为 13，不会让默认购买流程在 iOS 13/14 自动变成 StoreKit 1**：

- iOS 15+：默认 Dart / native 两端均为 StoreKit 2。
- iOS 13/14：该发布版默认 Dart 仍尝试 SK2，但原生 SK2 通道未注册；直接调用不能形成可用购买路径，可能出现 platform/channel error。存在 SK1 实现代码不代表自动回退。
- 该版本 enableStoreKit1 在 :353 的具体实现是 `_useStoreKit2 = !(await SKRequestMaker.supportsStoreKit2())`，不能凭方法名称将它视为可靠的旧系统自动回退方案。

后续 Phase 3 建议：锁定并验证精确版本，先查询系统能力；iOS 13/14 保留原有阅读、登录和服务器权益查询，但不初始化 SK2 stream/purchase/restore，提示升级系统以管理购买。iOS 15+ 使用 SK2。**本轮没有实现这一客户端 guard，更没有改 deployment target。**

此阶段不建议为了数据库工作提升最低版本。如之后改为 iOS 15，iOS 13/14 用户将无法安装或升级整个新版 App，而不只是不能购买；需评估存量设备、测试矩阵和 ASC/Xcode 设置后，由小游确认。

依据：[发布包 3.2.4](https://pub.dev/packages/in_app_purchase/versions/3.2.4)、[发布包 0.4.13](https://pub.dev/packages/in_app_purchase_storekit/versions/0.4.13)。

## 2. 已落地 schema

所有新表都明确存储 Apple environment，仅允许大小写精确的 Sandbox / Production，无默认环境。

| 表 | 主要字段与目的 |
| --- | --- |
| subscription_accounts | id、user_id、environment、app_account_token UUID、created_at；一个账号每个环境一个稳定 token |
| subscription_ownership | id、provider、environment、original_transaction_id、account_id、retired_at；永久占用交易链，禁止静默转移 |
| subscriptions | ownership_id、account_id、environment、product、latest transaction、status、purchase/expiry/grace/revocation、autoRenew、signed_at、snapshot_hash、verified/created/updated times |
| entitlement_grants | account_id、environment、entitlement=pro、source=apple_app_store、subscription_id、enabled、valid_from/until、revoked_at、verified_at |
| subscription_events | environment、event kind、request_hash、notificationUUID/type/subtype、ownership/account references、result、received/processed timestamps |

provider 与 original_transaction_id 集中存于 ownership，由 subscription 外键关联，避免复制多份归属真相。业务使用 entitlement service，不判断 monthly/yearly product ID。

### 约束和索引

- accounts：UNIQUE(user_id, environment)，app_account_token 全局唯一；身份字段禁止 UPDATE。
- ownership：UNIQUE(provider, environment, original_transaction_id)，归属禁止跨账号 UPDATE；已 retired 的链不可重新激活或 DELETE。
- subscriptions：ownership_id 唯一，UNIQUE(environment, latest_transaction_id)。
- grants：subscription_id 唯一；通过包含 account_id/environment 的复合外键绑定 subscription，拒绝跨用户或跨环境拼接。
- events：UNIQUE(environment, notification_uuid)，verification 类型不冒充有 notificationUUID 的 Apple 通知。
- status、environment、provider、entitlement、审计结果有 CHECK；时间先后、grace deadline、revocation 状态有 CHECK。
- 已添加账号关联、有效权益、last_verified_at 对账、待处理审计及 ownership 审计索引。
- events 没有 raw payload / JWS / receipt / token / email / 任意 JSON / 任意错误文本列。只保存有界元数据和内容摘要。

### 内部模型行为

`getOrCreateAccount(userId, environment)` 生成随机 UUID appAccountToken；同账号同环境并发调用也返回同一个 token。它不是登录令牌，不包含用户 email，也不等于 user UUID。

`applyVerifiedSnapshot(userId, state, notification?)` 是 **内部持久化边界，不是 Apple 验证函数**。当前没有任何 HTTP route 调用它。测试使用合成 DTO 检查业务/数据库判断，不代表真实交易已通过验签。

该函数会校验已归一化 DTO、商品 allowlist、account token 与环境/用户归属；订阅、权益、归属和成功审计同事务提交。失败审计可以独立于不发生的权益变化提交；中途数据库异常则全部回滚。

- 同版本同内容为 replay；更旧 signed_at 为 stale；同版本不同内容为 version_conflict。
- 同 notificationUUID 同内容为 duplicate，不重复写权益；内容冲突返回 event_conflict。
- 不同用户抢同一 chain 最多一方成功，另一方得到 ownership_conflict。
- 新 snapshot 更新当前状态；过期、取消续费、grace、billing retry、revocation 均有模型测试。
- 不能将 notification 到达时间当作 state 版本。Phase 2 必须在官方验签和 Apple current status 对账后构造该 DTO，尤其处理旧交易退款与通知/renewal 的不同 signedDate。**本阶段的版本栅栏不等于已经完成 Apple 乱序通知归一化。**

`getEntitlements(userId, environment)` 使用数据库时间检查 enabled、valid_from/until 和 revoked_at，合并有效 pro grant。无有效 grant 返回 FREE，否则 PRO；取消 autoRenew 不提前失效；多个 chain 中一个过期不会覆盖另一个有效 grant。数据库异常直接向调用层传播，不假装用户变成 FREE。

## 3. 账号删除后的精确行为

Apple appAccountToken 是官方的交易与应用账号关联机制，但不是独立的认证证明。必须由服务器给当前用户生成，再由 Phase 2 验证 Apple 签名 transaction 中的相同 token，不能信任客户端任意提交的 UUID。

现有 `user.repository.deleteUser` 仍使用原来的 DELETE FROM users，没有重构认证流程。数据库 CASCADE 到 subscription_accounts 时触发 erasure：

1. 删除对应 subscription_events（包括引用这些 ownership 的审计）。
2. 删除 subscriptions，以及关联 entitlement_grants。
3. 将 ownership.account_id 置空，设置 retired_at，保留禁止重新认领的链占用记录。
4. 删除 subscription_accounts，包括原 user_id -> appAccountToken 映射。
5. users 原有其他业务外键继续执行原有删除语义，不为订阅保留阅读数据。

这些操作和用户删除属于同一 PostgreSQL 事务。中途失败整个删除回滚；用户行锁与验证写入的锁顺序一致，防止并发删除后重新写入订阅。

### 删除后保留什么

仅 subscription_ownership 中的：

- 内部记录 id（用于引用，不是原 user UUID）；
- provider；
- Apple environment；
- original_transaction_id；
- account_id = NULL；
- retired_at（删除占用状态与保留审查时间依据）。

不保留旧 user_id、email、appAccountToken、购买明细、金额、产品、expiry、旧审计、JWT、Apple 登录凭据或阅读内容。

以后旧交易再次出现，即使请求方是相同 email 注册的新知读账号、或提供新账号 token，也不能认领已 retired 的 original_transaction_id。结果是 account_deleted；其他仍存在账号的链返回 ownership_conflict。同一未删除知读账号的重装/换设备/restore 不更换映射。

删除账号不会向 Apple 伪造“取消订阅”，Apple 的自动续费可能继续。订阅上线前，删除账号确认与法律页面必须准确说明管理/取消订阅入口，但不能强制用户先取消才能立即删除账号。本轮未改 UI。

### 最小化与合规边界

保留的 Apple 交易链标识仍属于可关联的假名化数据，**不是“完全匿名”**。技术目的仅为防止重复认领，不允许用来恢复旧账号或阅读数据。本轮不声称这种保留天然符合所有司法辖区的法律。

发布前需确定适用的保留依据、披露、访问限制和定期审查政策。当前不自动 GC 占用记录：删除占用会重新打开错误认领风险。如政策要求彻底清除此标识，必须同时设计仍然有效的拒绝恢复机制，再迁移，不能直接清表。没有为了审计便利保留整份 Apple JWS 或个人账户。

参考：[Apple appAccountToken](https://developer.apple.com/documentation/storekit/product/purchaseoption/appaccounttoken(_:))、[Apple 账号删除要求](https://developer.apple.com/support/offering-account-deletion-in-your-app/)。

## 4. Sandbox / TestFlight / Production

Apple 对 TestFlight 交易使用 **Sandbox**，不是另一个叫 TestFlight 的 transaction environment。因此数据库按 Apple 可信环境存储：

- Sandbox tester / TestFlight -> Sandbox；
- 正式购买 -> Production。

不从 productId、HTTP query 或客户端 isTestFlight 布尔值推断环境。Phase 2 需从 Apple 已验证数据及部署配置确定环境。

同一 user 在两个环境有不同 appAccountToken；同名 transaction ID / notification UUID 在两个环境的记录相互独立。Sandbox 的过期/撤销不会修改 Production grant。查询必须显式指定环境，没有“未找到生产就退回 Sandbox”的逻辑。

**Sandbox tester 与 TestFlight 不能仅凭 JWS environment 再互相区分。** 若产品需要它们也完全分库，应通过独立验收部署/测试账号规划实现，不能伪造 Apple 第三种 environment。本轮没有新增未经证明的渠道识别字段，也没有将任何测试权益授予生产。

## 5. Migration / rollout / rollback

- 新增 `008_app_store_subscriptions.up.sql` 与 `.down.sql`。
- 同步追加 `schema.sql` 中 008 区块，单元测试逐字校验与 migration DDL 一致。
- 001-007 保持不动。验证从它们之后继续升级，历史用户与 user_entries 保留；没有历史订阅 backfill，没有阅读 ledger 写入。
- up 包含事务、5 秒 lock_timeout、60 秒 statement_timeout，可重复执行。
- 下线业务代码无需删除表。down 仅用于所有新增表都为空的未使用安装；只要存在 account、ownership tombstone 或审计就拒绝，避免“回滚”删除防重认领记录。
- down 不是生产订阅数据清理工具，也没有强制删数据开关；成功 down 后可再 up。
- CREATE TABLE 的外键创建需短暂锁 users，被长事务阻挡会超时回滚；已有订阅表重复部署会因索引/trigger DDL 获取锁。没有旧业务表 rewrite 或大数据 backfill，仍应在维护窗口观察锁等待。
- 旧 backend 不认识新增表仍可运行。原 DELETE users 会自动执行新外键/触发器清理；不能用旧代码绕过归属 tombstone。
- 只在隔离测试实例执行过 008，未执行线上 migration。

## 6. 商品配置

集中位置：`backend/src/config/subscriptions.js`。

- Bundle ID 保持：`com.youxugarden.zhireader`。
- Group：`Zhidu Pro`。
- Monthly：`com.youxugarden.zhreader.pro.monthly`。
- Yearly：`com.youxugarden.zhreader.pro.yearly`。

商品 ID 按本轮确认值使用，和 Bundle ID 拼写不同是有意保留，并非自动推导错误。此决定覆盖 Phase 0 的暂定商品建议。没有 Apple 商品、密钥、定价或 webhook 的真实配置。

## 7. 修改文件

新增：

- backend/src/db/migrations/008_app_store_subscriptions.up.sql
- backend/src/db/migrations/008_app_store_subscriptions.down.sql
- backend/src/config/subscriptions.js
- backend/src/repositories/subscription.repository.js
- backend/src/services/subscriptionState.js
- backend/src/services/entitlement.service.js
- backend/src/services/subscriptionState.test.js
- backend/src/repositories/subscription.postgres.test.js
- docs/zhidu-pro-phase1.md

局部修改：

- backend/src/db/schema.sql：追加 008 区块，保留当前工作区已有的 Obsidian schema。
- backend/package.json：只追加三项 subscriptions test/check script，保留已有未提交修改。

没有新增 npm/Flutter 依赖或密钥环境变量，没有新增 HTTP API。

## 8. 实跑结果

Docker Desktop 启动因自身 Inference manager 路径错误失败，没有 reset Docker。改用下载并校验发布包 SHA512 的独立 PostgreSQL **16.13** 二进制，在临时目录创建新 cluster，只监听 **127.0.0.1:55442**。没有连接 55440 的原有验收实例。

测试库：

- zhidu_subscription_phase1_test：订阅测试，每次创建随机 schema，结束只移除该 schema。
- zhidu_subscription_ledger_test：原 ledger 破坏性 fixture 使用的全新测试库。
- zhidu_obsidian_phase1_test：在本次新 cluster 中创建的同名空库，不是用户原来 55440 的 Obsidian 验收库。

| 项目 | 本轮结果 |
| --- | --- |
| 新增 subscriptionState 单元测试 | 8 通过 |
| 新增真实 PG 模型测试 | 15 通过（包含父测试）；不 mock SQL/事务/核心业务判断 |
| 全部后端非 PG 测试 | 61 通过，包括原有 53 项和新增 8 项 |
| 原 ledger/reliable upload 真 PG 测试 | 19 通过 |
| 原 Obsidian 真 PG 测试 | 12 通过 |
| backend npm run check / check:subscriptions / check:obsidian / check:reliable-upload | 通过 |
| Flutter Windows harness | 64 通过，2 个模式限定 skip |
| 根目录 Flutter tests | 64 通过，原有 6 个 SQLite native asset 加载失败 |
| flutter analyze --no-pub | 原有 share_service.dart:64:43 异步 BuildContext info，exit 1 |
| Obsidian plugin npm test | 20 通过，2 个需要专用 HTTP 测试环境的 integration skip |

新增模型 PG 用例覆盖：从 001-007 升级与重复执行、空库 down/up、并发稳定 token、首次 grant、重复通知、同版本 replay/conflict、旧 snapshot、取消续费仍有效、renewal、服务器时间 expiry、grace/billing retry、revocation、跨账号并发认领、跨环境与跨账号 FK、故障全回滚、查询异常不变 FREE、多条有效权益合并、两个环境账户删除清理、retired 链拒绝重新认领、删除回滚、删除与验证竞争、禁止有数据 down、历史数据和 ledger 不受影响。

既有 Flutter SQLite / BuildContext 问题未改。此次已跑测试没有发现新增 regression。Apple 签名、证书链、真实购买、真正 Apple 通知和 TestFlight 均未在 Phase 1 实现或验证，不能把上述合成 snapshot 测试称为 Apple 验收通过。

### 复跑

在 backend 目录：

```powershell
npm run test:subscriptions
npm run check:subscriptions
$env:SUBSCRIPTION_TEST_DATABASE_URL='postgresql://postgres@127.0.0.1:55442/zhidu_subscription_phase1_test'
npm run test:subscriptions:postgres
```

最后一条需要先准备独立 PostgreSQL 服务和指定测试库。不要把该地址改成生产库或现有人工验收库；该测试仅接受 loopback 和精确测试库名。测试实例本轮结束后关闭，不是常驻服务。

## 9. 停止边界

Phase 1 完成到内部基础设施，停在这里等待审阅。Phase 2 必须补齐官方库 JWS/certificate verification、Apple API 对账、可信 DTO 构造、未知/早到通知处理、网络故障恢复和公开 API 的鉴权/环境边界，之后才可接客户端购买。
