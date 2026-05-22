# 知读 — 项目开发规范

> 任何 Agent 在修改此项目代码前，**必须先读此文件**。

---

## 一、架构约定

```
lib/
├── config/       # 常量、主题配置（无业务逻辑）
├── models/       # 纯数据类，不依赖任何 service
├── services/     # 业务逻辑层，调后端 API 或本地 DB
├── providers/    # 状态管理（Provider），连接 service 和 UI
└── screens/      # UI 页面 + widgets
    ├── bookshelf/
    ├── reader/
    ├── mingtai/
    └── ...
```

### 铁律

1. **Flutter 不直连 AI API**。所有 AI 调用必须经过后端 `/api/ai/*`。`ai_service.dart` 的直连是临时方案，后续要改。
2. **services/ 不 import screens/**。单向依赖：screens → providers → services → models。
3. **models/ 不依赖 Flutter**。只 import dart: 和 package:，不 import flutter/。
4. **后端 API 调用统一走 `BmobApi`（后续重命名为 `ApiClient`）**。不在其他 service 中散落 http.post。

---

## 二、代码风格

### 文件大小
- 单个文件 ≤ 400 行。超过就拆。
- 单个方法 ≤ 50 行。超过就拆子方法。

### 命名
| 类型 | 规范 | 示例 |
|------|------|------|
| 文件 | snake_case | `ai_service.dart` |
| 类 | PascalCase | `AiService` |
| 方法/变量 | camelCase | `explainText()` |
| 常量 | SCREAMING_SNAKE_CASE | `MAX_RETRY_COUNT` |

### 错误处理
- 不要在 UI 层 try-catch，在 service 层处理。
- service 的方法要么返回结果，要么 throw。不要返回 `null` 表示错误。
- throw 时带上可读信息：`throw Exception('AI 服务返回空结果')`，不是 `throw Exception('error')`。

### 注释
- 不要写「解释这段代码在做什么」的注释——代码本身应该说清楚。
- 只写「为什么这样做」的注释——比如业务规则、边缘情况、已知缺陷。

---

## 三、修改代码前

1. 读 `ai_reading_app_product_structure_cn.md` 了解产品定位
2. 读要改的文件 + 所有引用它的文件（用 `search_files` 找引用）
3. 如果改 API 接口，同步改前端 service 和后端 controller
4. 改完后跑 `flutter analyze` 检查

---

## 四、修改代码后

1. 确认没有新增 import 循环
2. 删除不再使用的 import 和方法
3. 如果有测试，跑 `flutter test`
4. 如果改了产品方向，同步更新产品文档

---

## 五、禁止事项

| 禁止 | 原因 |
|------|------|
| 在 models/ 中写业务逻辑 | models 是纯数据结构 |
| 在 widget 的 build() 中调 service | 用 provider 管理状态 |
| 硬编码 API URL / Key | 用 config/constants.dart |
| 留注释掉的旧代码 | 删干净，git 历史能找回 |
| 引入新依赖不更新 pubspec.yaml | 保持依赖清晰 |
| 绕过 `BmobApi` 直接调 http | 统一入口方便切换后端 |
| 随心记模块接入任何 AI 功能 | 产品定位：完全隔绝 |

---

## 六、当前已知问题（待清理）

详见 `CLEANUP.md`。
