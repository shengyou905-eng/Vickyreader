import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/sync_service.dart';
import '../auth/auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiKeyController = TextEditingController();
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiKeyController.text = settings.apiKey;
  }

  void _saveApiKey() {
    context.read<SettingsProvider>().setApiKey(_apiKeyController.text.trim());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('API Key 已保存'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Account
              _SectionHeader(title: '账户'),
              const SizedBox(height: 8),
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: auth.isLoggedIn
                        ? _buildLoggedIn(auth)
                        : _buildLoggedOut(),
                  );
                },
              ),
              const SizedBox(height: 24),

              // AI Settings
              _SectionHeader(title: 'AI 服务'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.api, size: 20, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        const Text(
                          'DeepSeek API',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: settings.apiKey.isNotEmpty
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            settings.apiKey.isNotEmpty ? '已配置' : '未配置',
                            style: TextStyle(
                              fontSize: 11,
                              color: settings.apiKey.isNotEmpty
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureKey,
                      decoration: InputDecoration(
                        hintText: '请输入 DeepSeek API Key',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(_obscureKey
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              iconSize: 18,
                              onPressed: () => setState(
                                  () => _obscureKey = !_obscureKey),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '使用 DeepSeek V3 模型，支持联网搜索。'
                      'API Key 仅存储在本地，不会上传到任何服务器。',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: _saveApiKey,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // About
              _SectionHeader(title: '关于'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.dividerColor),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '版本 1.0.0',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'AI 辅助阅读，让每本书都更易懂',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoggedOut() {
    return Row(
      children: [
        const Icon(Icons.account_circle, size: 22, color: AppTheme.primary),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '未登录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 2),
              Text(
                '登录后同步阅读进度和小U条目',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: _openAuth,
          child: const Text('登录 / 注册'),
        ),
      ],
    );
  }

  Widget _buildLoggedIn(AuthProvider auth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, size: 22, color: Colors.green),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.email ?? '',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '已连接云端账号',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            OutlinedButton(
              onPressed: _switchAccount,
              child: const Text('切换账户'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => auth.signOut(),
              child: const Text('退出登录', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openAuth() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    if (result == true && mounted) {
      await _onLoginSuccess();
    }
  }

  Future<void> _switchAccount() async {
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    await _openAuth();
  }

  Future<void> _onLoginSuccess() async {
    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null || userId.isEmpty) return;

    try {
      SyncService.instance.setUserId(userId);
      await SyncService.instance.mergeAnonymousData(userId);
      await SyncService.instance.pullAll();
    } catch (_) {}
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
