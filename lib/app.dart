import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/constants.dart';
import 'providers/auth_provider.dart';
import 'providers/bookshelf_provider.dart';
import 'providers/reader_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/bookmarks/bookmarks_screen.dart';
import 'screens/bookshelf/bookshelf_screen.dart';
import 'screens/mingtai/mingtai_screen.dart';
import 'screens/xiaou/xiaou_home_screen.dart';
import 'screens/notes/notes_screen.dart';
import 'screens/notes_free/notes_free_screen.dart';
import 'screens/settings/settings_screen.dart';

class AiReaderApp extends StatelessWidget {
  const AiReaderApp({super.key});

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
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.forTheme(settings.appThemeId),
          home: const MainScreen(),
          routes: {
            '/notes': (_) => const NotesScreen(),
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

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _xiaouRefreshSignal = 0;
  int _freeNotesRefreshSignal = 0;
  int _mingtaiRefreshSignal = 0;
  final Set<int> _initializedTabs = {0};
  final Map<int, DateTime> _lastTabActivatedAt = {0: DateTime.now()};

  Widget _pageAt(int index) {
    if (!_initializedTabs.contains(index)) return const SizedBox.shrink();
    return switch (index) {
      0 => const BookshelfScreen(),
      1 => XiaouHomeScreen(refreshSignal: _xiaouRefreshSignal),
      2 => NotesFreeScreen(refreshSignal: _freeNotesRefreshSignal),
      3 => MingtaiScreen(refreshSignal: _mingtaiRefreshSignal),
      _ => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            if (shouldCheckForUpdates && i == 1) _xiaouRefreshSignal++;
            if (shouldCheckForUpdates && i == 2) _freeNotesRefreshSignal++;
            if (shouldCheckForUpdates && i == 3) _mingtaiRefreshSignal++;
            _currentIndex = i;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline),
            selectedIcon: Icon(Icons.lightbulb),
            label: '小U',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: '随心记',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: '明台',
          ),
        ],
      ),
    );
  }
}
