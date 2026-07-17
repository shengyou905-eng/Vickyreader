import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/reader_typography.dart';

class ReaderFontAsset {
  final String cssFamily;
  final String uri;
  final String format;

  const ReaderFontAsset({
    required this.cssFamily,
    required this.uri,
    required this.format,
  });
}

class ReaderFontService {
  ReaderFontService._();

  static const _fontDefinitions = <ReaderFontFamily, _ReaderFontDefinition>{
    ReaderFontFamily.serif: _ReaderFontDefinition(
      assetPath: 'assets/fonts/SourceHanSerifCN-Regular.otf',
      fileName: 'SourceHanSerifCN-Regular.otf',
      cssFamily: 'ZhiDu Source Han Serif',
      format: 'opentype',
    ),
    ReaderFontFamily.wenkai: _ReaderFontDefinition(
      assetPath: 'assets/fonts/LXGWWenKaiLite-Regular.ttf',
      fileName: 'LXGWWenKaiLite-Regular.ttf',
      cssFamily: 'LXGW WenKai Lite',
      format: 'truetype',
    ),
  };
  static final Map<ReaderFontFamily, Future<ReaderFontAsset>> _fontFutures = {};

  static Future<ReaderFontAsset?> ensureFont(ReaderFontFamily family) {
    final definition = _fontDefinitions[family];
    if (definition == null) return Future.value();
    return _fontFutures.putIfAbsent(
      family,
      () => _copyFontToReadableLocation(definition),
    );
  }

  static Future<ReaderFontAsset> _copyFontToReadableLocation(
    _ReaderFontDefinition definition,
  ) async {
    final supportDir = await getApplicationSupportDirectory();
    final fontDir = Directory(p.join(supportDir.path, 'reader_fonts'));
    await fontDir.create(recursive: true);
    final target = File(p.join(fontDir.path, definition.fileName));

    final assetData = await rootBundle.load(definition.assetPath);
    if (!await target.exists() ||
        await target.length() != assetData.lengthInBytes) {
      final bytes = Uint8List.sublistView(assetData);
      await target.writeAsBytes(bytes, flush: true);
    }
    return ReaderFontAsset(
      cssFamily: definition.cssFamily,
      uri: Uri.file(target.path).toString(),
      format: definition.format,
    );
  }
}

class _ReaderFontDefinition {
  final String assetPath;
  final String fileName;
  final String cssFamily;
  final String format;

  const _ReaderFontDefinition({
    required this.assetPath,
    required this.fileName,
    required this.cssFamily,
    required this.format,
  });
}
