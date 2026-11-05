import 'version.dart';
import 'domain/models/settings.dart';
import 'ui/core/key_bindings.dart';
import 'domain/vscode_theme.dart';
import 'domain/identity.dart';
import 'ui/core/ashlar/toast.dart';
import 'utils/platform.dart';

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
import 'data/services/window_snapshots.dart';
import 'data/repositories/session_repository.dart';
import 'routing/router.dart';
import 'routing/nav_history.dart';
import 'ui/core/ashlar/app.dart';
import 'ui/core/ashlar/app_theme.dart';
import 'ui/core/ashlar/markdown.dart';
import 'ui/core/code_highlight.dart';
import 'ui/chat/widgets/floating_player.dart';
import 'ui/core/about_dialog.dart';
import 'ui/phone/phone_app.dart';
import 'ui/chat/widgets/step_input.dart' show CodeColors;

Future<void> main() async {
  // On a phone, Helmy is a remote for Helmy on a Mac: nothing of the desktop
  // app runs there.
  if (Platform.isIOS || Platform.isAndroid) return runPhone();
  WidgetsFlutterBinding.ensureInitialized();
  // A window opened as a floating player runs that, and nothing else.
  if (await _floatingPlayer() case (final window, final args)) {
    return runFloatingPlayer(window, args);
  }
  await NotifyService.splash('Loading your chats and settings…');
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
  StreamSubscription<Map<String, Object?>>? _snapKeys;

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
    // ⌘Q held back while chats work: say what a second press does.
    quitAsked.addListener(_quitAsked);
    // Both Shift keys, in any app: that window into the message being written,
    // in the conversation on screen (else the last one).
    final snaps = context.read<WindowSnapshots>();
    // Listening, and to which other shortcut: told again when either changes.
    String listeningTo(AppSettings s) => s.snapshotKeys ? 'on ${s.snapshotKey}' : 'off';
    Future<void> listen(AppSettings s) {
      final k = s.snapshotKey.isEmpty ? null : KeyBinding.parse(s.snapshotKey);
      return snaps.listen(
        s.snapshotKeys,
        also: k == null
            ? null
            : (char: k.key.keyLabel.toLowerCase(), cmd: k.command, shift: k.shift, alt: k.alt),
      );
    }

    var listening = listeningTo(settings.settings);
    if (settings.settings.snapshotKeys) unawaited(listen(settings.settings));
    settings.addListener(() {
      if (listeningTo(settings.settings) == listening) return;
      listening = listeningTo(settings.settings);
      unawaited(listen(settings.settings));
    });
    final sessions = context.read<SessionRepository>();
    _snapKeys = context.read<NotifyService>().snapshotKeys.listen((w) {
      final window = (
        id: (w['id'] as num).toInt(),
        pid: (w['pid'] as num).toInt(),
        app: '${w['app']}',
        title: '${w['title'] ?? ''}',
      );
      final here = _router.routerDelegate.currentConfiguration.uri.path;
      if (!here.startsWith('/s/')) {
        final last = sessions.sessions.where((s) => s.sideOf == null && !s.archived).firstOrNull;
        if (last != null) _router.go('/s/${last.id}');
      }
      snapshotRequests.value = (window: window, fromKeys: true);
    });
  }

  void _quitAsked() {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showToast(
      context,
      title: 'Chats are still working',
      description: context.read<SettingsRepository>().settings.carryOnAfterRestart
          ? 'Press ${Desktop.current.keys('⌘Q')} again to quit. They carry on when Helmy opens again.'
          : 'Press ${Desktop.current.keys('⌘Q')} again to quit and stop them.',
    );
  }

  void _about() {
    final context = _router.routerDelegate.navigatorKey.currentContext;
    if (context == null) return;
    showAbout(context, version: shownVersion);
  }

  @override
  void dispose() {
    aboutRequests.removeListener(_about);
    quitAsked.removeListener(_quitAsked);
    _opened?.cancel();
    _snapKeys?.cancel();
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsRepository>().settings;
    return AshlarApp.router(
      title: 'Helmy',
      theme: themeFor(
        .light,
        palette: settings.palette,
        accent: settings.accent,
        font: settings.interfaceFont,
        contrast: settings.contrast,
        imported: importedThemeFromJson(settings.themeImport),
      ),
      darkTheme: themeFor(
        .dark,
        palette: settings.palette,
        accent: settings.accent,
        font: settings.interfaceFont,
        contrast: settings.contrast,
        imported: importedThemeFromJson(settings.themeImport),
      ),
      themeMode: switch (settings.theme) {
        .system => AshlarThemeMode.system,
        .light => AshlarThemeMode.light,
        .dark => AshlarThemeMode.dark,
      },
      // Text size is a scale on every size the theme sets.
      builder: (context, child) {
        // Code's font, and how clocks read, for the helpers that draw them.
        chosenCodeFont = settings.codeFont;
        writingStyle = writingStyleFor(settings.commitStyle, settings.commitNote);
        use24Hour = switch (settings.clock) {
          .system => MediaQuery.of(context).alwaysUse24HourFormat,
          .twelve => false,
          .twentyFour => true,
        };
        return MediaQuery(
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
        );
      },
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
