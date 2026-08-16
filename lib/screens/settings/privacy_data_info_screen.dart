import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/constants.dart';
import '../../config/theme.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../services/privacy_service.dart';
import 'legal_document_screen.dart';

class PrivacyDataInfoScreen extends StatelessWidget {
  const PrivacyDataInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final items = <_DocumentItem>[
      _DocumentItem(
        icon: Icons.shield_outlined,
        title: context.l10n.privacyPolicy,
        subtitle: context.l10n.privacyPolicySubtitle,
        url: Localizations.localeOf(context).languageCode == 'en'
            ? AppConstants.privacyPolicyEnglishUrl
            : AppConstants.privacyPolicyUrl,
      ),
      _DocumentItem(
        icon: Icons.list_alt_outlined,
        title: context.l10n.dataCollectionList,
        subtitle: context.l10n.dataCollectionListSubtitle,
        url: AppConstants.dataCollectionUrl,
      ),
      _DocumentItem(
        icon: Icons.hub_outlined,
        title: context.l10n.thirdPartyList,
        subtitle: context.l10n.thirdPartyListSubtitle,
        url: AppConstants.thirdPartiesUrl,
      ),
      _DocumentItem(
        icon: Icons.auto_awesome_outlined,
        title: context.l10n.aiDataProcessing,
        subtitle: context.l10n.aiDataProcessingSubtitle,
        url: AppConstants.aiDataProcessingUrl,
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.privacyDataInfo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider),
            ),
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  _DocumentTile(item: items[index]),
                  Divider(height: 1, color: palette.divider),
                ],
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  minLeadingWidth: 28,
                  titleAlignment: ListTileTitleAlignment.center,
                  leading: const Icon(Icons.person_remove_outlined),
                  title: Text(
                    context.l10n.accountDataDeletion,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(context.l10n.accountDataDeletionSubtitle),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccountDataDeletionScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AccountDataDeletionScreen extends StatefulWidget {
  const AccountDataDeletionScreen({super.key});

  @override
  State<AccountDataDeletionScreen> createState() =>
      _AccountDataDeletionScreenState();
}

class _AccountDataDeletionScreenState extends State<AccountDataDeletionScreen> {
  bool _deleting = false;

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final auth = context.read<AuthProvider>();
    final needsPassword = auth.hasPassword;
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.deleteAccountTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              needsPassword
                  ? context.l10n.deleteAccountBody
                  : context.l10n.appleAccountDeleteConfirm,
              style: const TextStyle(height: 1.55),
            ),
            if (needsPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.l10n.currentPassword,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(
              dialogContext,
              needsPassword ? controller.text : '__confirmed__',
            ),
            child: Text(context.l10n.deletePermanently),
          ),
        ],
      ),
    );
    controller.dispose();
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PrivacyService.deleteAccount(
        password: needsPassword ? password : null,
        confirm: !needsPassword,
      );
      await auth.signOut();
      if (!mounted) return;
      final message = context.l10n.accountDeleted;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(context.l10n.deleteAccountFailed('$error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final isLoggedIn = context.watch<AuthProvider>().isLoggedIn;
    final errorColor = Theme.of(context).colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.accountDataDeletion)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.divider),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              minLeadingWidth: 28,
              leading: const Icon(Icons.description_outlined),
              title: Text(
                context.l10n.accountDataDeletion,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(context.l10n.accountDataDeletionSubtitle),
              trailing: const Icon(Icons.open_in_new_rounded, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LegalDocumentScreen(
                    title: context.l10n.accountDataDeletion,
                    url: AppConstants.accountDeletionUrl,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              context.l10n.deleteAccountBody,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isLoggedIn)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: errorColor,
                side: BorderSide(color: errorColor.withValues(alpha: 0.55)),
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _deleting ? null : _deleteAccount,
              icon: _deleting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_remove_outlined),
              label: Text(
                _deleting
                    ? context.l10n.deletingAccount
                    : context.l10n.deleteAccount,
              ),
            )
          else
            Text(
              context.l10n.signInToManagePrivacy,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  final _DocumentItem item;

  const _DocumentTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 28,
      titleAlignment: ListTileTitleAlignment.center,
      leading: Icon(item.icon),
      title: Text(
        item.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(item.subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LegalDocumentScreen(title: item.title, url: item.url),
        ),
      ),
    );
  }
}

class _DocumentItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  const _DocumentItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });
}
