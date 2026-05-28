import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
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
