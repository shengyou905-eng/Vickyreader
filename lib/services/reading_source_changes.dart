import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Process-local invalidation only: no source content or account identity.
/// Consumers must still fence account changes with AuthSessionScope.
abstract final class ReadingSourceChanges {
  static final _SourceChangeNotifier _notifier = _SourceChangeNotifier();
  static Listenable get changes => _notifier;

  /// Call only after a standalone write or the OUTERMOST transaction commits.
  /// A successful no-op may conservatively invalidate all visible recaps.
  static void committed() => _notifier.committed();

  static Future<T> afterCommit<T>(Future<T> commit) async {
    final result = await commit;
    committed();
    return result;
  }
}

class _SourceChangeNotifier extends ChangeNotifier {
  void committed() => notifyListeners();
}

extension ReadingSourceTransaction on Database {
  /// Never notify from an enqueue helper that receives a Transaction executor:
  /// its statements can succeed even when the enclosing transaction rolls back.
  Future<T> readingSourceTransaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => ReadingSourceChanges.afterCommit(
    transaction(action, exclusive: exclusive),
  );
}
