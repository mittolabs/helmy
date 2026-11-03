import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'config/dependencies.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/desktop_service.dart';
import 'data/services/notify_service.dart';
import 'routing/router.dart';
import 'routing/nav_history.dart';
import 'ui/core/ashlar/app.dart';
import 'ui/core/ashlar/app_theme.dart';
import 'ui/core/ashlar/markdown.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loaded = await load();
  final last = loaded.sessions.sessions.firstOrNull;
  runApp(
    MultiProvider(
      providers: providers(loaded),
      // HELMY_OPEN picks the first page, for looking at one while developing.
      child: HelmyApp(
        initialLocation:
            Platform.environment['HELMY_OPEN'] ?? (last == null ? '/' : '/s/${last.id}'),
      ),
    ),
  );
}

class HelmyApp extends StatefulWidget {
  const new({super.key, required this.initialLocation});
  final String initialLocation;

  @override
  State<HelmyApp> createState() => _HelmyAppState();
}

class _HelmyAppState extends State<HelmyApp> {
  late final _router = router(widget.initialLocation);
  late final NavHistory _history;
  StreamSubscription<String>? _opened;

  @override
  void initState() {
    super.initState();
    _history = NavHistory.current = NavHistory(_router);
    // The window's close button follows the setting, from the start and on change.
    final settings = context.read<SettingsRepository>();
    final desktop = context.read<DesktopService>();
    var keep = settings.settings.keepRunning;
    desktop.setKeepRunning(keep);
    settings.addListener(() {
      if (settings.settings.keepRunning == keep) return;
      keep = settings.settings.keepRunning;
      desktop.setKeepRunning(keep);
    });
    // A click on a notification opens the session it was about.
    _opened = context.read<NotifyService>().opened.listen((id) => _router.go('/s/$id'));
  }

  @override
  void dispose() {
    _opened?.cancel();
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>().settings;
    return AshlarApp.router(
      title: 'Helmy',
      theme: appTheme,
      darkTheme: appDarkTheme,
      themeMode: switch (settings.theme) {
        .system => AshlarThemeMode.system,
        .light => AshlarThemeMode.light,
        .dark => AshlarThemeMode.dark,
      },
      // Text size is a scale on every size the theme sets.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(settings.textSize.scale)),
        child: MarkdownCodeWrap(wrap: settings.wrapCode, child: child!),
      ),
      routerConfig: _router,
    );
  }
}
