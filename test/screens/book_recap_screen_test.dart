import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/book_recap_screen.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_material_catalog.dart';
import 'package:ai_reader/services/privacy_service.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import '../support/recap_display_fixture.dart';
import '../services/book_recap_client_test.dart' as base;

void main() {
  late RecapDisplayFixture f;
  late RouteObserver<ModalRoute<void>> observer;
  late GlobalKey<NavigatorState> navigator;
  bool consent = true;
  Future<bool> Function(BuildContext)? customGate;
  setUp(() async {
    f = RecapDisplayFixture();
    await f.init();
    observer = RouteObserver<ModalRoute<void>>();
    navigator = GlobalKey<NavigatorState>();
    consent = true;
    customGate = null;
  });
  tearDown(() async => f.dispose());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 35)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    bool dark = false,
    double safeBottom = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = BookRecapWorkspace(
      session: f.session,
      api: f.api,
      catalog: BookRecapMaterialCatalog(() async => f.db),
      guard: f.guard,
      online: f.online,
      localChanges: ReadingSourceChanges.changes,
      displayLifetime: const Duration(seconds: 20),
      approvedPolicies: {'isolated-v1'},
      consentGate: customGate ?? (_) async => consent,
      routeObserver: observer,
      monotonic: () => f.elapsed,
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(bottom: safeBottom),
            viewPadding: EdgeInsets.only(bottom: safeBottom),
          ),
          child: child!,
        ),
        theme: dark ? ThemeData.dark() : AppTheme.forTheme(AppThemeId.babyBlue),
        home: Scaffold(body: BookRecapEntry(workspace: workspace)),
      ),
    );
    await tester.tap(find.text('阅读回望'));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    if (find.text(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(label),
        250,
        maxScrolls: 40,
        scrollable: find.byType(Scrollable).first,
      );
    }
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> prepare(WidgetTester tester) async {
    await tap(tester, '条件与证据');
    await tester.tap(find.byKey(const ValueKey('material-local-a')));
    await tester.pump();
    await tap(tester, '确认所选材料');
    expect(find.text('已核验 1 条阅读记录、0 条追问。'), findsOneWidget);
  }

  Future<void> generate(WidgetTester tester) async {
    await prepare(tester);
    await tap(tester, '生成回望');
    expect(find.text('知识整理'), findsOneWidget);
    expect(find.text('检验是必要条件，不能据此断言结论必然成立。'), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  testWidgets(
    'real components: select, generate, evidence, follow-up, save, restore, feedback and delete',
    (tester) async {
      await mount(tester);
      await generate(tester);
      await tester.ensureVisible(find.text('查看依据').first);
      await tester.tap(find.text('查看依据').first);
      await settle(tester);
      expect(find.text('原文上下文'), findsOneWidget);
      expect(find.text('当前只能核对已保存的片段，无法保证精确跳转到原书。'), findsOneWidget);
      await tap(tester, '返回回望');
      await tap(tester, '继续追问');
      await tester.enterText(
        find.byKey(const Key('recap-question')),
        '那么需要什么额外证据？',
      );
      await tap(tester, '发送追问');
      expect(find.text('那么需要什么额外证据？'), findsOneWidget);
      expect(find.text('目前证据只说明必要性，并未保证结果。'), findsOneWidget);
      await tap(tester, '返回回望');
      await tap(tester, '保存回望');
      expect(f.current['is_saved'], isTrue);
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('我的回望'));
      await settle(tester);
      expect(find.text('已保存'), findsOneWidget);
      await tester.tap(find.byType(ListTile).first);
      await settle(tester);
      expect(find.text('确认阅读范围'), findsOneWidget);
      expect(find.text('检验是必要条件，不能据此断言结论必然成立。'), findsNothing);
      await tap(tester, '核验并查看回望');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      await tap(tester, '反馈');
      await tap(tester, '提交私有反馈');
      expect(find.text('反馈已保存，仅对当前账号可见。'), findsOneWidget);
      await tap(tester, '删除回望');
      expect(f.deleted, isFalse);
      await tap(tester, '确认删除');
      expect(f.deleted, isTrue);
      expect(find.text('还没有回望。'), findsOneWidget);
      expect(
        (await tester.runAsync(() => f.db.query('user_entries')))!.length,
        1,
      );
      expect(
        f.requests.every((r) => !r.url.path.contains('conversations')),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'pending material cannot authorize generation; six-line preview preserves expandable full text',
    (tester) async {
      final longText = List.filled(25, '这是一段需要保留的长原文。').join();
      await tester.runAsync(
        () => f.db.update('user_entries', {
          'original_text': longText,
          'bmob_id': null,
        }),
      );
      await mount(tester);
      await tap(tester, '条件与证据');
      expect(find.text(longText), findsOneWidget);
      final checkbox = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('material-local-a')),
      );
      expect(checkbox.onChanged, isNull);
      expect(f.requests.any((r) => r.url.path.endsWith('/prepare')), isFalse);
      // UI refinement explicitly approves a six-line preview, not shortened data.
      expect(tester.widget<Text>(find.text(longText)).maxLines, 6);
      await tap(tester, '展开原文');
      expect(find.text(longText), findsOneWidget);
      expect(tester.widget<Text>(find.text(longText)).maxLines, isNull);
      await tap(tester, '收起原文');
      expect(tester.widget<Text>(find.text(longText)).maxLines, 6);
      await unmount(tester);
    },
  );

  testWidgets(
    'source commit, offline, consent withdrawal and background remove private subtree',
    (tester) async {
      await mount(tester);
      await generate(tester);
      ReadingSourceChanges.committed();
      await tester.pump();
      expect(find.text('检验是必要条件，不能据此断言结论必然成立。'), findsNothing);
      await tap(tester, '重新核验正文');
      f.online.value = false;
      await tester.pump();
      expect(find.text('知识整理'), findsNothing);
      f.online.value = true;
      await tester.pump();
      await tap(tester, '重新核验正文');
      PrivacyService.aiConsentChanges.value++;
      await tester.pump();
      expect(find.text('知识整理'), findsNothing);
      await tap(tester, '重新核验正文');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('知识整理'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('知识整理'), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'display expiration hides actual widgets without automatic polling',
    (tester) async {
      await mount(tester);
      await generate(tester);
      final count = f.requests.length;
      f.elapsed = const Duration(seconds: 21);
      await tester.pump(const Duration(seconds: 21));
      expect(find.text('知识整理'), findsNothing);
      expect(f.requests.length, count);
      await tap(tester, '重新核验正文');
      expect(find.text('知识整理'), findsOneWidget);
      await unmount(tester);
    },
  );

  testWidgets('A-B-A late generated result never appears', (tester) async {
    await mount(tester);
    await prepare(tester);
    f.heldAction = 'generate';
    f.hold = Completer<void>();
    await tester.ensureVisible(find.text('生成回望'));
    await tester.tap(find.text('生成回望'));
    await settle(tester);
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish('different-owner', 'test');
    AuthSessionScope.beginTransition();
    AuthSessionScope.publish(base.owner, 'synthetic-token');
    f.hold!.complete();
    await settle(tester);
    expect(find.text('知识整理'), findsNothing);
    expect(find.text('登录状态已变化，请返回后重新进入。'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets(
    'cancel during generation remains fenced against late completion',
    (tester) async {
      await mount(tester);
      await prepare(tester);
      f.heldAction = 'generate';
      f.hold = Completer<void>();
      await tester.ensureVisible(find.text('生成回望'));
      await tester.tap(find.text('生成回望'));
      await settle(tester);
      await tap(tester, '取消生成');
      f.hold!.complete();
      await settle(tester);
      expect(find.text('知识整理'), findsNothing);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/generate')).length,
        1,
      );
      expect(f.requests.where((r) => r.url.path.endsWith('/cancel')).length, 1);
      await unmount(tester);
    },
  );

  testWidgets(
    'history recovery without exact local identity remains body-free',
    (tester) async {
      await tester.runAsync(() => f.db.delete('user_entries'));
      await mount(tester);
      await tester.tap(find.byTooltip('我的回望'));
      await settle(tester);
      await tester.tap(find.byType(ListTile).first);
      await settle(tester);
      expect(find.textContaining('本机缺少可核验'), findsOneWidget);
      expect(f.requests.any((r) => r.url.path.endsWith('/view')), isFalse);
      await tester.tap(find.byTooltip('删除回望'));
      await settle(tester);
      expect(f.deleted, isFalse);
      await tap(tester, '确认删除');
      expect(f.deleted, isTrue);
      await unmount(tester);
    },
  );

  testWidgets('small screen large text and route overlay do not retain prose', (
    tester,
  ) async {
    await mount(tester, size: const Size(320, 640), textScale: 1.4);
    await generate(tester);
    expect(tester.takeException(), isNull);
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('合成覆盖页面')),
      ),
    );
    await settle(tester);
    navigator.currentState!.pop();
    await settle(tester);
    expect(find.text('知识整理'), findsNothing);
    await unmount(tester);
  });

  testWidgets(
    'dark small screen at 200 percent keeps primary actions reachable',
    (tester) async {
      await mount(tester, size: const Size(320, 640), textScale: 2, dark: true);
      await generate(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, '保存回望');
      expect(f.current['is_saved'], isTrue);
      await tap(tester, '继续追问');
      await tester.enterText(
        find.byKey(const Key('recap-question')),
        '证据支持什么？',
      );
      await tap(tester, '发送追问');
      expect(find.text('证据支持什么？'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets(
    'inline deletion confirmation can be dismissed without deleting or hiding valid body',
    (tester) async {
      await mount(tester, size: const Size(320, 640));
      await generate(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pump();
      await tester.pump();
      expect(find.text('删除回望').hitTestable(), findsOneWidget);
      await tap(tester, '删除回望');
      expect(f.deleted, isFalse);
      await tap(tester, '保留回望');
      expect(find.text('确认删除'), findsNothing);
      expect(f.deleted, isFalse);
      expect(find.text('检验是必要条件，不能据此断言结论必然成立。'), findsOneWidget);
      expect(f.requests.any((r) => r.method == 'DELETE'), isFalse);
      await unmount(tester);
    },
  );

  testWidgets(
    'bottom actions respect home indicator and selected materials remain interactive',
    (tester) async {
      await mount(tester, size: const Size(320, 640), safeBottom: 34);
      await tap(tester, '条件与证据');
      final checkbox = find.byKey(const ValueKey('material-local-a'));
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      final confirm = find.widgetWithText(FilledButton, '确认所选材料');
      expect(tester.getRect(confirm).bottom, lessThanOrEqualTo(606));
      expect(confirm.hitTestable(), findsOneWidget);
      await tap(tester, '确认所选材料');
      final generate = find.widgetWithText(FilledButton, '生成回望');
      expect(tester.getRect(generate).bottom, lessThanOrEqualTo(606));
      expect(generate.hitTestable(), findsOneWidget);
      await tap(tester, '生成回望');
      await tap(tester, '保存回望');
      expect(f.current['is_saved'], isTrue);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, '继续追问')).bottom,
        lessThanOrEqualTo(606),
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    },
  );

  testWidgets('consent refusal sends neither prepare nor model request', (
    tester,
  ) async {
    consent = false;
    await mount(tester);
    await tap(tester, '条件与证据');
    await tester.tap(find.byKey(const ValueKey('material-local-a')));
    await tester.pump();
    await tap(tester, '确认所选材料');
    expect(find.text('请先确认本次云端 AI 分析授权。'), findsOneWidget);
    expect(f.requests, isEmpty);
    await unmount(tester);
  });

  testWidgets(
    'consent dialog cannot resume a revoked selection; explicit reselection succeeds',
    (tester) async {
      var accepted = false;
      customGate = (context) async {
        if (accepted) return true;
        PrivacyService.aiConsentChanges.value++;
        accepted =
            await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const Text('合成授权确认'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('确认授权'),
                  ),
                ],
              ),
            ) ??
            false;
        return accepted;
      };
      await mount(tester);
      await tap(tester, '条件与证据');
      await tester.tap(find.byKey(const ValueKey('material-local-a')));
      await tester.pump();
      await tap(tester, '确认所选材料');
      await tap(tester, '确认授权');
      expect(f.requests, isEmpty);
      expect(find.text('授权已确认，请重新选择并核验本次材料。'), findsOneWidget);
      await tap(tester, '刷新材料');
      await tester.tap(find.byKey(const ValueKey('material-local-a')));
      await tester.pump();
      await tap(tester, '确认所选材料');
      expect(find.text('确认阅读范围'), findsOneWidget);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/prepare')).length,
        1,
      );
      await unmount(tester);
    },
  );

  testWidgets('empty validated result never manufactures discoveries', (
    tester,
  ) async {
    f.emptyResult = true;
    await mount(tester);
    await prepare(tester);
    await tap(tester, '生成回望');
    expect(find.text('知识整理'), findsOneWidget);
    expect(find.text('我的思考'), findsOneWidget);
    expect(find.text('继续思考'), findsNothing);
    expect(find.text('当前材料不足以形成可靠整理。'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  testWidgets(
    'pagination deduplicates changing pages and retains no private list body',
    (tester) async {
      f.paginated = true;
      await mount(tester);
      await tester.tap(find.byTooltip('我的回望'));
      await settle(tester);
      await tap(tester, '加载更多');
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('加载更多'), findsNothing);
      expect(find.text('检验是必要条件，不能据此断言结论必然成立。'), findsNothing);
      final requests = f.requests
          .where((r) => r.url.path.endsWith('/history'))
          .toList();
      expect(requests.length, 2);
      expect(jsonDecode(requests.last.body)['cursor'], 'synthetic-next-page');
      await unmount(tester);
    },
  );

  testWidgets(
    'generation transport failure recovers by exact request replay without duplicate click',
    (tester) async {
      await mount(tester);
      await prepare(tester);
      f.heldAction = 'generate';
      f.hold = Completer<void>();
      await tester.ensureVisible(find.text('生成回望'));
      await tester.tap(find.text('生成回望'));
      await settle(tester);
      f.failNext = true;
      f.hold!.complete();
      await settle(tester);
      expect(find.text('知识整理'), findsNothing);
      await tap(tester, '查询上次请求');
      expect(find.text('知识整理'), findsOneWidget);
      final requests = f.requests
          .where((r) => r.url.path.endsWith('/generate'))
          .toList();
      expect(requests.length, 2);
      expect(requests.first.body, requests.last.body);
      await unmount(tester);
    },
  );
}
