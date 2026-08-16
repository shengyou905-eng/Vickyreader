import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'l10n/l10n.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/bookshelf_provider.dart';
import 'providers/reader_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/bookmarks/bookmarks_screen.dart';
import 'screens/bookshelf/bookshelf_screen.dart';
import 'screens/mingtai/community_mingtai_screen.dart';
import 'screens/xiaou/xiaou_home_screen.dart';
import 'screens/notes_free/notes_free_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/password_reset_screens.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

class AiReaderApp extends StatefulWidget {
  const AiReaderApp({super.key});

  @override
  State<AiReaderApp> createState() => _AiReaderAppState();
}

class _AiReaderAppState extends State<AiReaderApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastResetToken;

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    unawaited(
      _appLinks
          .getInitialLink()
          .then((uri) {
            if (uri != null) _handleLink(uri);
          })
          .catchError((_) {}),
    );
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (_) {},
    );
  }

  void _handleLink(Uri uri) {
    final isResetLink = uri.scheme == 'readu' && uri.host == 'reset-password';
    if (!isResetLink) return;
    final token = uri.queryParameters['token']?.trim() ?? '';
    if (token.isEmpty || token == _lastResetToken) return;
    _lastResetToken = token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(token: token)),
      );
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => BookshelfProvider()),
        ChangeNotifierProvider(create: (_) => ReaderProvider()),
        ChangeNotifierProvider(create: (_) => AiProvider()),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider()..loadSettings(),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          navigatorKey: appNavigatorKey,
          onGenerateTitle: (context) => context.l10n.appName,
          debugShowCheckedModeBanner: false,
          locale: settings.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.forTheme(settings.appThemeId),
          themeAnimationDuration: AppVisualFoundation.standard.motionDuration,
          themeAnimationCurve: Curves.easeOutCubic,
          home: const MainScreen(),
          routes: {
            '/bookmarks': (_) => const BookmarksScreen(),
            '/settings': (_) => const SettingsScreen(),
          },
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _xiaouRefreshSignal = 0;
  int _freeNotesRefreshSignal = 0;
  int _mingtaiRefreshSignal = 0;
  final Set<int> _initializedTabs = {0};
  final Map<int, DateTime> _lastTabActivatedAt = {0: DateTime.now()};
  bool _wasBackgrounded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !_wasBackgrounded || !mounted) {
      return;
    }
    _wasBackgrounded = false;
    debugPrint('[AppDataRefresh] resumed; refreshing initialized tabs');
    setState(() {
      if (_initializedTabs.contains(1)) _xiaouRefreshSignal++;
      if (_initializedTabs.contains(2)) _freeNotesRefreshSignal++;
      if (_initializedTabs.contains(3)) _mingtaiRefreshSignal++;
    });
    context.read<BookshelfProvider>().loadBooks();
  }

  Widget _pageAt(int index) {
    if (!_initializedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => const BookshelfScreen(),
      1 => XiaouHomeScreen(
        refreshSignal: _xiaouRefreshSignal,
        isActive: _currentIndex == 1,
      ),
      2 => NotesFreeScreen(refreshSignal: _freeNotesRefreshSignal),
      3 => CommunityMingtaiScreen(
        refreshSignal: _mingtaiRefreshSignal,
        isActive: _currentIndex == 3,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(4, _pageAt, growable: false),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          if (i == _currentIndex) return;
          final now = DateTime.now();
          final wasInitialized = _initializedTabs.contains(i);
          final lastActivatedAt = _lastTabActivatedAt[i];
          final shouldCheckForUpdates =
              wasInitialized &&
              (lastActivatedAt == null ||
                  now.difference(lastActivatedAt) >
                      const Duration(seconds: 30));
          setState(() {
            _initializedTabs.add(i);
            _lastTabActivatedAt[i] = now;
            if (wasInitialized && i == 1) _xiaouRefreshSignal++;
            // Free notes can be created from Xiaou while this tab stays alive.
            // Always re-read the fast local cache when returning to the tab.
            if (wasInitialized && i == 2) _freeNotesRefreshSignal++;
            if (shouldCheckForUpdates && i == 3) _mingtaiRefreshSignal++;
            _currentIndex = i;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: context.l10n.tabBookshelf,
          ),
          NavigationDestination(
            icon: const Icon(Icons.lightbulb_outline),
            selectedIcon: const Icon(Icons.lightbulb),
            label: context.l10n.tabXiaou,
          ),
          NavigationDestination(
            icon: const Icon(Icons.edit_note_outlined),
            selectedIcon: const Icon(Icons.edit_note),
            label: context.l10n.tabFreeNotes,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_stories_outlined),
            selectedIcon: const Icon(Icons.auto_stories),
            label: context.l10n.tabMingtai,
          ),
        ],
      ),
    );
  }
}
