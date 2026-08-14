import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/auth_service.dart';
import '../services/privacy_service.dart';

class AiConsentGate {
  static Future<bool> ensure(BuildContext context) async {
    await AuthService.init();
    if (!AuthService.isLoggedIn) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.aiLoginRequired)));
      }
      return false;
    }
    try {
      if (await PrivacyService.hasAiConsent()) return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.aiConsentLoadFailed('$error'))),
        );
      }
      return false;
    }
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.aiConsentTitle),
        content: SingleChildScrollView(
          child: Text(
            dialogContext.l10n.aiConsentBody,
            style: const TextStyle(height: 1.65),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.decline),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.agreeContinue),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    try {
      await PrivacyService.acceptAiConsent();
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.aiConsentSaveFailed('$error'))),
        );
      }
      return false;
    }
  }
}

class AiGeneratedNotice extends StatelessWidget {
  const AiGeneratedNotice({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 5 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              context.l10n.aiGeneratedNotice,
              style: TextStyle(color: color, fontSize: compact ? 10.5 : 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
