# 小U阅读解读离线基准 V1

这是 P0b 第一阶段的固定材料、评分标准及离线一致性检查，不是模型调用器，也不是已经完成的模型质量测评。

## 文件

- `cases.v1.json`：20 个原创合成案例，每种免费模式 4 个。包含实际请求材料、逐字证据、应答要点、禁止误读、参考答法；`ARGUMENT-04` 附 14 轮追问。
- `rubric.v1.json`：五维评分、关键失败项和待确认验收门槛。
- `offline.test.cjs`：案例结构、引文出处、模式覆盖、评分权重及现有后端上下文契约检查。
- `../../docs/zhidu-xiaou-p0b-stage1.md`：代码审查、Prompt/上下文改进提案、Token/延迟/成本设计和本轮结果。

## 运行（无新增依赖）

在项目根目录：

```powershell
node --test tool/xiaou_reading_eval/offline.test.cjs
```

只加载 JSON 和纯 `aiProtocol` 模块，不加载 app/controller/db，不创建数据库、不读取环境密钥、不发送 HTTP 请求。controller 源文件只读用于 SHA-256 版本记录。测试拦截 `fetch` 并要求调用数为 0；工具没有模型执行/联网入口。

该检查通过仅说明评测材料和契约自洽。它不判断参考答案已经由模型生成，不代表现有模型回答正确。

## P0b 第二阶段回归

固定 20 个案例和 rubric 保持不变。第二阶段已把它们用于真实 Prompt/证据构造函数及控制器到本地 HTTP 上游替身的回归：

```powershell
node --test tool/xiaou_reading_eval/offline.test.cjs backend/src/services/readingInterpretation.test.js backend/src/controllers/readingQuality.http.test.js
```

纯构造测试核对来源分层、scope、截取范围、五模式目标、Prompt/客户端缓存版本及整轮历史。HTTP 测试实际运行控制器与 SSE 解析，把供应商请求重定向到本地 loopback；合成参考回答只由上游替身返回，不混入待测模型请求。覆盖显式伪引文不发 completed/DONE、14轮纠正保留、selection/page/chapter、旧字段兼容和输入拒绝。

第二阶段版本为 `xiaou-reading-v2.20261019`，真实评测后的代码精修版本为 `xiaou-reading-v3.20261019`，同步提升 Flutter 缓存版本。显式原文核验只检查 `原文：“...”` / `Source quote: "..."` 等约定格式的逐字出处，不核验所有引号、背景知识或结论的逻辑真伪；没有使用真实模型证明 20 例语义质量达标。

详见 `../../docs/zhidu-xiaou-p0b-stage2.md`。不更改本基准材料来迎合新 Prompt，也不把上游替身的正确回答当成现有模型的质量成绩。

## 真实评测后的离线精修

第三阶段已获许可的 12 次真实调用及原始回答见 `../../docs/zhidu-xiaou-p0b-stage3.md`；这些历史结果属于 v2，不能在改 Prompt 后重新标成 v3 的表现。本轮只做离线精修，不调用 `live.cjs --execute`，不删除上一批 execution.lock。

```powershell
node --test tool/xiaou_reading_eval/offline.test.cjs backend/src/services/readingInterpretation.test.js backend/src/services/readingInterpretation.refinement.test.js backend/src/controllers/readingQuality.http.test.js
```

新增条件方向反例、所有模式共用规则、来源范围提示、自然表达规则、技术类原文不删词、旧 AI 可纠错及 14 轮契约检查。真值表只证明反例逻辑自洽，Prompt 断言只证明约束实际进入请求；本地 HTTP 的回答是合成替身，均不能证明真实模型已经不再混淆必要/充分条件或泄露字段。

原有 `cases.v1.json`、`rubric.v1.json` 和第三阶段所有原始回答保持原样。后续真实质量复核必须单独获得授权，不能用本轮离线通过冒充模型质量验收。

## 案例输入与评审材料分离

模型输入只能来自每个案例的 `request`。`expected`、`evidence`、`comparison_only`、`follow_ups[].checks` 和参考回答是评审材料，不得混入当前请求。

证据 ID 是评测夹具内部身份，不是实际阅读锚点或真实 trace ID。`field + quote` 明确指向本次已提供的原文区域；不会因同句出现在另一处就自动取得那里的上下文。缺失作者保持空串，不造出作者。

`ARGUMENT-04.seed_answer` 故意错误，只用于“纠正先前错误 AI”的受控测试；不能把它当标准首轮解读。离线 14 轮使用参考答法模拟已经发生的历史，只验证固定原文不会随窗口裁剪丢失，不验证真实模型的记忆或推理。

首次真实生成评测、固定错误 seed 的纠错评测要分开标注。后续若获模型调用许可，每轮只追加本次已实际得到的回答，不用后面轮次的 gold 预填历史。测试案例数不等于调用次数，14 轮及重试应逐次记录。

## 人工评审流程（后续模型调用需另行授权）

1. 固定 suite/rubric SHA-256、Prompt 版本、代码版本和请求/实际模型；给旧方案与候选方案相同输入。模拟、历史回放、真实生成必须分组，不混算成绩。
2. 按模式分层打乱匿名答案顺序，由两名评审依据原文独立评分，不以供应商、模型名、篇幅或措辞华丽程度评分。
3. 每条对照 `key_points`、`must_not`。直接引文核验逐字匹配；若使用省略号，分别核对两端连续片段。意译不能装成逐字引文。
4. 给正确性、证据、模式匹配、可读性、不确定性各 0–4 分，按 rubric 权重换算为 100 分。
5. 任一关键失败先记录，不用高可读性抵消。同维差异超过 1 分或关键失败判断不一致，复核原文并裁决。
6. 14 轮逐轮检查，尤其是第 1 轮纠错、第 6 轮未知数字、第 9 轮未知作者、第 14 轮首轮证据。不能只看最后一句是否像答案。
7. 报告总分、各模式、复杂论证/未知/追问子集、引文错误数及完成率。不完整响应单列，不静默剔除；不要求模型给内部思维链。

建议评审记录列：

```text
suite_hash, rubric_hash, run_group, anonymous_answer_id, case_id, turn_index,
prompt_version, model_requested, model_returned, outcome,
reviewer_id, correctness, evidence, mode_fit, clarity, calibration,
critical_failures, missing_key_points, disputed_evidence_ids, review_note
```

参考答案不是唯一正确答案。`uncertainty=not_required` 不要求机械添加“不能确定”；`conditional` 要限制材料外推；`required` 要指出具体缺证，但不能回避已经足够回答的内容。评分阈值是提案，尚未成为产品承诺。

## 已知限制

- 20 条合成材料是冒烟基准，不代表真实书籍、文学阐释、专业医学/法律材料、长章节和英文场景的整体质量。
- 引文真的存在不等于它能支持附着的判断；离线测试特意保留这种反例，不能用关键词或子串命中代替人工语义审查。
- 当前离线 14 轮只调用现有纯后端上下文函数；客户端 Provider/SQLite/会话隔离由此前 P0a/专项测试覆盖，本工具不重新打开任何用户数据库。
- 不调整免费模式、价格、额度、模型、缓存产品语义、IAP、Obsidian、私人随心记或阅读 UI。
