# 知读 — 待清理项

> 每个阶段结束时逐项处理。处理完的打 ✅。

---

## 🔴 架构层面

### 1. `ai_service.dart` 直连 DeepSeek，应迁移到后端

**现状**：`lib/services/ai_service.dart` 直接从 Flutter 端调 `api.deepseek.com`，API Key 存在 SharedPreferences。

**问题**：
- Key 暴露在客户端
- 产品文档要求统一走后端 `/api/ai/*`
- 无法做服务端缓存、用量控制、日志

**方案**：在后端新增 `POST /api/ai/explain` 和 `POST /api/ai/chat`，`ai_service.dart` 改为调后端。

**影响文件**：
- `lib/services/ai_service.dart`（改）
- `backend/src/routes/`（新增 ai.routes.js）
- `backend/src/controllers/`（新增 ai.controller.js）

**优先级**：🐝 小U阶段必须做（小U对话依赖后端 AI）

---

### 2. `bmob_api.dart` 命名误导

**现状**：文件名为 `bmob_api.dart`，类名 `BmobApi`，但实际调的是自建后端 `apiBaseUrl`，不是 Bmob 云服务。这是历史残留。

**问题**：新 Agent 看到这个名字会困惑——到底有没有在用 Bmob？

**方案**：重命名为 `api_client.dart`，类名 `ApiClient`。同时更新所有引用。

**影响文件**：
- `lib/services/bmob_api.dart` → `api_client.dart`
- `lib/services/auth_service.dart`（import 改）
- `lib/services/book_service.dart`（import 改）
- `lib/services/sync_service.dart`（import 改）

**优先级**：🐝 下次改后端 API 时顺手一起改

---

### 3. 后端缺少 AI 路由

**现状**：后端只有 `auth.routes.js`、`entries.routes.js`、`readingProgress.routes.js`，没有 AI 相关路由。

**问题**：小U的自动标签、自动摘要、对话都无法实现。

**方案**：新增 `POST /api/ai/explain`（解释）、`POST /api/ai/tag`（打标签）、`POST /api/ai/summarize`（摘要）、`POST /api/ai/chat`（小U对话）。

**优先级**：🔴 第一阶段阻塞项

---

## 🟡 代码质量

### 4. `book_service.dart` 713 行 —— 逼近上帝类

**现状**：`lib/services/book_service.dart` 混合了书籍管理、EPUB 解析、封面提取、进度同步。

**问题**：超过 400 行阈值。一次改 EPUB 解析可能不小心破坏进度同步。

**建议拆分**：
- `book_service.dart`（书籍 CRUD + 书架管理）
- `book_import_service.dart`（导入 + 解析）
- 封面逻辑移到已有的 `epub_service.dart`

**优先级**：🟡 下次改 book_service 时拆分

---

### 5. `ai_service.dart` 中 `explain()` 和 `chat()` 70% 重复

**现状**：两个方法各自拼 prompt、调 API、解析响应，几乎一样。

**问题**：改一个容易忘记改另一个。

**方案**：提取公共方法 `_callDeepSeek(systemPrompt, messages)`，`explain()` 和 `chat()` 只负责构造 prompt。

**优先级**：🟡 迁移到后端时自然消失（Flutter 端只调后端一个端点）

---

### 6. `AppConstants.apiBaseUrl` 硬编码 IP

**现状**：`lib/config/constants.dart` 中写死了 `http://101.32.186.151:3000`。

**问题**：如果 IP 变了，需要改代码重新编译。

**方案**：至少从配置文件/环境变量读取，或者做成设置页可配置项。

**优先级**：🟢 暂时不影响开发

---

## 🟢 工程规范

### 7. 零测试覆盖率

**现状**：`flutter_test` 已在 dev_dependencies 中，但只有一个 smoke test。新增的 `ai_conversation_test.dart` 是第二个。

**方案**：每新增一个 service，至少写 1 个 model 序列化测试 + 1 个错误处理测试。不需要高覆盖率，但关键路径必须有。

**优先级**：🟢 随开发节奏渐进增加

---

### 8. 后端 539 行 JS 无测试

**现状**：后端完全没有测试框架。

**方案**：至少给 `POST /api/auth/register` 和 `POST /api/entries` 加集成测试。

**优先级**：🟢 第一阶段结束后补
