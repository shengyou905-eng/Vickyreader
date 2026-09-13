import 'dart:async';

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/apple_auth_service.dart';
import '../services/book_service.dart';
import '../services/sync_service.dart';
import '../services/reliable_upload_service.dart';
import '../config/local_diagnostics_mode.dart';

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
    if (LocalDiagnosticsMode.enabled) return;
    await AuthService.init();
    if (AuthService.isLoggedIn && AuthService.userId?.isNotEmpty == true) {
      await ReliableUploadService.instance.claimAnonymousOperations(
        AuthService.userId!,
      );
      ReliableUploadService.instance.start();
      unawaited(BookService.enqueueReliableUploadSnapshot());
    }
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
    ReliableUploadService.instance.stop();
    await AuthService.signOut();
    _error = null;
    notifyListeners();
  }

  Future<bool> signInWithApple() => _runAppleAuth(bind: false);

  Future<bool> bindApple() => _runAppleAuth(bind: true);

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
    if (LocalDiagnosticsMode.enabled) return;
    final userId = AuthService.userId;
    if (userId == null || userId.isEmpty) return;
    await ReliableUploadService.instance.claimAnonymousOperations(userId);
    ReliableUploadService.instance.start();

    try {
      SyncService.instance.setUserId(userId);
      await SyncService.instance.mergeAnonymousData(userId);
      await BookService.syncFreeNotes();
      await SyncService.instance.pullAll();
    } catch (_) {
      // 登录不能被同步问题卡住；随心记页面进入时还会再次尝试同步。
    }

    // MCP uses a deliberately separate, metadata-only bookshelf mirror.
    // Keep it independent from the older sync flow so a transient failure in
    // either path cannot prevent the other one from completing.
    try {
      await BookService.enqueueReliableUploadSnapshot();
    } catch (_) {
      // MCP stays opt-in and can retry from Settings without affecting login.
    }
  }
}
