import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../l10n/l10n.dart';
import '../../services/api_request_exception.dart';

enum XiaouLoadFailure {
  authentication,
  connection,
  other;

  static XiaouLoadFailure? fromErrors(Iterable<Object> errors) {
    if (errors.isEmpty) return null;
    // Both home requests run concurrently; authentication must not depend on
    // which failure arrives first.
    if (errors.any((e) => e is ApiRequestException && e.statusCode == 401)) {
      return authentication;
    }
    if (errors.every(
      (e) =>
          e is TimeoutException ||
          e is SocketException ||
          e is http.ClientException,
    )) {
      return connection;
    }
    return other;
  }

  String message(AppLocalizations l10n) => switch (this) {
    authentication => l10n.xiaouLoadSignInRequired,
    connection => l10n.xiaouLoadConnectionFailed,
    other => l10n.xiaouLoadRetained,
  };

  IconData get icon => switch (this) {
    authentication => Icons.lock_outline,
    connection => Icons.cloud_off_outlined,
    other => Icons.info_outline,
  };
}
