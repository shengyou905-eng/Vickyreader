import 'dart:async';
import 'dart:io';

import 'package:ai_reader/l10n/l10n.dart';
import 'package:ai_reader/screens/xiaou/xiaou_load_failure.dart';
import 'package:ai_reader/services/api_request_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('401 wins regardless of concurrent request completion order', () {
    const auth = ApiRequestException(401);
    final timeout = TimeoutException('synthetic timeout');
    for (final errors in [
      [timeout, auth],
      [auth, timeout],
      [const ApiRequestException(500), auth],
    ]) {
      expect(
        XiaouLoadFailure.fromErrors(errors),
        XiaouLoadFailure.authentication,
      );
    }
  });

  test('transport failures are distinct from HTTP and decoding failures', () {
    for (final error in [
      const SocketException('synthetic offline'),
      TimeoutException('synthetic timeout'),
      http.ClientException('synthetic connection failure'),
    ]) {
      expect(XiaouLoadFailure.fromErrors([error]), XiaouLoadFailure.connection);
    }
    for (final error in [
      const ApiRequestException(403),
      const ApiRequestException(428),
      const ApiRequestException(500),
      const FormatException('synthetic malformed JSON'),
      Exception('401 in arbitrary text is not authentication evidence'),
    ]) {
      expect(XiaouLoadFailure.fromErrors([error]), XiaouLoadFailure.other);
    }
    expect(XiaouLoadFailure.fromErrors([]), isNull);
  });

  test(
    'Chinese and English auth notices preserve account and local content',
    () {
      final zh = lookupAppLocalizations(const Locale('zh'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(XiaouLoadFailure.authentication.message(zh), contains('原账号'));
      expect(
        XiaouLoadFailure.authentication.message(zh),
        contains('本地阅读内容已保留'),
      );
      expect(
        XiaouLoadFailure.authentication.message(en),
        contains('same account'),
      );
      expect(XiaouLoadFailure.authentication.icon, Icons.lock_outline);
      expect(XiaouLoadFailure.connection.icon, Icons.cloud_off_outlined);
      expect(XiaouLoadFailure.other.icon, Icons.info_outline);
      expect(
        XiaouLoadFailure.authentication.message(zh),
        isNot(zh.xiaouLoadRetained),
      );
    },
  );
}
