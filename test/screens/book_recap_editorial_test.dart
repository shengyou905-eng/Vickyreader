import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/book_recap_screen.dart';
import 'package:ai_reader/screens/xiaou/widgets/book_recap_editorial.dart';
import 'package:ai_reader/services/auth_session_scope.dart';
import 'package:ai_reader/services/book_recap_material_catalog.dart';
import 'package:ai_reader/services/privacy_service.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import '../support/recap_editorial_fixture.dart';
import '../services/book_recap_client_test.dart' as base;

class _Preview {
  final RecapEditorialFixture f;
  final boundary = GlobalKey();
  final navigator = GlobalKey<NavigatorState>();
  final observer = RouteObserver<ModalRoute<void>>();
  final scale = ValueNotifier(1.0);
  final keyboard = ValueNotifier(0.0);
  _Preview(this.f);
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 160; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
      if (i >= 14 && find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    fail('Synthetic request did not finish within the bounded UI wait');
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool fonts = false,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (fonts) {
      await tester.runAsync(() async {
        final root = Directory.current.path.endsWith('reliable_upload_tests')
            ? '../..'
            : '.';
        for (final font in [
          (
            'SourceHanSerifCN',
            '$root/assets/fonts/SourceHanSerifCN-Regular.otf',
          ),
          ('LXGWWenKaiLite', '$root/assets/fonts/LXGWWenKaiLite-Regular.ttf'),
          ('RecapVisualChinese', 'C:/Windows/Fonts/msyh.ttc'),
          (
            'MaterialIcons',
            'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ),
        ]) {
          final file = File(font.$2);
          expect(
            await file.exists(),
            isTrue,
            reason: 'Never silently capture missing CJK fonts',
          );
          await (FontLoader(
            font.$1,
          )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
        }
      });
    }
    final workspace = BookRecapWorkspace(
      session: f.session,
      api: f.api,
      catalog: BookRecapMaterialCatalog(() async => f.db),
      guard: f.guard,
      online: f.online,
      localChanges: ReadingSourceChanges.changes,
      displayLifetime: const Duration(seconds: 120),
      approvedPolicies: {'isolated-v1'},
      consentGate: (_) async => true,
      routeObserver: observer,
      monotonic: () => f.elapsed,
    );
    final theme = dark
        ? ThemeData.dark()
        : AppTheme.forTheme(AppThemeId.babyBlue);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          debugShowCheckedModeBanner: false,
          theme: fonts
              ? theme.copyWith(
                  textTheme: theme.textTheme.apply(
                    fontFamily: 'RecapVisualChinese',
                  ),
                )
              : theme,
          builder: (context, child) => ValueListenableBuilder(
            valueListenable: scale,
            builder: (_, factor, _) => ValueListenableBuilder(
              valueListenable: keyboard,
              builder: (_, inset, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(factor),
                  viewInsets: EdgeInsets.only(bottom: inset),
                  padding: const EdgeInsets.only(bottom: 34),
                  viewPadding: const EdgeInsets.only(bottom: 34),
                ),
                child: child!,
              ),
            ),
          ),
          home: Scaffold(body: BookRecapEntry(workspace: workspace)),
        ),
      ),
    );
    debugPrint('editorial flow: mounted');
    await tap(tester, '阅读回望');
    await tap(tester, RecapEditorialFixture.book);
    for (final id in RecapEditorialFixture.localIds) {
      final target = find.byKey(ValueKey('material-$id'));
      if (target.evaluate().isEmpty) {
        await tester.scrollUntilVisible(target, 200, maxScrolls: 30);
      }
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
    }
    debugPrint('editorial flow: selected');
    await tap(tester, '确认所选材料');
    debugPrint('editorial flow: prepared');
    await tap(tester, '生成回望');
    expect(find.text('知识整理'), findsOneWidget);
  }

  Future<void> top(WidgetTester tester) async {
    final scroll = tester.widget<Scrollable>(
      find
          .descendant(
            of: find.byKey(const ValueKey('recap-scroll-detail')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.controller!.jumpTo(0);
    await tester.pump();
  }

  Future<void> section(WidgetTester tester, int index) async {
    await tester.tap(find.byTooltip('章节目录'));
    await tester.pump();
    await tester.tap(find.byKey(ValueKey('recap-toc-$index')));
    await tester.pump();
    await tester.pump();
  }

  Future<void> capture(
    WidgetTester tester,
    Directory output,
    String name, {
    bool full = false,
  }) async {
    await tester.pumpAndSettle();
    final render = full
        ? tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('recap-editorial-article')),
          )
        : boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: 1);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final colors = <int>{};
      for (var i = 0; i < rgba.lengthInBytes; i += 64) {
        colors.add(rgba.getUint32(i));
      }
      expect(colors.length, greaterThan(20));
      expect(image.width, tester.view.physicalSize.width.toInt());
      if (full) expect(image.height, greaterThan(2000));
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await File(
        '${output.path}/$name.png',
      ).writeAsBytes(png.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    scale.dispose();
    keyboard.dispose();
    await tester.runAsync(f.dispose);
  }
}

void main() {
  Future<Directory> interactionOutput(WidgetTester tester) async {
    late Directory directory;
    await tester.runAsync(() async {
      final root = Platform.environment['ZHIDU_RECAP_PORT_ARTIFACTS'];
      directory = root == null
          ? await Directory.systemTemp.createTemp('recap-interaction-')
          : await Directory(
              '$root/../a-v2-interaction/screenshots-${DateTime.now().millisecondsSinceEpoch}',
            ).create(recursive: true);
    });
    return directory;
  }

  testWidgets(
    'evidence return restores verified position and TOC/footer remain usable',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester, fonts: true);
        final output = await interactionOutput(tester);
        await p.capture(tester, output, 'navigation-390');
        expect(find.byTooltip('我的回望'), findsNothing);
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('我的回望').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        await p.section(tester, 1);
        final scroll = tester
            .widget<ListView>(find.byKey(const ValueKey('recap-scroll-detail')))
            .controller!;
        final reference = find.text('查看依据').hitTestable();
        for (var i = 0; i < 12 && reference.evaluate().isEmpty; i++) {
          await tester.drag(
            find.byKey(const ValueKey('recap-scroll-detail')),
            const Offset(0, -180),
          );
          await tester.pumpAndSettle();
        }
        final before = scroll.offset;
        expect(before, greaterThan(300));
        await tester.tap(find.text('查看依据').hitTestable().first);
        await p.settle(tester);
        expect(
          find.byKey(const ValueKey('recap-editorial-article')),
          findsNothing,
        );
        expect(find.text('返回回望'), findsOneWidget);
        await p.capture(tester, output, 'evidence-390');
        await p.tap(tester, '返回回望');
        await tester.pumpAndSettle();
        expect(scroll.offset, closeTo(before, 1));
        await p.capture(tester, output, 'restored-390');
        await p.section(tester, 2);
        expect(find.text('继续思考').hitTestable(), findsOneWidget);
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        final last = tester.getRect(find.text('查看依据').last);
        final footer = tester.getRect(find.text('继续追问'));
        expect(last.bottom, lessThan(footer.top));
        tester.view.physicalSize = const Size(320, 640);
        await p.top(tester);
        await p.capture(tester, output, 'navigation-320');
        p.scale.value = 2;
        await tester.pump();
        await p.capture(tester, output, 'navigation-320-scale200');
        expect(
          tester.getSize(find.byTooltip('章节目录')).width,
          greaterThanOrEqualTo(44),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    },
  );

  for (final event in [
    'failure',
    'consent',
    'source',
    'account',
    'new-version',
    'network',
    'expiry',
  ]) {
    testWidgets('evidence return cannot restore private article after $event', (
      tester,
    ) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester, fonts: event == 'failure');
        await tester.ensureVisible(find.text('查看依据').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看依据').first);
        await p.settle(tester);
        f.hold = Completer<void>();
        f.heldAction = 'view';
        if (event == 'failure') {
          f.alterGrant = (grant) => grant['policy_version'] = 'unapproved';
        }
        final count = f.requests
            .where((r) => r.url.path.endsWith('/view'))
            .length;
        await tester.tap(find.text('返回回望'));
        for (
          var i = 0;
          i < 100 &&
              f.requests.where((r) => r.url.path.endsWith('/view')).length ==
                  count;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          f.requests.where((r) => r.url.path.endsWith('/view')).length,
          count + 1,
        );
        switch (event) {
          case 'consent':
            PrivacyService.aiConsentChanges.value++;
          case 'source':
            ReadingSourceChanges.committed();
          case 'account':
            AuthSessionScope.beginTransition();
            AuthSessionScope.publish('other', 'synthetic-other');
          case 'new-version':
            f.current['revision'] = (int.parse(f.current['revision']) + 1)
                .toString();
          case 'network':
            f.online.value = false;
          case 'expiry':
            f.elapsed = const Duration(minutes: 3);
        }
        f.hold!.complete();
        await p.settle(tester);
        expect(
          find.byKey(const ValueKey('recap-editorial-article')),
          findsNothing,
        );
        expect(find.byType(RecapEditorialQuote), findsNothing);
        if (event == 'failure') {
          await p.capture(
            tester,
            await interactionOutput(tester),
            'authorization-failed-390',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    });
  }

  testWidgets(
    'editorial quote voices remain distinct; question draft is editable and uses recap channel',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester);
        final quotes = tester
            .widgetList<RecapEditorialQuote>(find.byType(RecapEditorialQuote))
            .toList();
        expect(
          quotes.where((q) => q.userVoice).map((q) => q.text),
          contains(RecapEditorialFixture.note),
        );
        expect(
          quotes.where((q) => q.historicalAi).single.text,
          RecapEditorialFixture.oldAnswer,
        );
        expect(find.text('小U整理 · 依据用户表达'), findsNWidgets(2));
        await p.section(tester, 2);
        await tester.ensureVisible(find.byKey(const ValueKey('recap-ask-n1')));
        await tester.tap(find.byKey(const ValueKey('recap-ask-n1')));
        await p.settle(tester);
        final field = find.byKey(const Key('recap-question'));
        expect(
          tester.widget<TextField>(field).controller!.text,
          '最近一次省下时间后，我把注意力交给了什么？',
        );
        expect(
          f.requests.where(
            (r) => r.method == 'POST' && r.url.path.endsWith('/follow-ups'),
          ),
          isEmpty,
        );
        await tester.enterText(field, '我想先核对停顿与理解之间的依据。');
        await p.tap(tester, '发送追问');
        expect(f.turns.single['question'], '我想先核对停顿与理解之间的依据。');
        expect(
          f.requests.every((r) => r.url.path.startsWith('/recaps/')),
          isTrue,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    },
  );

  for (final trigger in [
    'offline',
    'source',
    'consent',
    'expiry',
    'account',
    'background',
  ]) {
    testWidgets(
      'editorial evidence and TOC withdraw on $trigger without retained prose',
      (tester) async {
        final f = RecapEditorialFixture();
        await tester.runAsync(f.init);
        final p = _Preview(f);
        try {
          await p.mount(tester);
          await tester.tap(find.byTooltip('章节目录'));
          await tester.pump();
          expect(find.byKey(const ValueKey('recap-toc-0')), findsOneWidget);
          await tester.tap(find.byTooltip('关闭目录'));
          await tester.pump();
          await tester.ensureVisible(find.text('查看依据').first);
          await tester.pumpAndSettle();
          expect(find.text('查看依据').first.hitTestable(), findsOneWidget);
          await tester.tap(find.text('查看依据').first);
          await p.settle(tester);
          expect(find.text(RecapEditorialFixture.excerpt), findsOneWidget);
          expect(
            find.byKey(const ValueKey('recap-editorial-article')),
            findsNothing,
          );
          switch (trigger) {
            case 'offline':
              f.online.value = false;
            case 'source':
              ReadingSourceChanges.committed();
            case 'consent':
              PrivacyService.aiConsentChanges.value++;
            case 'expiry':
              f.elapsed = const Duration(seconds: 121);
              await tester.pump(const Duration(seconds: 121));
            case 'account':
              AuthSessionScope.beginTransition();
              AuthSessionScope.publish(base.other, 'synthetic-other');
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await tester.pump();
              expect(find.text(RecapEditorialFixture.excerpt), findsNothing);
              // Paused disables frame production. Check the visible transition
              // before it, then verify resume cannot restore the old subtree.
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.paused,
              );
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
          }
          await tester.pump();
          expect(find.text(RecapEditorialFixture.excerpt), findsNothing);
          expect(find.byType(RecapEditorialQuote), findsNothing);
          expect(find.byTooltip('关闭依据'), findsNothing);
          expect(find.byKey(const ValueKey('recap-toc-0')), findsNothing);
          expect(find.byKey(const Key('recap-question')), findsNothing);
          if (trigger == 'background') {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          expect(tester.takeException(), isNull);
        } finally {
          await p.dispose(tester);
        }
      },
    );
  }

  testWidgets(
    'open TOC expires with article and Escape closes it without a new route',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester);
        final before = f.requests.length;
        await tester.tap(find.byTooltip('章节目录'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(find.byKey(const ValueKey('recap-toc-0')), findsNothing);
        expect(
          find.byKey(const ValueKey('recap-editorial-article')),
          findsOneWidget,
        );
        expect(f.requests.length, before);
        await tester.tap(find.byTooltip('章节目录'));
        await tester.pump();
        f.elapsed = const Duration(seconds: 121);
        await tester.pump(const Duration(seconds: 121));
        expect(find.byKey(const ValueKey('recap-toc-0')), findsNothing);
        expect(
          find.byKey(const ValueKey('recap-editorial-article')),
          findsNothing,
        );
        expect(find.text(RecapEditorialFixture.note), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    },
  );

  testWidgets(
    'late question preparation after consent revocation never restores draft',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester);
        await p.section(tester, 2);
        f.heldAction = 'follow-ups';
        f.hold = Completer<void>();
        final target = find.byKey(const ValueKey('recap-ask-n1'));
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        for (
          var i = 0;
          i < 20 && !f.requests.any((r) => r.url.path.endsWith('/follow-ups'));
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(
          f.requests.any((r) => r.url.path.endsWith('/follow-ups')),
          isTrue,
        );
        PrivacyService.aiConsentChanges.value++;
        await tester.pump();
        f.hold!.complete();
        await p.settle(tester);
        expect(find.byKey(const Key('recap-question')), findsNothing);
        expect(find.text('最近一次省下时间后，我把注意力交给了什么？'), findsNothing);
        expect(f.turns, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    },
  );

  testWidgets(
    'late evidence after route exit cannot resurrect sheet or article',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      try {
        await p.mount(tester);
        f.heldAction = 'evidence';
        f.hold = Completer<void>();
        await tester.ensureVisible(find.text('查看依据').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看依据').first);
        for (
          var i = 0;
          i < 25 && !f.requests.any((r) => r.url.path.endsWith('/evidence'));
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(f.requests.any((r) => r.url.path.endsWith('/evidence')), isTrue);
        expect(
          find.byKey(const ValueKey('recap-editorial-article')),
          findsNothing,
        );
        p.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        f.hold!.complete();
        await p.settle(tester);
        expect(find.byType(RecapEditorialQuote), findsNothing);
        expect(find.text(RecapEditorialFixture.excerpt), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await p.dispose(tester);
      }
    },
  );

  testWidgets(
    'native editorial visual review at both widths, large text, sheets and withdrawal',
    (tester) async {
      final f = RecapEditorialFixture();
      await tester.runAsync(f.init);
      final p = _Preview(f);
      late Directory output;
      await tester.runAsync(() async {
        final root = Platform.environment['ZHIDU_RECAP_PORT_ARTIFACTS'];
        output = root == null
            ? await Directory.systemTemp.createTemp('zhidu-recap-a-v2-flutter-')
            : await Directory(
                '$root/screenshots-${DateTime.now().millisecondsSinceEpoch}',
              ).create(recursive: true);
      });
      try {
        await p.mount(tester, fonts: true);
        for (final size in [const Size(390, 844), const Size(320, 640)]) {
          tester.view.physicalSize = size;
          await tester.pump();
          await p.top(tester);
          final width = size.width.toInt();
          await p.capture(tester, output, 'flutter-$width');
          await p.capture(tester, output, 'flutter-$width-full', full: true);
          expect(tester.takeException(), isNull);
        }
        tester.view.physicalSize = const Size(390, 844);
        await tester.pump();
        await tester.tap(find.byTooltip('章节目录'));
        await tester.pump();
        await p.capture(tester, output, 'flutter-390-contents');
        await tester.tap(find.byKey(const ValueKey('recap-toc-1')));
        await tester.pump();
        await tester.pump();
        await p.capture(tester, output, 'flutter-390-thinking');
        await p.section(tester, 2);
        await p.capture(tester, output, 'flutter-390-questions');
        await tester.ensureVisible(find.byKey(const ValueKey('recap-ask-n1')));
        await tester.tap(find.byKey(const ValueKey('recap-ask-n1')));
        await p.settle(tester);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('recap-question')))
              .controller!
              .text,
          isNotEmpty,
        );
        await p.capture(tester, output, 'flutter-390-ask');
        p.keyboard.value = 280;
        await tester.pump();
        await tester.ensureVisible(find.text('发送追问'));
        await tester.pump();
        expect(
          tester.getRect(find.text('发送追问')).bottom,
          lessThanOrEqualTo(564),
        );
        await p.capture(tester, output, 'flutter-390-keyboard');
        p.keyboard.value = 0;
        await tester.pump();
        await p.tap(tester, '返回回望');
        await tester.ensureVisible(find.text('查看依据').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看依据').first);
        await p.settle(tester);
        expect(find.byTooltip('关闭依据'), findsOneWidget);
        expect(find.text(RecapEditorialFixture.excerpt), findsOneWidget);
        await p.capture(tester, output, 'flutter-390-evidence');
        await p.tap(tester, '返回回望');
        tester.view.physicalSize = const Size(320, 640);
        p.scale.value = 2;
        await tester.pump();
        await p.top(tester);
        expect(tester.takeException(), isNull);
        await p.capture(tester, output, 'flutter-320-scale200');
        await tester.tap(find.byTooltip('章节目录'));
        await tester.pump();
        await p.capture(tester, output, 'flutter-320-scale200-contents');
        expect(tester.takeException(), isNull);
        f.online.value = false;
        await tester.pump();
        expect(find.byType(RecapEditorialQuote), findsNothing);
        expect(find.byKey(const ValueKey('recap-toc-0')), findsNothing);
        p.scale.value = 1;
        await tester.pump();
        await p.capture(tester, output, 'flutter-320-withdrawn');
        debugPrint('A V2 actual Flutter artifacts: ${output.path}');
      } finally {
        await p.dispose(tester);
      }
    },
  );
}
