import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_session_scope.dart';
import 'book_recap_client_contract.dart';

class RecapRequestAbort {
  final Completer<void> _done = Completer<void>();
  bool get cancelled => _done.isCompleted;
  void cancel() {
    if (!cancelled) _done.complete();
  }
}

/// No implicit endpoint or singleton. Pilot availability is enforced on the server.
class BookRecapClientApi {
  final Uri baseUri;
  final http.Client Function() clientFactory;
  final String? Function(AuthSessionScope) tokenProvider;
  final bool enabled;
  final bool loopbackTest;
  final Duration timeout;

  BookRecapClientApi({
    required this.baseUri,
    required this.clientFactory,
    required this.tokenProvider,
    this.enabled = false,
    this.loopbackTest = false,
    this.timeout = const Duration(seconds: 100),
  }) {
    final local = ['127.0.0.1', '::1'].contains(baseUri.host);
    if (baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.scheme != 'https' &&
            !(loopbackTest && local && baseUri.scheme == 'http')) ||
        (loopbackTest && !local) ||
        timeout <= Duration.zero) {
      recapReject('NOT_CONFIGURED');
    }
  }

  Future<Map<String, dynamic>> send(
    AuthSessionScope scope,
    String method,
    String relative, {
    Map<String, dynamic>? body,
    RecapRequestAbort? abort,
  }) async {
    if (!enabled) recapReject('NOT_CONFIGURED');
    scope.requireOwner();
    if (!loopbackTest && Uri.parse(scope.origin).origin != baseUri.origin) {
      recapReject('AUTH_CHANGED');
    }
    if (!RegExp(
          r'^(capability|prepare|display/history|display/[a-f0-9-]{36}/(scope|view|evidence|validate)|[a-f0-9-]{36}(/(generate|save|feedback|follow-ups|operations/[a-f0-9-]{36}/cancel))?)$',
        ).hasMatch(relative) ||
        !['GET', 'POST', 'DELETE'].contains(method)) {
      recapReject('INVALID_REQUEST');
    }
    if (relative.startsWith('display/') && method != 'POST') {
      recapReject('INVALID_REQUEST');
    }
    final token = tokenProvider(scope);
    scope.check();
    if (token == null || token.trim().isEmpty) {
      recapReject('RECAP_AUTH_REQUIRED');
    }
    if (abort?.cancelled == true) recapReject('CANCELLED');
    final uri = baseUri.replace(
      path: '${baseUri.path.replaceFirst(RegExp(r'/$'), '')}/$relative',
    );
    final client = clientFactory();
    try {
      Future<Map<String, dynamic>> perform() async {
        final request = http.Request(method, uri)..followRedirects = false;
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
        });
        if (body != null) {
          request.body = jsonEncode(body);
          if (utf8.encode(request.body).length > 80 * 1024) {
            recapReject('RECAP_INPUT_BUDGET');
          }
        }
        final response = await client.send(request);
        final bytes = <int>[];
        await for (final chunk in response.stream) {
          if (abort?.cancelled == true) recapReject('CANCELLED');
          if (bytes.length + chunk.length > 768 * 1024) {
            recapReject('INVALID_RESPONSE');
          }
          bytes.addAll(chunk);
        }
        scope.check();
        if (abort?.cancelled == true) recapReject('CANCELLED');
        if (response.statusCode == 204) return {};
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes));
        } catch (_) {
          recapReject('INVALID_RESPONSE');
        }
        final data = recapObject(decoded);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          if (response.statusCode == 403 &&
              data['error_code'] == 'RECAP_PILOT_DISABLED') {
            recapReject('RECAP_PILOT_DISABLED');
          }
          if (response.statusCode == 401 || response.statusCode == 403) {
            recapReject('RECAP_AUTH_REQUIRED');
          }
          if (response.statusCode == 428) recapReject('AI_CONSENT_REQUIRED');
          final code = data['error_code'];
          recapReject(
            code is String &&
                    RegExp(
                      r'^(RECAP_[A-Z_]+|AI_CONSENT_REQUIRED)$',
                    ).hasMatch(code)
                ? code
                : 'NETWORK',
          );
        }
        return data;
      }

      final response = await Future.any([
        perform(),
        if (abort != null)
          abort._done.future.then<Map<String, dynamic>>(
            (_) => recapReject('CANCELLED'),
          ),
      ]).timeout(timeout);
      scope.check();
      return response;
    } on StaleAuthSession {
      recapReject('AUTH_CHANGED');
    } on TimeoutException {
      recapReject('TIMEOUT');
    } on RecapClientException {
      rethrow;
    } catch (_) {
      recapReject('NETWORK');
    } finally {
      client.close();
    }
  }
}
