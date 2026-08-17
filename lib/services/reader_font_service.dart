import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/constants.dart';
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
      mimeType: 'font/otf',
    ),
    ReaderFontFamily.wenkai: _ReaderFontDefinition(
      assetPath: 'assets/fonts/LXGWWenKaiLite-Regular.ttf',
      fileName: 'LXGWWenKaiLite-Regular.ttf',
      cssFamily: 'LXGW WenKai Lite',
      format: 'truetype',
      mimeType: 'font/ttf',
    ),
  };
  static final Map<ReaderFontFamily, Future<ReaderFontAsset>> _fontFutures = {};

  static Future<ReaderFontAsset?> ensureFont(ReaderFontFamily family) {
    final definition = _fontDefinitions[family];
    if (definition == null) return Future.value();
    return _fontFutures.putIfAbsent(
      family,
      () => _resolveFontResource(definition),
    );
  }

  static Future<ReaderFontAsset> _resolveFontResource(
    _ReaderFontDefinition definition,
  ) async {
    final assetData = await rootBundle.load(definition.assetPath);
    final bytes = Uint8List.sublistView(assetData);
    if (Platform.isIOS) {
      // WKWebView does not consistently grant loadHtmlString documents access
      // to absolute file:// font URLs. A session-cached data URI keeps the
      // bundled font available without changing the chapter resource base URL.
      return ReaderFontAsset(
        cssFamily: definition.cssFamily,
        uri: dataUriForBytes(bytes, definition.mimeType),
        format: definition.format,
      );
    }

    // Keep WebView fonts under the same local resource root as chapter files.
    // Android requires file access for EPUB images and accepts this shared root.
    final documentsDir = await getApplicationDocumentsDirectory();
    final fontDir = Directory(
      p.join(documentsDir.path, AppConstants.booksDir, '.reader_fonts'),
    );
    await fontDir.create(recursive: true);
    final target = File(p.join(fontDir.path, definition.fileName));

    if (!await target.exists() ||
        await target.length() != assetData.lengthInBytes) {
      await target.writeAsBytes(bytes, flush: true);
    }
    return ReaderFontAsset(
      cssFamily: definition.cssFamily,
      uri: Uri.file(target.path).toString(),
      format: definition.format,
    );
  }

  @visibleForTesting
  static String dataUriForBytes(Uint8List bytes, String mimeType) {
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }
}

class _ReaderFontDefinition {
  final String assetPath;
  final String fileName;
  final String cssFamily;
  final String format;
  final String mimeType;

  const _ReaderFontDefinition({
    required this.assetPath,
    required this.fileName,
    required this.cssFamily,
    required this.format,
    required this.mimeType,
  });
}
