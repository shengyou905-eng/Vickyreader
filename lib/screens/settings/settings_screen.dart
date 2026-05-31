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

          const _SectionHeader(title: '界面氛围'),
          const SizedBox(height: 8),
          const _AppearanceSection(),
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
}

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.divider),
      ),
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return Row(
            children: [
              for (var i = 0; i < AppThemeId.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ThemeChoice(
                    themeId: AppThemeId.values[i],
                    selected: settings.appThemeId == AppThemeId.values[i],
                    onTap: () => settings.setAppThemeId(AppThemeId.values[i]),
                  ),
                ),
              ],
            ],
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(7, 8, 7, 7),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? currentPalette.primary : palette.divider,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 54,
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: palette.divider),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    size: 18,
                    color: palette.illustration,
                  ),
                  const Spacer(),
                  Container(
                    width: 21,
                    height: 9,
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Text(
              themeId.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? currentPalette.primaryDark
                    : currentPalette.textPrimary,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              themeId.chineseLabel,
              style: TextStyle(
                color: currentPalette.textSecondary,
                fontSize: 10,
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
