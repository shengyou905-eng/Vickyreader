import 'auth_session_scope.dart';
import 'book_recap_client_api.dart';
import 'book_recap_client_contract.dart';
import 'book_recap_display_contract.dart';

/// Session-bound metadata access. No private-body cache, endpoint or login default.
class BookRecapDisplayRepository {
  final BookRecapClientApi api;
  final AuthSessionScope session;
  BookRecapDisplayRepository({required this.api, required this.session});

  void _checkSession() {
    try {
      session.check();
      if (session.userId == null) recapReject('RECAP_AUTH_REQUIRED');
    } on StaleAuthSession {
      recapReject('AUTH_CHANGED');
    }
  }

  Future<T> _request<T>(
    String method,
    String relative,
    T Function(Map<String, dynamic>) parse, {
    Map<String, dynamic>? body,
    RecapRequestAbort? abort,
  }) async {
    _checkSession();
    try {
      final data = await api.send(
        session,
        method,
        relative,
        body: body,
        abort: abort,
      );
      _checkSession();
      if (abort?.cancelled == true) recapReject('CANCELLED');
      final result = parse(data);
      _checkSession();
      return result;
    } on StaleAuthSession {
      recapReject('AUTH_CHANGED');
    } catch (_) {
      _checkSession();
      rethrow;
    }
  }

  Future<RecapHistoryPage> history({
    int limit = 20,
    RecapHistoryFilter filter = RecapHistoryFilter.all,
    String? cursor,
    RecapRequestAbort? abort,
  }) {
    if (limit < 1 ||
        limit > 50 ||
        (cursor != null && (cursor.isEmpty || cursor.length > 2048))) {
      recapReject('INVALID_REQUEST');
    }
    return _request(
      'POST',
      'display/history',
      (value) {
        final page = RecapHistoryPage.parse(value);
        if (page.items.length > limit ||
            page.items.any(
              (item) =>
                  (filter == RecapHistoryFilter.saved && !item.isSaved) ||
                  (filter == RecapHistoryFilter.preview && item.isSaved),
            )) {
          recapReject();
        }
        return page;
      },
      body: {'limit': limit, 'filter': filter.name, 'cursor': ?cursor},
      abort: abort,
    );
  }

  Future<RecapRecoveredScope> scope(String id, {RecapRequestAbort? abort}) {
    recapId(id);
    return _request(
      'POST',
      'display/$id/scope',
      (value) {
        final scope = RecapRecoveredScope.parse(value);
        if (scope.header.id != id) recapReject('RECAP_REVISION_CONFLICT');
        return scope;
      },
      body: {},
      abort: abort,
    );
  }

  /// Privacy deletion does not depend on a local book or recovered sources.
  Future<void> delete(String id, {RecapRequestAbort? abort}) {
    recapId(id);
    return _request<void>('DELETE', id, (_) {}, abort: abort);
  }
}
