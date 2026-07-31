import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/sync_service.dart';
import '../../services/privacy_service.dart';
import '../../services/first_use_guide_service.dart';
import '../auth/auth_screen.dart';
import '../mingtai/community_mingtai_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
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
                  color: palette.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.divider),
                ),
                child: auth.isLoggedIn
                    ? _buildLoggedIn(auth)
                    : _buildLoggedOut(),
              );
            },
          ),
          const SizedBox(height: 24),

          Consumer<AuthProvider>(
            builder: (context, auth, _) => auth.isLoggedIn
                ? const _PrivacyAndSafetySection()
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),

          const _SectionHeader(title: '界面氛围'),
          const SizedBox(height: 8),
          const _AppearanceSection(),
          const SizedBox(height: 24),

          const _SectionHeader(title: '功能引导'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider),
            ),
            child: ListTile(
              leading: const Icon(Icons.help_outline_rounded),
              title: const Text('重新查看功能引导'),
              subtitle: const Text('下次进入对应场景时，再看一次简短提示'),
              trailing: const Icon(Icons.refresh_rounded),
              onTap: _resetFirstUseGuides,
            ),
          ),
          const SizedBox(height: 24),

          // About
          const _SectionHeader(title: '关于'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '版本 1.0.0',
                  style: TextStyle(color: palette.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  AppConstants.appTagline,
                  style: TextStyle(fontSize: 12, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLoggedOut() {
    final palette = context.appPalette;
    return Row(
      children: [
        Icon(Icons.account_circle, size: 22, color: palette.icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '未登录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                '登录后同步阅读进度和小U条目',
                style: TextStyle(fontSize: 12, color: palette.textSecondary),
              ),
            ],
          ),
        ),
        ElevatedButton(onPressed: _openAuth, child: const Text('登录 / 注册')),
      ],
    );
  }

  Widget _buildLoggedIn(AuthProvider auth) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle, size: 22, color: palette.icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.email ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '已连接云端账号',
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openMingtaiProfile,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.person_outline_rounded,
                  size: 21,
                  color: palette.icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '我的阅读档案',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '头像、昵称、在读书籍与公开想法',
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: palette.textSecondary),
              ],
            ),
          ),
        ),
        Divider(height: 18, color: palette.divider),
        Row(
          children: [
            OutlinedButton(
              onPressed: _switchAccount,
              child: const Text('切换账户'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => auth.signOut(),
              child: const Text(
                '退出登录',
                style: TextStyle(color: Color(0xFFAD6765)),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _deleteAccount(auth),
              child: const Text(
                '注销账号',
                style: TextStyle(color: Color(0xFFAD6765)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openAuth() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AuthScreen()));
    if (result == true && mounted) {
      await _onLoginSuccess();
    }
  }

  Future<void> _switchAccount() async {
    await context.read<AuthProvider>().signOut();
    if (!mounted) return;
    await _openAuth();
  }

  Future<void> _deleteAccount(AuthProvider auth) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('注销知读账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '账号、云端阅读记录、随心记、公开帖子、评论与个人资料将永久删除。设备里的本地书籍文件不会被删除。',
              style: TextStyle(height: 1.55),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: '输入当前密码确认'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFAD6765),
            ),
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('永久注销'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty || !mounted) return;
    try {
      await PrivacyService.deleteAccount(password);
      await auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('账号及云端关联数据已删除')));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('注销失败：$error')));
      }
    }
  }

  void _openMingtaiProfile() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CommunityProfileScreen()));
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

  Future<void> _resetFirstUseGuides() async {
    await FirstUseGuideService.resetAll();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('功能引导已重置，将在下次进入对应场景时出现')));
  }
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final visuals = context.appVisuals;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: visuals.surface,
        borderRadius: BorderRadius.circular(visuals.controlRadius),
        border: Border.all(color: visuals.divider),
      ),
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: AppThemeId.values.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              childAspectRatio: 1.48,
            ),
            itemBuilder: (context, index) {
              final themeId = AppThemeId.values[index];
              return _ThemeChoice(
                themeId: themeId,
                selected: settings.appThemeId == themeId,
                onTap: () => settings.setAppThemeId(themeId),
              );
            },
          );
        },
      ),
    );
  }
}

class _PrivacyAndSafetySection extends StatelessWidget {
  const _PrivacyAndSafetySection();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: '隐私与安全'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.divider),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('小U与第三方 AI'),
                subtitle: const Text('查看或撤回 DeepSeek 数据处理授权'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showAiPrivacy(context),
              ),
              Divider(height: 1, color: palette.divider),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('明台公开范围'),
                subtitle: const Text('控制阅读状态、进度、关注和同书发现'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CommunityPrivacyScreen(),
                  ),
                ),
              ),
              Divider(height: 1, color: palette.divider),
              ListTile(
                leading: const Icon(Icons.gavel_outlined),
                title: const Text('社区规范与举报'),
                subtitle: const Text('查看公开内容规范和联系邮箱'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showCommunityPolicy(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Future<void> _showAiPrivacy(BuildContext context) async {
    try {
      final consented = await PrivacyService.hasAiConsent(force: true);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('小U与 DeepSeek'),
          content: Text(
            consented
                ? '你已允许将主动提交的原文、上下文、提问和必要阅读痕迹发送给 DeepSeek。撤回后，小U将停止工作，阅读功能不受影响。'
                : '你尚未授权第三方 AI 数据处理。首次使用小U时会再次说明并征求同意。',
            style: const TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
            if (consented)
              FilledButton.tonal(
                onPressed: () async {
                  await PrivacyService.revokeAiConsent();
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('撤回授权'),
              ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取授权失败：$error')));
      }
    }
  }

  static Future<void> _showCommunityPolicy(BuildContext context) async {
    try {
      final policy = await PrivacyService.getCommunityGuidelines();
      if (!context.mounted) return;
      final principles = (policy['principles'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('明台社区规范'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...principles.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Text('• $item', style: const TextStyle(height: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
                Text('客服与举报邮箱：${policy['support_email'] ?? ''}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('读取社区规范失败：$error')));
      }
    }
  }
}

class CommunityPrivacyScreen extends StatefulWidget {
  const CommunityPrivacyScreen({super.key});

  @override
  State<CommunityPrivacyScreen> createState() => _CommunityPrivacyScreenState();
}

class _CommunityPrivacyScreenState extends State<CommunityPrivacyScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _showReadingStatus = false;
  bool _showReadingProgress = false;
  bool _allowFollows = true;
  bool _appearInSameBook = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await PrivacyService.getCommunityPrivacy();
      if (!mounted) return;
      setState(() {
        _showReadingStatus = data['show_reading_status'] == true;
        _showReadingProgress = data['show_reading_progress'] == true;
        _allowFollows = data['allow_follows'] != false;
        _appearInSameBook = data['appear_in_same_book'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取隐私设置失败：$error')));
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await PrivacyService.updateCommunityPrivacy({
        'show_reading_status': _showReadingStatus,
        'show_reading_progress': _showReadingProgress,
        'allow_follows': _allowFollows,
        'appear_in_same_book': _appearInSameBook,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('明台隐私设置已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('明台公开范围')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    '所有选项默认以保护私人阅读为先。单篇想法仍需在发布前单独确认。',
                    style: TextStyle(height: 1.55),
                  ),
                ),
                SwitchListTile(
                  title: const Text('公开正在读 / 读过 / 想读'),
                  value: _showReadingStatus,
                  onChanged: (value) =>
                      setState(() => _showReadingStatus = value),
                ),
                SwitchListTile(
                  title: const Text('公开阅读进度'),
                  subtitle: const Text('当前版本只保存偏好，页面暂不展示具体百分比'),
                  value: _showReadingProgress,
                  onChanged: (value) =>
                      setState(() => _showReadingProgress = value),
                ),
                SwitchListTile(
                  title: const Text('允许其他读者关注我'),
                  value: _allowFollows,
                  onChanged: (value) => setState(() => _allowFollows = value),
                ),
                SwitchListTile(
                  title: const Text('出现在“同书读者”中'),
                  value: _appearInSameBook,
                  onChanged: (value) =>
                      setState(() => _appearInSameBook = value),
                ),
                ListTile(
                  leading: const Icon(Icons.person_off_outlined),
                  title: const Text('已拉黑的读者'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlockedReadersScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '正在保存…' : '保存设置'),
                ),
              ],
            ),
    );
  }
}

class BlockedReadersScreen extends StatefulWidget {
  const BlockedReadersScreen({super.key});

  @override
  State<BlockedReadersScreen> createState() => _BlockedReadersScreenState();
}

class _BlockedReadersScreenState extends State<BlockedReadersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final users = await PrivacyService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取拉黑列表失败：$error')));
    }
  }

  Future<void> _unblock(Map<String, dynamic> user) async {
    final id = user['user_id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await PrivacyService.setBlocked(id, false);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('取消拉黑失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('已拉黑的读者')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
          ? const Center(child: Text('这里没有被拉黑的读者。'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = _users[index];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person_outline_rounded),
                  ),
                  title: Text(user['nickname']?.toString() ?? '读者'),
                  trailing: TextButton(
                    onPressed: () => _unblock(user),
                    child: const Text('取消拉黑'),
                  ),
                );
              },
            ),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final AppThemeId themeId;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChoice({
    required this.themeId,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.paletteFor(themeId);
    final currentPalette = context.appPalette;
    final visuals = context.appVisuals;
    return InkWell(
      borderRadius: BorderRadius.circular(visuals.controlRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: visuals.motionDuration,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
        decoration: BoxDecoration(
          color: selected
              ? palette.selectedBackground.withValues(alpha: 0.36)
              : visuals.surfaceSoft,
          borderRadius: BorderRadius.circular(visuals.controlRadius),
          border: Border.all(
            color: selected ? currentPalette.primary : visuals.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: visuals.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: palette.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Icon(
                        Icons.auto_stories_outlined,
                        size: 18,
                        color: palette.glow,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        width: 28,
                        height: 9,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    if (selected)
                      Align(
                        alignment: Alignment.topRight,
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: currentPalette.primaryDeep,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${themeId.label} · ${themeId.chineseLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? currentPalette.primaryDeep : visuals.ink,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: palette.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
