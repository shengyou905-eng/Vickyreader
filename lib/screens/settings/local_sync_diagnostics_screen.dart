import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/local_sync_diagnostics.dart';

class LocalSyncDiagnosticsScreen extends StatefulWidget {
  const LocalSyncDiagnosticsScreen({super.key});

  @override
  State<LocalSyncDiagnosticsScreen> createState() =>
      _LocalSyncDiagnosticsScreenState();
}

class _LocalSyncDiagnosticsScreenState
    extends State<LocalSyncDiagnosticsScreen> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting || !LocalSyncDiagnostics.enabled) return;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    setState(() => _exporting = true);
    try {
      // Read only the stored user ID; do not initialize AuthProvider/BmobApi.
      final file = await LocalSyncDiagnostics.export(
        currentUserId: await LocalSyncDiagnostics.storedUserId(),
      );
      if (!mounted) return;
      final box = context.findRenderObject();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        sharePositionOrigin: box is RenderBox
            ? box.localToGlobal(Offset.zero) & box.size
            : const Rect.fromLTWH(0, 0, 1, 1),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chinese
                ? '未能导出本地诊断，请检查文件空间后重试。'
                : 'Could not export local diagnostics. Check available storage and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Scaffold(
      appBar: AppBar(title: Text(chinese ? '开发者诊断' : 'Developer Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _exporting || !LocalSyncDiagnostics.enabled
                ? null
                : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share),
            label: Text(chinese ? '导出本地同步状态' : 'Export Local Sync State'),
          ),
        ],
      ),
    );
  }
}
