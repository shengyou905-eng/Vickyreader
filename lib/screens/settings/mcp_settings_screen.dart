import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../services/bmob_api.dart';
import '../../services/book_service.dart';

class McpSettingsScreen extends StatefulWidget {
  const McpSettingsScreen({super.key});

  @override
  State<McpSettingsScreen> createState() => _McpSettingsScreenState();
}

class _McpSettingsScreenState extends State<McpSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _accessToken;
  String _endpoint = '${AppConstants.apiBaseUrl}/mcp';

  bool get _isEnglish => Localizations.localeOf(context).languageCode == 'en';

  String get _title => _isEnglish ? 'MCP' : 'MCP 实验性功能';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Existing books may predate the optional MCP index. This synchronizes
      // only metadata and intentionally does not send local file paths/files.
      await BookService.syncMcpLibraryMetadata();
      final data = await BmobApi.instance.getMcpTokenStatus();
      if (!mounted) return;
      setState(() {
        _accessToken = data['access_token'] is Map
            ? Map<String, dynamic>.from(data['access_token'] as Map)
            : null;
        _endpoint = data['endpoint']?.toString().trim().isNotEmpty == true
            ? data['endpoint'].toString()
            : _endpoint;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _generateToken() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await BookService.syncMcpLibraryMetadata();
      final result = await BmobApi.instance.generateMcpToken();
      if (!mounted) return;
      final token = result['token']?.toString() ?? '';
      final record = result['access_token'] is Map
          ? Map<String, dynamic>.from(result['access_token'] as Map)
          : null;
      setState(() {
        _accessToken = record;
        _endpoint = result['endpoint']?.toString() ?? _endpoint;
      });
      if (token.isNotEmpty) {
        await _showOneTimeToken(token);
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          _isEnglish
              ? 'Could not generate MCP access: $error'
              : '生成 MCP 访问令牌失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showOneTimeToken(String token) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isEnglish ? 'Save this token now' : '请现在保存访问令牌'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isEnglish
                    ? 'This is the only time the complete token is shown. It grants read-only access to your reading traces. Do not share it with people or untrusted clients.'
                    : '完整令牌只会显示这一次。它可只读访问你的阅读痕迹，请不要分享给他人或不受信任的客户端。',
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 16),
              SelectableText(
                token,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_isEnglish ? 'Copied' : '已复制')),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(_isEnglish ? 'Copy' : '复制'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_isEnglish ? 'Done' : '我已保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeToken() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isEnglish ? 'Revoke MCP access?' : '撤销 MCP 访问？'),
        content: Text(
          _isEnglish
              ? 'Any client using the current token will immediately lose access to your reading knowledge.'
              : '使用当前令牌的所有客户端会立即失去对阅读知识的访问权限。',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_isEnglish ? 'Cancel' : '取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_isEnglish ? 'Revoke' : '撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await BmobApi.instance.revokeMcpToken();
      if (!mounted) {
        return;
      }
      setState(() => _accessToken = null);
      _showMessage(_isEnglish ? 'MCP access revoked' : 'MCP 访问已撤销');
    } catch (error) {
      if (mounted) {
        _showMessage(
          _isEnglish
              ? 'Could not revoke MCP access: $error'
              : '撤销 MCP 访问失败：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  _isEnglish
                      ? 'Read-only access to your reading knowledge'
                      : '让外部助手只读访问你的阅读知识',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isEnglish
                      ? 'MCP can list your bookshelf and search your highlights, thoughts, and Xiaou explanations. Free notes, complete Xiaou chats, account information, and every write action stay excluded.'
                      : 'MCP 只能列出书架并搜索划线、想法和小U解读。随心记、完整小U对话、账户资料以及所有写入操作都不会开放。',
                  style: TextStyle(color: palette.textSecondary, height: 1.55),
                ),
                const SizedBox(height: 24),
                _InfoBlock(
                  title: _isEnglish ? 'Endpoint' : 'MCP Endpoint',
                  value: _endpoint,
                  onCopy: () =>
                      Clipboard.setData(ClipboardData(text: _endpoint)),
                ),
                const SizedBox(height: 16),
                _InfoBlock(
                  title: _isEnglish ? 'Access' : '访问状态',
                  value: _accessToken == null
                      ? (_isEnglish ? 'Off' : '未启用')
                      : '${_accessToken?['token_prefix'] ?? 'zd_mcp_…'}  ·  ${_isEnglish ? 'read-only' : '只读'}',
                  subtitle: _accessToken?['expires_at'] == null
                      ? null
                      : (_isEnglish ? 'Expires ' : '有效期至 ') +
                            _formatDate(_accessToken!['expires_at'].toString()),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: palette.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: palette.divider),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _accessToken != null,
                    onChanged: _saving
                        ? null
                        : (enabled) =>
                              enabled ? _generateToken() : _revokeToken(),
                    title: Text(
                      _isEnglish ? 'Enable MCP access' : '启用 MCP 访问',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isEnglish
                          ? 'Allows an external client to read your selected reading data.'
                          : '允许外部客户端只读访问你选择开放的阅读数据。',
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    activeThumbColor: palette.primary,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _isEnglish
                        ? 'Could not load MCP status: $_error'
                        : '读取 MCP 状态失败：$_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      height: 1.45,
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: Text(_isEnglish ? 'Try again' : '重试'),
                  ),
                ],
                const SizedBox(height: 24),
                if (_accessToken != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _generateToken,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      _saving
                          ? (_isEnglish ? 'Working…' : '正在处理…')
                          : (_isEnglish ? 'Regenerate token' : '重新生成令牌'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  String _formatDate(String source) {
    final parsed = DateTime.tryParse(source)?.toLocal();
    if (parsed == null) return source;
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.title,
    required this.value,
    this.subtitle,
    this.onCopy,
  });

  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: palette.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              onPressed: () async {
                onCopy!();
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制')));
              },
              icon: const Icon(Icons.copy_outlined),
            ),
        ],
      ),
    );
  }
}
