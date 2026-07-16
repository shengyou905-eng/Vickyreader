import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ReaderFontService {
  ReaderFontService._();

  static const _assetPath = 'assets/fonts/LXGWWenKaiLite-Regular.ttf';
  static const _fileName = 'LXGWWenKaiLite-Regular.ttf';
  static Future<String>? _fontUriFuture;

  static Future<String> ensureWenkaiFontUri() {
    return _fontUriFuture ??= _copyFontToReadableLocation();
  }

  static Future<String> _copyFontToReadableLocation() async {
    final supportDir = await getApplicationSupportDirectory();
    final fontDir = Directory(p.join(supportDir.path, 'reader_fonts'));
    await fontDir.create(recursive: true);
    final target = File(p.join(fontDir.path, _fileName));

    final assetData = await rootBundle.load(_assetPath);
    if (!await target.exists() ||
        await target.length() != assetData.lengthInBytes) {
      final bytes = Uint8List.sublistView(assetData);
      await target.writeAsBytes(bytes, flush: true);
    }
    return Uri.file(target.path).toString();
  }
}
