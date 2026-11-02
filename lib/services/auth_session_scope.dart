import 'package:flutter/foundation.dart';
import '../config/constants.dart';

class StaleAuthSession implements Exception {
  const StaleAuthSession();
  @override
  String toString() => 'Account session changed';
}

/// In-memory identity fence. An A -> B -> A transition never revives old work.
class AuthSessionScope {
  static final ValueNotifier<int> changes = ValueNotifier(0);
  static String? _userId;
  static String? _token;
  static bool _transitioning = false;
  static bool _initialized = false;
  static bool get initialized => _initialized;

  final String? userId;
  final int epoch;
  final String origin;

  AuthSessionScope._(this.userId, this.epoch, this.origin);

  static AuthSessionScope capture() =>
      AuthSessionScope._(_userId, changes.value, AppConstants.apiBaseUrl);

  static void beginTransition() {
    _transitioning = true;
    changes.value++;
  }

  static void publish(String? userId, String? token) {
    _initialized = true;
    final normalized = userId?.trim();
    final owner = normalized == null || normalized.isEmpty ? null : normalized;
    final changed = _transitioning || owner != _userId || token != _token;
    _userId = owner;
    _token = token;
    _transitioning = false;
    if (changed) changes.value++;
  }

  bool get isCurrent =>
      !_transitioning &&
      epoch == changes.value &&
      userId == _userId &&
      origin == AppConstants.apiBaseUrl;

  void check() {
    if (!isCurrent) throw const StaleAuthSession();
  }

  String requireOwner() {
    check();
    if (userId == null) throw StateError('Please sign in');
    return userId!;
  }
}
