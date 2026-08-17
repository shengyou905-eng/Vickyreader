import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_reader/services/reader_font_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds an embeddable font data URI without changing bytes', () {
    final bytes = Uint8List.fromList([0, 1, 2, 127, 128, 255]);

    final uri = ReaderFontService.dataUriForBytes(bytes, 'font/otf');

    expect(uri, startsWith('data:font/otf;base64,'));
    final encoded = uri.substring(uri.indexOf(',') + 1);
    expect(base64Decode(encoded), bytes);
  });
}
