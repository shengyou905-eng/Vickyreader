# 小U P0b：缺证与证伪语义精修

日期：2026-10-20。小范围修改及离线验证完成，暂停等待确认；未开始 P1。

## 修改了什么

公共 Prompt 增加证据强度约束，统一作用于五种解读模式及问小U：

- 没有证据证明 A：本次材料不足以确认 A，不能据此确认非 A。
- 有证据证明非 A：需要实际支持相反判断的证据，结论限定在证据覆盖的范围。
- 原文明确否定 A：忠实说明作者否定的具体对象，但作者断言本身不等于已独立证实非 A。
- 纠错时，可以撤回旧 AI 的“已经证明 A”，不能把这变成“A 已被排除”。约束“原文明确否定了这个结论”等指向不清的表达。
- 条件判断保留有效推理：必要条件已确认不满足，与是否满足尚未知，是不同情况；满足必要条件也不保证结论成立。没有充分性证明不等于有不充分的证明。
- 原文确有反证或明确否定时，不一律弱化成未知。上述分类仅供内部核对，不增加固定栏目、强制话术或输出删词过滤器。

Prompt 和客户端缓存常量同步升为 `xiaou-reading-v4.20261020`。只改变新版请求使用的缓存版本，不删除或重写既有历史；仅更新后端仍不能自动清除未更新客户端的旧内存缓存。

## 文件范围

| 文件 | 本轮改动 |
| --- | --- |
| `backend/src/services/readingInterpretation.js` | 公共语义约束与版本，不改请求构造、历史窗口或引文门禁逻辑 |
| `lib/services/reading_history.dart` | 仅缓存版本常量 |
| `backend/src/services/readingInterpretation.refinement.test.js` | 仅更新当前版本断言，原基准哈希不变 |
| `backend/src/services/readingInterpretation.evidence.test.js` | 新增14项离线规则、材料隔离、反例与固定案例契约测试 |
| `backend/src/controllers/readingQuality.http.test.js` | 新增1个子测试，覆盖两条接口、三组合成材料及SSE原样传输 |
| 本报告 | 新增说明 |

新增7组合成材料：因果缺证、未检出不等于不存在、真实反例否定全称命题、作者否认但缺查证、必要条件未知、必要条件确认不满足、必要条件满足但充分性未知。材料和评审说明只存在新测试中，没有修改20例基准或评分标准，也不把期望答案放入模型请求。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 修改前定向离线基线 | 96通过 |
| 修改后定向离线回归 | 111通过，0失败 |
| 后端非PostgreSQL测试与既有通用评测离线测试 | 211通过，0失败 |
| Flutter独立harness的 `reading_quality_test.dart` | 4通过，0失败 |
| `dart analyze lib/services/reading_history.dart` | No issues found |
| `backend` 的 `npm run check` | 通过 |
| 历史v3专用驱动的版本/源码保护 | `makePlan()` 按预期拒绝当前v4，错误为 `SOURCE_HASH_MISMATCH`；没有取密钥或发请求 |

新增数量为14项纯测试和1个HTTP子测试。HTTP仅使用本机合成上游；完整后端离线集包含既有P0a、Obsidian、IAP相关回归，不是实际Apple/PostgreSQL联调。原20例、14轮上下文、证据与旧AI分离、SSE完成/截断及引文拒绝契约继续通过。

后端复跑命令（在 `backend` 目录）：

```powershell
$tests = @(rg --files src -g '*.test.js' | Where-Object { $_ -notlike '*.postgres.test.js' })
node --test $tests ../tool/xiaou_reading_eval/offline.test.cjs ../tool/xiaou_reading_eval/live.test.cjs
```

历史 `retest-v3.test.cjs` 是固定v3源码哈希的旧批次工具测试，本轮未将其冒充v4通用回归，也没有放宽旧驱动的哈希锁；核验了当前v4会在调用前被拒绝。旧请求计划、原始回答、匿名材料及执行锁保持原样。

## 限制与保护

离线测试验证规则实际进入请求、材料不被改写、评审答案不注入以及协议保持兼容。有限逻辑反例只验证夹具自洽；合成上游答案不代表真实模型回答。**本轮不能证明真实模型已经稳定消除“未证实/已排除”的混淆。** 引文门禁仍只验证直接引文出处，不判断解释是否蕴含于原文。

没有重跑整个Flutter套件、真实数据库或真机验收；既有SQLite环境问题和其他文件的BuildContext warning未修改，不宣称已解决。

对本轮开始登记的335个源码、测试、文档和既有评测文件核对SHA-256：仅计划内4个已有文件改变，0个丢失；新增1个测试文件及本报告。真实评测回答、基准语料、评分标准和执行锁全部不变。Git index为空。

没有调用付费模型或读取凭证，没有接触真实用户数据或备份；未改数据库、阅读UI、明台、Pro、IAP、Obsidian、小U发现、账号隔离或独立历史保存逻辑。未构建安装包、部署、commit、push。到此暂停。
