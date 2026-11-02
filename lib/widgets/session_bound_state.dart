import 'package:flutter/material.dart';
import '../services/auth_session_scope.dart';

/// Private detail views may not retain content across an identity transition.
mixin SessionBoundState<T extends StatefulWidget> on State<T> {
  late final AuthSessionScope sessionScope;
  bool get sessionActive => mounted && sessionScope.isCurrent;

  @override
  void initState() {
    super.initState();
    sessionScope = AuthSessionScope.capture();
    AuthSessionScope.changes.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted || sessionScope.isCurrent) return;
    onSessionInvalidated();
    setState(() {});
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          route?.isCurrent == true &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  @protected
  void onSessionInvalidated() {}

  @override
  void dispose() {
    AuthSessionScope.changes.removeListener(_sessionChanged);
    super.dispose();
  }
}
