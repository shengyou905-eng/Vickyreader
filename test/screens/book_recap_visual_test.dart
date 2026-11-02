import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_reader/config/theme.dart';
import 'package:ai_reader/screens/xiaou/book_recap_screen.dart';
import 'package:ai_reader/services/book_recap_material_catalog.dart';
import 'package:ai_reader/services/reading_source_changes.dart';
import '../support/recap_display_fixture.dart';

void main() {
  testWidgets(
    'render actual synthetic reading flow at phone and small viewport sizes',
    (tester) async {
      late RecapDisplayFixture f;
      late Directory output;
      var chineseFont = false;
      await tester.runAsync(() async {
        f = RecapDisplayFixture();
        await f.init();
        output = await Directory.systemTemp.createTemp(
          'zhidu-recap-b24b2-ui-refinement-',
        );
        // System test font only: never added to the shipped application or assets.
        final font = File('C:/Windows/Fonts/msyh.ttc');
        if (await font.exists()) {
          final loader = FontLoader('RecapVisualChinese')
            ..addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
          await loader.load();
          chineseFont = true;
        }
        final icons = File(
          'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icons.exists()) {
          await (FontLoader('MaterialIcons')..addFont(
                icons.readAsBytes().then((b) => ByteData.sublistView(b)),
              ))
              .load();
        }
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      final boundary = GlobalKey();
      final observer = RouteObserver<ModalRoute<void>>();
      final workspace = BookRecapWorkspace(
        session: f.session,
        api: f.api,
        catalog: BookRecapMaterialCatalog(() async => f.db),
        guard: f.guard,
        online: f.online,
        localChanges: ReadingSourceChanges.changes,
        displayLifetime: const Duration(seconds: 20),
        approvedPolicies: {'isolated-v1'},
        consentGate: (_) async => true,
        routeObserver: observer,
        monotonic: () => f.elapsed,
      );
      Future<void> settle() async {
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 35)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
      }

      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await settle();
      }

      Future<void> capture(String name) async {
        await tester.pump();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixels, isNotNull);
          final sampled = <int>{};
          for (var i = 0; i < pixels!.lengthInBytes; i += 64) {
            sampled.add(pixels.getUint32(i));
          }
          expect(
            sampled.length,
            greaterThan(20),
            reason: 'Actual screen must not be blank',
          );
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${output.path}/$name.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      try {
        final theme = AppTheme.forTheme(AppThemeId.babyBlue);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              navigatorObservers: [observer],
              debugShowCheckedModeBanner: false,
              theme: chineseFont
                  ? theme.copyWith(
                      textTheme: theme.textTheme.apply(
                        fontFamily: 'RecapVisualChinese',
                      ),
                      appBarTheme: theme.appBarTheme.copyWith(
                        titleTextStyle: theme.appBarTheme.titleTextStyle!
                            .copyWith(fontFamily: 'RecapVisualChinese'),
                      ),
                    )
                  : theme,
              home: Scaffold(body: BookRecapEntry(workspace: workspace)),
            ),
          ),
        );
        await settle();
        await tap('阅读回望');
        await tap('条件与证据');
        await capture('materials-390');
        await tester.tap(find.byKey(const ValueKey('material-local-a')));
        await tester.pump();
        await tap('确认所选材料');
        await capture('confirmation-390');
        await tap('生成回望');
        await tester.drag(find.byType(ListView), const Offset(0, 1200));
        await tester.pumpAndSettle();
        await capture('detail-390');
        tester.view.physicalSize = const Size(320, 640);
        await tester.pumpAndSettle();
        await capture('detail-320');
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('查看依据').first);
        await tester.tap(find.text('查看依据').first);
        await settle();
        await capture('evidence-390');
        await tap('返回回望');
        await tap('继续追问');
        await tester.enterText(
          find.byKey(const Key('recap-question')),
          '那么需要什么额外证据？',
        );
        await tap('发送追问');
        await tester.drag(find.byType(ListView), const Offset(0, 1200));
        await tester.pumpAndSettle();
        await capture('discussion-390');
        await tap('返回回望');
        await tap('保存回望');
        await tester.tap(find.byTooltip('更多操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('我的回望'));
        await settle();
        await capture('history-390');
        expect(tester.takeException(), isNull);
        // This is a generated test artifact, not a business file or user data.
        debugPrint(
          'B24b2 UI refinement artifacts: ${output.path}; system Chinese font=$chineseFont',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.runAsync(f.dispose);
      }
    },
  );
}
