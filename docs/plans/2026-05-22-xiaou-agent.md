# 小U Agent 化 — 实施计划

> 历史方案说明：本文早于 `docs/zhidu_product_direction.md`。后续不可直接按“通用聊天 Agent”思路实现小U；必须以“阅读意识层”为准，先做结构化记忆、主题层和人格层缓存，再做克制的回顾式对话。

> **For Hermes:** 使用 subagent-driven-development 逐 task 执行。

**目标：** 把小U从静态知识浏览页变成真正的 AI Agent —— 基于用户阅读记录的对话式体验，支持流式输出、多轮追问。

**当前状态：**
- 后端 `/api/insights/questions/:id/answer` 是**纯规则计算**（数标签、数书籍），没有调 DeepSeek
- 前端 `ai_service.dart` **直连 DeepSeek**（违反架构，且无法做流式）
- `MingtaiScreen` 被当小U用，实际是静态浏览页
- 没有聊天界面

**架构决策：**
- 所有 AI 调用统一走后端 `/api/ai/chat`（SSE 流式）
- 小U对话注入 user_entries 作为 context，让 AI 基于用户阅读记录回答
- 小U首页保留（洞察卡片 + 条目浏览），通过 FAB 进入对话
- 文件改名：`mingtai_screen.dart` → `xiaou_home_screen.dart`，`MingtaiScreen` → `XiaouHomeScreen`

---

## Task 1: 后端 — 新建 AI 路由和控制器

**目标：** 创建 `/api/ai/chat` SSE 端点

**文件：**
- Create: `backend/src/routes/ai.routes.js`
- Create: `backend/src/controllers/ai.controller.js`
- Modify: `backend/src/app.js`

### Step 1: 创建 ai.controller.js

```javascript
// backend/src/controllers/ai.controller.js
const entryRepository = require('../repositories/entry.repository');
const httpError = require('../utils/httpError');

const DEEPSEEK_URL = 'https://api.deepseek.com/v1/chat/completions';
const DEEPSEEK_API_KEY = process.env.DEEPSEEK_API_KEY;

const SYSTEM_PROMPT = `你是「小U」，知读App的AI阅读伙伴。

你的知识来源是用户留下的阅读痕迹——他们读过的书、划过的线、写下的想法、问过的AI解释。
你不是通用AI助手，你是一个了解用户阅读历程的思考伙伴。

规则：
1. 回答要基于用户的阅读记录，引用具体的书名和段落
2. 语气温暖但不腻，像一位爱读书的朋友在和你聊天
3. 如果用户的记录不足以回答某个问题，诚实说明，不要编造
4. 回答控制在 300 字以内，除非用户明确要求更详细
5. 用中文回答`;

async function chat(req, res, next) {
  try {
    const { message, history = [] } = req.body;
    if (!message || !message.trim()) {
      throw httpError(400, '消息不能为空');
    }

    // 获取用户最近 200 条阅读记录作为 context
    const entries = await entryRepository.listEntries(req.user.id, { limit: 200 });
    const context = buildContext(entries);

    // 构建消息
    const messages = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'system', content: `以下是用户近期的阅读记录，请基于这些内容回答问题：\n\n${context}` },
      ...history.slice(-10).map(m => ({ role: m.role, content: m.content })),
      { role: 'user', content: message },
    ];

    // 设置 SSE 响应头
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });

    const response = await fetch(DEEPSEEK_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${DEEPSEEK_API_KEY}`,
      },
      body: JSON.stringify({
        model: 'deepseek-chat',
        messages,
        temperature: 0.7,
        max_tokens: 1200,
        stream: true,
      }),
    });

    if (!response.ok) {
      const err = await response.text();
      res.write(`data: ${JSON.stringify({ error: 'AI 服务异常' })}\n\n`);
      res.end();
      return;
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.startsWith('data: ')) continue;
        const data = line.slice(6).trim();
        if (data === '[DONE]') {
          res.write('data: [DONE]\n\n');
          continue;
        }
        try {
          const parsed = JSON.parse(data);
          const content = parsed.choices?.[0]?.delta?.content;
          if (content) {
            res.write(`data: ${JSON.stringify({ content })}\n\n`);
          }
        } catch (_) {
          // skip malformed chunks
        }
      }
    }

    res.end();
  } catch (error) {
    if (!res.headersSent) {
      return next(error);
    }
    res.write(`data: ${JSON.stringify({ error: error.message })}\n\n`);
    res.end();
  }
}

function buildContext(entries) {
  if (!entries || entries.length === 0) {
    return '用户还没有任何阅读记录。';
  }

  const lines = entries.slice(0, 200).map((entry, i) => {
    const book = entry.book_title || '未知书籍';
    const text = entry.original_text || entry.user_input || entry.ai_explanation || '';
    const source = sourceLabel(entry.source);
    const tags = tagsOf(entry).join('、');
    return `${i + 1}. [${source}]《${book}》${tags ? `🏷${tags}` : ''}\n   ${text.slice(0, 200)}`;
  });

  return `共 ${entries.length} 条记录（展示最近 ${Math.min(entries.length, 200)} 条）：\n\n${lines.join('\n\n')}`;
}

function sourceLabel(source) {
  return { highlight: '划线', thought: '想法', ai_explanation: 'AI解释', manual: '手动' }[source] || source;
}

function tagsOf(entry) {
  if (Array.isArray(entry.auto_tags)) return entry.auto_tags;
  if (typeof entry.auto_tags === 'string') return entry.auto_tags.split(',').map(t => t.trim()).filter(Boolean);
  return [];
}

module.exports = { chat };
```

### Step 2: 创建路由文件

```javascript
// backend/src/routes/ai.routes.js
const express = require('express');
const aiController = require('../controllers/ai.controller');
const auth = require('../middleware/auth');

const router = express.Router();

router.post('/chat', auth, aiController.chat);

module.exports = router;
```

### Step 3: 在 app.js 中注册路由

在 `backend/src/app.js` 中加一行：

```javascript
const aiRoutes = require('./routes/ai.routes');  // 在文件顶部 import 区
app.use('/api/ai', aiRoutes);                      // 在其他 app.use 之后
```

### Step 4: 设置环境变量

```bash
# 在服务器上设置 DeepSeek API Key
export DEEPSEEK_API_KEY=sk-xxxxxxxx
```

### Step 5: 重启后端并测试

```bash
cd backend && pm2 restart server
# 或 node server.js

# 测试（需要先登录获取 token）
curl -X POST http://localhost:3000/api/ai/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{"message":"我最近在关注什么？","history":[]}'
# 预期：返回 SSE 流式文本
```

---

## Task 2: 前端 — 创建 XiaoU 聊天页面

**目标：** 新建真正的 Agent 对话界面

**文件：**
- Create: `lib/screens/xiaou/xiaou_chat_screen.dart`
- Create: `lib/providers/xiaou_chat_provider.dart`

### Step 1: 创建 ChatProvider（管理对话状态 + SSE 流式）

```dart
// lib/providers/xiaou_chat_provider.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../config/constants.dart';
import '../../services/auth_service.dart';

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isStreaming;

  const ChatMessage({
    required this.role,
    required this.content,
    this.isStreaming = false,
  });
}

class XiaouChatProvider extends ChangeNotifier {
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _streamSub;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void addWelcomeMessage() {
    if (_messages.isEmpty) {
      _messages.add(const ChatMessage(
        role: 'assistant',
        content: '我是小U，你的阅读伙伴。\n\n我了解你读过的书、划过的线、写下的想法。想聊聊什么？',
      ));
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty || _isLoading) return;

    _error = null;
    _isLoading = true;

    // 添加用户消息
    _messages.add(ChatMessage(role: 'user', content: text.trim()));
    // 添加占位 AI 消息（流式更新）
    final aiMsg = ChatMessage(role: 'assistant', content: '', isStreaming: true);
    _messages.add(aiMsg);
    notifyListeners();

    try {
      final token = AuthService.token;
      if (token == null || token.isEmpty) {
        throw Exception('未登录');
      }

      final history = _messages
          .where((m) => !m.isStreaming && m.role != 'assistant' ? true : m.role == 'user')
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      // 去掉刚加的占位消息
      history.removeLast();

      final request = http.Request(
        'POST',
        Uri.parse('${AppConstants.apiBaseUrl}/api/ai/chat'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.headers['Authorization'] = 'Bearer $token';
      request.body = jsonEncode({
        'message': text.trim(),
        'history': history,
      });

      final streamed = await request.send();
      if (streamed.statusCode != 200) {
        throw Exception('请求失败 (${streamed.statusCode})');
      }

      final buffer = StringBuffer();
      _streamSub = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final data = line.substring(6).trim();
          if (data == '[DONE]') {
            _finalizeStream(buffer.toString());
            return;
          }
          try {
            final parsed = jsonDecode(data);
            if (parsed['error'] != null) {
              _handleError(parsed['error']);
              return;
            }
            final content = parsed['content'] as String?;
            if (content != null) {
              buffer.write(content);
              // 更新最后一条消息
              _messages.last = ChatMessage(
                role: 'assistant',
                content: buffer.toString(),
                isStreaming: true,
              );
              notifyListeners();
            }
          } catch (_) {}
        },
        onError: (e) => _handleError(e.toString()),
        onDone: () {
          if (buffer.isNotEmpty && _messages.last.isStreaming) {
            _finalizeStream(buffer.toString());
          }
        },
      );
    } catch (e) {
      _handleError(e.toString());
    }
  }

  void _finalizeStream(String content) {
    _messages.last = ChatMessage(role: 'assistant', content: content);
    _isLoading = false;
    notifyListeners();
  }

  void _handleError(String msg) {
    _error = msg;
    _isLoading = false;
    // 移除空的占位消息
    if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
      _messages.removeLast();
    }
    _streamSub?.cancel();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
```

### Step 2: 创建聊天页面 UI

```dart
// lib/screens/xiaou/xiaou_chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/xiaou_chat_provider.dart';

class XiaouChatScreen extends StatefulWidget {
  const XiaouChatScreen({super.key});

  @override
  State<XiaouChatScreen> createState() => _XiaouChatScreenState();
}

class _XiaouChatScreenState extends State<XiaouChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _showWelcome = true;
  late final XiaouChatProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<XiaouChatProvider>();
    _provider.addWelcomeMessage();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _showWelcome = false;
    _provider.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('小U'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<XiaouChatProvider>(
        builder: (_, provider, __) {
          // Scroll to bottom on new messages
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

          return Column(
            children: [
              Expanded(
                child: provider.messages.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: provider.messages.length,
                        itemBuilder: (_, i) => _buildBubble(provider.messages[i]),
                      ),
              ),
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(provider.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
              _buildInputBar(provider.isLoading),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 56, color: AppTheme.primaryLight),
          const SizedBox(height: 16),
          const Text('小U 阅读伙伴', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('基于你的阅读记录，随时和我聊聊', style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : AppTheme.primaryLight.withAlpha(25),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(6),
            bottomRight: isUser ? const Radius.circular(6) : const Radius.circular(18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.isStreaming)
              Text(
                msg.content.isEmpty ? '...' : msg.content,
                style: TextStyle(
                  color: isUser ? Colors.white : AppTheme.textPrimary,
                  fontSize: 15,
                  height: 1.55,
                ),
              )
            else
              Text(
                msg.content,
                style: TextStyle(
                  color: isUser ? Colors.white : AppTheme.textPrimary,
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
            if (msg.isStreaming)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary.withAlpha(150),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool loading) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: AppTheme.dividerColor.withAlpha(80))),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: '和小U聊聊你的阅读...',
                  filled: true,
                  fillColor: AppTheme.primaryLight.withAlpha(18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
```

### Step 3: 在 app.dart 注册 Provider

在 `MultiProvider` 的 providers 数组中添加：

```dart
ChangeNotifierProvider(create: (_) => XiaouChatProvider()),
```

---

## Task 3: 前端 — 小U首页改名为 XiaouHome + 加 FAB

**目标：** 把 mingtai_screen.dart 重命名为 xiaou_home_screen.dart，类名同步改，加浮动按钮进入对话

**文件：**
- Rename: `lib/screens/mingtai/mingtai_screen.dart` → `lib/screens/xiaou/xiaou_home_screen.dart`
- Rename: `lib/screens/mingtai/widgets/mingtai_card.dart` → `lib/screens/xiaou/widgets/xiaou_card.dart`
- Modify: `lib/app.dart`

### Step 1: 重命名 mingtai_screen.dart → xiaou_home_screen.dart

- 类名 `MingtaiScreen` → `XiaouHomeScreen`
- 类名 `_MingtaiScreenState` → `_XiaouHomeScreenState`
- import 路径更新
- `MingtaiInsight`, `MingtaiQuestionAnswer`, `BookService.getMingtaiOverview` 等暂时保留原名（这些是数据层的，与 UI 无关，后续逐步改）

### Step 2: 在 XiaouHomeScreen 加 FAB

在 Scaffold 中加：

```dart
floatingActionButton: FloatingActionButton.extended(
  onPressed: () {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const XiaouChatScreen()),
    );
  },
  icon: const Icon(Icons.chat_bubble_outline),
  label: const Text('和小U聊聊'),
  backgroundColor: AppTheme.primary,
  foregroundColor: Colors.white,
),
```

### Step 3: 重命名 mingtai_card.dart → xiaou_card.dart

- 类名 `MingtaiCard` → `XiaouCard`
- 更新所有 import

### Step 4: 修改 app.dart

```dart
// 更新 import
import 'screens/xiaou/xiaou_home_screen.dart';
import 'screens/xiaou/xiaou_chat_screen.dart';
import 'providers/xiaou_chat_provider.dart';

// 更新 _pages
List<Widget> get _pages => [
      const BookshelfScreen(),
      const XiaouHomeScreen(),
      const NotesFreeScreen(),
    ];

// 在 MultiProvider 中添加
ChangeNotifierProvider(create: (_) => XiaouChatProvider()),
```

---

## Task 4: 验证

### Step 1: Flutter analyze

```bash
cd /mnt/c/Users/29319/Desktop/reader && cmd.exe /c flutter analyze
```

### Step 2: 测试流程

1. 打开应用 → 小U Tab → 看到首页（洞察卡片 + 条目列表）
2. 点击右下角 FAB「和小U聊聊」→ 进入聊天页
3. 输入「我最近在关注什么？」→ 看到流式文本逐步输出
4. 追问「具体说说关于自由的部分」→ 多轮对话

---

## 当前暂不处理

- `ai_service.dart` 直连 DeepSeek 的问题（这是阅读器内 AI 解释的路径，后续改为走同一个后端）
- 明台 Tab（独立计划）
- `MingtaiInsight` / `MingtaiQuestionAnswer` 等类名（数据层，不改也影响不大，后续统一改）
