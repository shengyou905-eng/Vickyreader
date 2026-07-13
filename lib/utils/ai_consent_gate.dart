import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/privacy_service.dart';

class AiConsentGate {
  static Future<bool> ensure(BuildContext context) async {
    await AuthService.init();
    if (!AuthService.isLoggedIn) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('登录后才能使用小U')));
      }
      return false;
    }
    try {
      if (await PrivacyService.hasAiConsent()) return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('暂时无法读取 AI 授权状态：$error')));
      }
      return false;
    }
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('使用小U前，请先了解'),
        content: const SingleChildScrollView(
          child: Text(
            '为生成小U解读，你选择的原文、相关上下文、提问和必要的阅读痕迹将发送至第三方人工智能服务 DeepSeek 处理。\n\n'
            '小U全局对话还可能使用你的划线、想法、小U解读，以及你主动授权的随心记。私人书籍文件不会发送。\n\n'
            '请不要提交身份证、医疗信息、密码等敏感个人信息。AI 生成内容可能存在错误，请结合原文判断。',
            style: TextStyle(height: 1.65),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('暂不同意'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('同意并继续'),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存授权失败：$error')));
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
              '由 AI 生成，可能存在错误，请结合原文判断。',
              style: TextStyle(color: color, fontSize: compact ? 10.5 : 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
