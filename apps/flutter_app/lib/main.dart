import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/stats_base_url.dart'
    if (dart.library.io) 'config/stats_base_url_io.dart';
import 'l10n/app_localizations.dart';
import 'pages/home_page.dart';
import 'services/first_open_analytics.dart';
import 'services/launch_args_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialGamePath = await LaunchArgsService.getInitialGamePath();
  FirstOpenAnalytics.reportIfNeeded(baseUrl: statsBaseUrl, version: '1.0.0');
  runApp(Krkr2App(initialGamePath: initialGamePath));
}

class Krkr2App extends StatefulWidget {
  const Krkr2App({super.key, this.initialGamePath});

  final String? initialGamePath;

  /// Change the app locale at runtime. Pass null to follow system default.
  static void setLocale(BuildContext context, Locale? locale) {
    final state = context.findAncestorStateOfType<_Krkr2AppState>();
    state?._setLocale(locale);
  }

  /// Change the app theme mode at runtime.
  static void setThemeMode(BuildContext context, ThemeMode mode) {
    final state = context.findAncestorStateOfType<_Krkr2AppState>();
    state?._setThemeMode(mode);
  }

  @override
  State<Krkr2App> createState() => _Krkr2AppState();
}

class _Krkr2AppState extends State<Krkr2App> {
  static const String _localeKey = 'krkr2_locale';
  static const String _themeModeKey = 'krkr2_theme_mode';
  Locale? _locale; // null = follow system
  ThemeMode _themeMode = ThemeMode.dark; // default to dark

  @override
  void initState() {
    super.initState();
    _loadLocale();
    _loadThemeMode();
  }

  Future<void> _loadLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_localeKey);
    if (code != null && code != 'system' && mounted) {
      setState(() => _locale = Locale(code));
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_themeModeKey);
    if (mode != null && mounted) {
      setState(() {
        switch (mode) {
          case 'light':
            _themeMode = ThemeMode.light;
          case 'dark':
            _themeMode = ThemeMode.dark;
          default:
            _themeMode = ThemeMode.dark;
        }
      });
    }
  }

  void _setLocale(Locale? locale) {
    setState(() => _locale = locale);
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KrKr2 Next',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      themeMode: _themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pink,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: HomePage(initialGamePath: widget.initialGamePath),
    );
  }
}
