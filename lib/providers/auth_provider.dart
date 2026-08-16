import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/apple_auth_service.dart';
import '../services/book_service.dart';
import '../services/sync_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  bool get isLoggedIn => AuthService.isLoggedIn;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get userId => AuthService.userId;
  String? get email => AuthService.email;
  bool get hasPassword => AuthService.hasPassword;
  bool get appleLinked => AuthService.appleLinked;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    await AuthService.init();
    notifyListeners();
  }

  Future<bool> signUp(String email, String password) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await AuthService.signUp(email, password);
      if (res != null && res.containsKey('error')) {
        _error = res['error'] as String;
        _isLoading = false;
        notifyListeners();
        return false;
      }
      unawaited(_afterAuthSuccess());
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn(String email, String password) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      final res = await AuthService.signIn(email, password);
      if (res != null && res.containsKey('error')) {
        _error = res['error'] as String;
        _isLoading = false;
        notifyListeners();
        return false;
      }
      unawaited(_afterAuthSuccess());
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await AuthService.signOut();
    _error = null;
    notifyListeners();
  }

  Future<bool> signInWithApple() async {
    return _runAppleAuth(bind: false);
  }

  Future<bool> bindApple() async {
    return _runAppleAuth(bind: true);
  }

  Future<bool> _runAppleAuth({required bool bind}) async {
    _error = null;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await AppleAuthService.authorize(bind: bind);
      _isLoading = false;
      if (result.status == AppleAuthStatus.success) {
        if (!bind) unawaited(_afterAuthSuccess());
        notifyListeners();
        return true;
      }
      if (result.status == AppleAuthStatus.unavailable) {
        _error = '当前设备不支持 Apple 登录';
      }
      notifyListeners();
      return false;
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> _afterAuthSuccess() async {
    final userId = AuthService.userId;
    if (userId == null || userId.isEmpty) return;

    try {
      SyncService.instance.setUserId(userId);
      await SyncService.instance.mergeAnonymousData(userId);
      await BookService.syncFreeNotes();
      await SyncService.instance.pullAll();
    } catch (_) {
      // 登录不能被同步问题卡住；随心记页面进入时还会再次尝试同步。
    }
  }
}
