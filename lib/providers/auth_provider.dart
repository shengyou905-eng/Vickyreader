import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
}
