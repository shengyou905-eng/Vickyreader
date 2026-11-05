import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';
import '../../services/auth_session_scope.dart';
import '../../services/book_recap_client_api.dart';
import '../../services/book_recap_client_contract.dart';
import '../../services/book_recap_local_guard.dart';
import '../../services/book_recap_material_catalog.dart';
import '../../services/database_service.dart';
import '../../services/reading_source_changes.dart';
import '../../services/privacy_service.dart';
import '../../utils/ai_consent_gate.dart';
import 'book_recap_screen.dart';

final recapPilotRoutes = RouteObserver<ModalRoute<void>>();
const _policy = recapDisplayPolicy;

// Shared with the pushed route even when the sliver containing its entry is
// recycled. Only path availability is retained; never tokens or private text.
final _path = ValueNotifier(false);
StreamSubscription<dynamic>? _monitor;
void _monitorPath() {
  _monitor ??= const EventChannel('zhidu/recap_network_path')
      .receiveBroadcastStream()
      .listen(
        (v) => _path.value = v == true,
        onError: (Object _) => _path.value = false,
        onDone: () {
          _path.value = false;
          _monitor = null;
        },
      );
}

class RecapPilotEntry extends StatefulWidget {
  final bool isActive;
  final int refreshSignal;
  const RecapPilotEntry({
    super.key,
    this.isActive = true,
    this.refreshSignal = 0,
  });
  @override
  State<RecapPilotEntry> createState() => _RecapPilotEntryState();
}

class _RecapPilotEntryState extends State<RecapPilotEntry>
    with WidgetsBindingObserver {
  BookRecapWorkspace? workspace;
  RecapRequestAbort? discoveryAbort;
  RecapRequestAbort? openAbort;
  int discoveryEpoch = 0;
  bool foreground = true;
  bool checking = false;

  bool get available => widget.isActive && foreground && _path.value;

  Future<bool> _beforeOpen(BookRecapWorkspace w) async {
    if (checking || !w.session.isCurrent || !available) return false;
    checking = true;
    final abort = RecapRequestAbort();
    openAbort = abort;
    try {
      final cap = await w.api.send(
        w.session,
        'GET',
        'capability',
        abort: abort,
      );
      if (mounted &&
          w.session.isCurrent &&
          available &&
          identical(workspace, w) &&
          cap['enabled'] == true &&
          cap['policy_version'] == _policy) {
        return true;
      }
    } catch (_) {
      // A previous capability response is never an authorization fallback.
    } finally {
      if (identical(openAbort, abort)) checking = false;
    }
    if (mounted && identical(workspace, w)) {
      setState(() => workspace = null);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('暂时无法打开阅读回望，请检查网络与账号权限。')));
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    AuthSessionScope.changes.addListener(_refresh);
    PrivacyService.aiConsentChanges.addListener(_refresh);
    _path.addListener(_refresh);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _monitorPath();
      unawaited(_discover());
    }
  }

  void _refresh() => unawaited(_discover());

  @override
  void didUpdateWidget(covariant RecapPilotEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive ||
        oldWidget.refreshSignal != widget.refreshSignal) {
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _refresh();
  }

  Future<void> _discover() async {
    final epoch = ++discoveryEpoch;
    discoveryAbort?.cancel();
    discoveryAbort = null;
    openAbort?.cancel();
    openAbort = null;
    checking = false;
    if (mounted) setState(() => workspace = null);
    if (!mounted ||
        !available ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    final session = AuthSessionScope.capture();
    if (!session.isCurrent || session.userId == null) return;
    final abort = RecapRequestAbort();
    discoveryAbort = abort;
    try {
      final api = BookRecapClientApi(
        baseUri: Uri.parse('${session.origin}/api/recaps'),
        enabled: true,
        clientFactory: http.Client.new,
        tokenProvider: (scope) =>
            scope.isCurrent && AuthService.userId == scope.userId
            ? AuthService.token
            : null,
      );
      final capability = await api.send(
        session,
        'GET',
        'capability',
        abort: abort,
      );
      if (!mounted ||
          epoch != discoveryEpoch ||
          !available ||
          !session.isCurrent ||
          capability['enabled'] != true ||
          capability['policy_version'] != _policy) {
        return;
      }
      setState(
        () => workspace = BookRecapWorkspace(
          session: session,
          api: api,
          catalog: BookRecapMaterialCatalog(() => DatabaseService.database),
          guard: BookRecapLocalGuard(() => DatabaseService.database),
          online: _path,
          localChanges: ReadingSourceChanges.changes,
          displayLifetime: const Duration(seconds: 60),
          approvedPolicies: const {_policy},
          consentGate: AiConsentGate.ensure,
          routeObserver: recapPilotRoutes,
        ),
      );
    } catch (_) {
      // Old server, expired session, disabled pilot, or offline: no entry.
    }
  }

  @override
  void dispose() {
    discoveryEpoch++;
    discoveryAbort?.cancel();
    openAbort?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AuthSessionScope.changes.removeListener(_refresh);
    PrivacyService.aiConsentChanges.removeListener(_refresh);
    _path.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = workspace;
    if (w == null || !w.session.isCurrent || !available) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<bool>(
      valueListenable: _path,
      builder: (_, online, _) => online && w.session.isCurrent
          ? BookRecapEntry(workspace: w, checkAccess: () => _beforeOpen(w))
          : const SizedBox.shrink(),
    );
  }
}
