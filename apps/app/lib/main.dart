import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'config/dependencies.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/desktop_service.dart';
import 'data/services/error_reports.dart';
import 'data/services/notify_service.dart';
import 'routing/router.dart';
import 'routing/nav_history.dart';
import 'ui/core/ashlar/app.dart';
import 'ui/core/ashlar/app_theme.dart';
import 'ui/core/ashlar/markdown.dart';
import 'ui/core/code_highlight.dart';
import 'ui/chat/widgets/floating_player.dart';
import 'ui/core/about_dialog.dart';
import 'ui/chat/widgets/step_input.dart' show CodeColors;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A window opened as a floating player runs that, and nothing else.
  if (await _floatingPlayer() case (final window, final args)) {
    return runFloatingPlayer(window, args);
  }
  await NotifyService.splash('Loading your sessions and settings…');
  final loaded = await load();
  await NotifyService.splash('Opening Helmy…');
  // Helmy's own errors, to Mittolabs, when this build names where and the
  // setting allows; in step with the setting from then on.
  await ErrorReports.start(
    allowed: loaded.settings.settings.sendErrors,
    release: const String.fromEnvironment('HELMY_VERSION', defaultValue: 'dev'),
  );
  loaded.settings.addListener(() => ErrorReports.allow(loaded.settings.settings.sendErrors));
  // The session last worked in (a side chat shows only beside its session).
  final last = loaded.sessions.sessions.where((s) => s.sideOf == null).firstOrNull;
  // The splash window shows until the first frame is drawn.
  WidgetsBinding.instance.addPostFrameCallback((_) => NotifyService.ready());
  // HELMY_FLOAT opens a video in a floating player, for looking at one while
  // developing.
  if (Platform.environment['HELMY_FLOAT'] case final video?) {
    WidgetsBinding.instance.addPostFrameCallback((_) => FloatingPlayers.openForLook(video));
  }
  runApp(
    MultiProvider(
      providers: providers(loaded),
      // HELMY_OPEN picks the first page, for looking at one while developing.
      child: HelmyApp(
        // First run: setup first.
        initialLocation:
            Platform.environment['HELMY_OPEN'] ??
            (!loaded.settings.settings.setupDone
                ? '/setup'
                : last == null
                ? '/'
                : '/s/${last.id}'),
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
    // About Helmy, from the app's menu.
    aboutRequests.addListener(_about);
  }

  void _about() {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showAbout(
      context,
      version: const String.fromEnvironment('HELMY_VERSION', defaultValue: _version),
    );
  }

  @override
  void dispose() {
    aboutRequests.removeListener(_about);
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
        child: MarkdownCodeWrap(
          wrap: settings.wrapCode,
          // Code in answers, plans and notes in syntax colors, in the theme's palette.
          child: Builder(
            builder: (context) {
              final colors = CodeColors.of(context);
              return MarkdownHighlight(
                highlight: (code, language, base) =>
                    CodeHighlighter.spans(code, language, base, colors),
                child: child!,
              );
            },
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}

/// This window and its player, when it was opened as a floating player.
Future<(WindowController, FloatingArgs)?> _floatingPlayer() async {
  if (!FloatingPlayers.here) return null;
  try {
    final window = await WindowController.fromCurrentEngine();
    final args = FloatingArgs.decode(window.arguments);
    return args == null ? null : (window, args);
  } on Object {
    return null;
  }
}

/// The version this build says, as pubspec.yaml has it.
const _version = '0.1.0'; // x-release-please-version
