import 'package:flutter/material.dart';

import '../services/privacy_service.dart';

Future<bool> ensureCommunityGuidelines(BuildContext context) async {
  try {
    final policy = await PrivacyService.getCommunityGuidelines();
    if (policy['accepted'] == true) return true;
    if (!context.mounted) return false;
    final principles = (policy['principles'] as List? ?? const [])
        .map((item) => item.toString())
        .toList(growable: false);
    final supportEmail = policy['support_email']?.toString() ?? '';
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('明台社区规范'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('明台围绕阅读交流。发布前，请确认：'),
              const SizedBox(height: 12),
              ...principles.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $item', style: const TextStyle(height: 1.5)),
                ),
              ),
              if (supportEmail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('举报与客服：$supportEmail'),
              ],
            ],
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
    await PrivacyService.acceptCommunityGuidelines(
      int.tryParse(policy['version']?.toString() ?? '') ?? 1,
    );
    return true;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('暂时无法读取社区规范：$error')));
    }
    return false;
  }
}

Future<bool> confirmPublicPostPreview(
  BuildContext context, {
  required String bookTitle,
  required String content,
  required String quote,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('确认公开这些内容'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('关联书籍：《$bookTitle》'),
                if (quote.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '短摘录',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(quote, maxLines: 6, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 14),
                const Text(
                  '你的公开内容',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(content, maxLines: 10, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                const Text(
                  '电子书文件、私人划线、阅读进度和未选择的内容不会公开。',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('返回修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认发布'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showCommunityReportDialog(
  BuildContext context, {
  required String targetType,
  required String targetId,
}) async {
  const options = <String, String>{
    'spam': '垃圾信息或广告',
    'harassment': '骚扰或人身攻击',
    'hate': '仇恨或歧视',
    'sexual': '色情内容',
    'violence': '暴力或威胁',
    'copyright': '版权问题',
    'privacy': '泄露隐私',
    'other': '其他问题',
  };
  final reason = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        children: [
          const ListTile(
            title: Text('举报内容', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('举报会进入人工审核，不会通知对方。'),
          ),
          ...options.entries.map(
            (entry) => ListTile(
              title: Text(entry.value),
              onTap: () => Navigator.pop(sheetContext, entry.key),
            ),
          ),
        ],
      ),
    ),
  );
  if (reason == null) return;
  try {
    await PrivacyService.report(
      targetType: targetType,
      targetId: targetId,
      reason: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已收到举报，我们会尽快处理。')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('举报失败：$error')));
    }
  }
}
