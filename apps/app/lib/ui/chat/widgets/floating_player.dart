import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/ashlar/app.dart';
import '../../core/ashlar/app_theme.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';
import 'player.dart';

/// A video playing in Helmy's own small window, kept above every other app's
/// (picture in picture), on macOS, Windows and Linux alike. It is a second
/// window with its own player: popping out pauses the conversation's player
/// and starts this one where it was; coming back hands the place back.

/// What a floating player is opened with: the video, and where to start.
class FloatingArgs {
  FloatingArgs({
    required this.where,
    required this.words,
    required this.at,
    required this.volume,
    required this.speed,
    required this.ratio,
  });

  /// A full path, or a web address.
  final String where;
  final String words;
  final Duration at;
  final double volume, speed;

  /// The picture's width over its height, for the window's shape.
  final double ratio;

  static const kind = 'helmy-floating-player';

  String encode() => jsonEncode({
    'kind': kind,
    'where': where,
    'words': words,
    'at': at.inMilliseconds,
    'volume': volume,
    'speed': speed,
    'ratio': ratio,
  });

  /// The arguments of a window, when it is a floating player's.
  static FloatingArgs? decode(String arguments) {
    try {
      final j = jsonDecode(arguments) as Map;
      if (j['kind'] != kind) return null;
      return FloatingArgs(
        where: j['where'] as String,
        words: j['words'] as String? ?? '',
        at: Duration(milliseconds: (j['at'] as num?)?.toInt() ?? 0),
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        speed: (j['speed'] as num?)?.toDouble() ?? 1,
        ratio: (j['ratio'] as num?)?.toDouble() ?? 16 / 9,
      );
    } on Object {
      return null;
    }
  }
}

/// Where a floating player was when it came back, and whether it played.
typedef Place = ({Duration at, bool playing});

/// The main window's side: opens a floating player and hears it come back.
class FloatingPlayers {
  /// Whether a floating window can be opened here: the desktop platforms.
  static bool get here => enabled && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Off in tests: an extra window starts the test's own code, not the app's.
  static bool enabled = true;

  static WindowMethodChannel _channel(String windowId) =>
      WindowMethodChannel('helmy/floating/$windowId');

  /// Opens [c]'s video floating, from where it is; [onBack] hears where it
  /// stopped when it comes back. Null when no window could be opened, and
  /// the caller shows it another way.
  static Future<String?> open(
    VideoPlayerController c, {
    required String where,
    required String words,
    required ValueChanged<Place> onBack,
  }) async {
    if (!here) return null;
    try {
      final v = c.value;
      final window = await WindowController.create(
        WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: FloatingArgs(
            where: where,
            words: words,
            at: v.position,
            volume: v.volume,
            speed: v.playbackSpeed,
            ratio: v.aspectRatio,
          ).encode(),
        ),
      );
      await _channel(window.windowId).setMethodCallHandler((call) async {
        if (call.method == 'back') onBack(_place(call.arguments));
        return null;
      });
      await window.show();
      return window.windowId;
    } on Object {
      return null;
    }
  }

  /// Opens [where] floating from its start, muted: for looking at the
  /// floating player while developing (HELMY_FLOAT).
  static Future<String?> openForLook(String where) async {
    if (!here) return null;
    final window = await WindowController.create(
      WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: FloatingArgs(
          where: where,
          words: 'look',
          at: Duration.zero,
          volume: 0,
          speed: 1,
          ratio: 16 / 9,
        ).encode(),
      ),
    );
    await _channel(window.windowId).setMethodCallHandler((call) async {
      final place = _place(call.arguments);
      debugPrint(
        'floating player came back at ${place.at.inMilliseconds} ms, playing ${place.playing}',
      );
      return null;
    });
    await window.show();
    // HELMY_FLOAT_STOP=<seconds>: the main window asks for it back then.
    final after = int.tryParse(Platform.environment['HELMY_FLOAT_STOP'] ?? '');
    if (after != null) {
      unawaited(
        Future<void>.delayed(Duration(seconds: after), () async {
          final place = await bringBack(window.windowId);
          debugPrint('brought back at ${place?.at.inMilliseconds} ms, playing ${place?.playing}');
        }),
      );
    }
    return window.windowId;
  }

  /// Asks the floating player [windowId] to close, and where it was.
  static Future<Place?> bringBack(String windowId) async {
    try {
      return _place(await _channel(windowId).invokeMethod<Object?>('stop'));
    } on Object {
      return null;
    }
  }

  static Place _place(Object? a) {
    final m = (a as Map?) ?? const {};
    return (
      at: Duration(milliseconds: (m['at'] as num?)?.toInt() ?? 0),
      playing: m['playing'] == true,
    );
  }
}

/// The floating window's own app: started by `main` when its window was
/// opened as a floating player.
Future<void> runFloatingPlayer(WindowController window, FloatingArgs args) async {
  await windowManager.ensureInitialized();
  const width = 400.0;
  final size = Size(width, (width / args.ratio).clamp(120.0, 600.0));
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: size,
      minimumSize: const Size(220, 124),
      title: 'Helmy',
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: const Color(0xFF000000),
      alwaysOnTop: true,
    ),
    () async {
      // Its own close and back buttons; not the window's.
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      // On every desktop, and over an app in full screen, as picture in
      // picture is: it follows you.
      await windowManager.setVisibleOnAllWorkspaces(true, visibleOnFullScreen: true);
      await windowManager.setAspectRatio(args.ratio);
      await windowManager.setAlignment(Alignment.bottomRight);
      await windowManager.show();
    },
  );
  runApp(
    AshlarApp(
      theme: appDarkTheme,
      darkTheme: appDarkTheme,
      home: FloatingPlayerPage(windowId: window.windowId, args: args),
    ),
  );
}

/// The floating window's page: the video edge to edge; its controls show
/// while the pointer is over it.
class FloatingPlayerPage extends StatefulWidget {
  const FloatingPlayerPage({super.key, required this.windowId, required this.args});
  final String windowId;
  final FloatingArgs args;

  @override
  State<FloatingPlayerPage> createState() => _FloatingPlayerPageState();
}

class _FloatingPlayerPageState extends State<FloatingPlayerPage> with WindowListener {
  late final VideoPlayerController _c = widget.args.where.startsWith('http')
      ? VideoPlayerController.networkUrl(Uri.parse(widget.args.where))
      : VideoPlayerController.file(File(widget.args.where));
  late final _channel = WindowMethodChannel('helmy/floating/${widget.windowId}');
  final _focus = FocusNode(debugLabel: 'floating player');
  bool _hover = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(windowManager.setPreventClose(true));
    _c.addListener(_changed);
    unawaited(
      _c.initialize().then((_) async {
        await _c.setVolume(widget.args.volume);
        await _c.setPlaybackSpeed(widget.args.speed);
        await _c.seekTo(widget.args.at);
        await _c.play();
      }),
    );
    unawaited(
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'stop') return null;
        final place = _place;
        unawaited(Future<void>.delayed(const Duration(milliseconds: 50), _close));
        return place;
      }),
    );
  }

  Map<String, Object?> get _place => {
    'at': _c.value.position.inMilliseconds,
    'playing': _c.value.isPlaying,
  };

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Back to Helmy: its player takes up from here (playing, if [playing]).
  Future<void> _back({required bool playing}) async {
    if (_closing) return;
    try {
      await _channel.invokeMethod<void>('back', {..._place, 'playing': playing});
    } on Object {
      // Helmy's window is gone; this one just closes.
    }
    await _close();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _c.pause();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// The window's own close button: back to Helmy, paused.
  @override
  void onWindowClose() => unawaited(_back(playing: false));

  @override
  void dispose() {
    windowManager.removeListener(this);
    _c.removeListener(_changed);
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final v = _c.value;
    Widget tool(String label, IconData icon, VoidCallback onPressed) => Button(
      variant: .ghost,
      size: .iconXs,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 14, color: const Color(0xFFFFFFFF)),
    );
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return .ignored;
        if (e.logicalKey == LogicalKeyboardKey.space) {
          togglePlay(_c);
        } else if (e.logicalKey == LogicalKeyboardKey.escape) {
          unawaited(_back(playing: v.isPlaying));
        } else {
          return .ignored;
        }
        return .handled;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: ColoredBox(
          color: const Color(0xFF000000),
          child: Stack(
            fit: .expand,
            children: [
              // Dragging the picture moves the window; a click plays or pauses.
              DragToMoveArea(
                child: GestureDetector(
                  onTap: () => togglePlay(_c),
                  child: v.isInitialized
                      ? Center(
                          child: AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c)),
                        )
                      : const SizedBox.expand(),
                ),
              ),
              if (_hover || !v.isPlaying)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xCC000000), Color(0x00000000)],
                      ),
                    ),
                    padding: const .fromLTRB(6, 18, 6, 4),
                    child: Row(
                      spacing: 4,
                      children: [
                        tool(
                          v.isPlaying ? 'Pause' : 'Play',
                          v.isPlaying
                              ? AshlarIconsRoundedStroke.pause
                              : AshlarIconsRoundedStroke.play,
                          () => togglePlay(_c),
                        ),
                        Expanded(
                          child: Bar(
                            value: v.duration.inMilliseconds == 0
                                ? 0
                                : v.position.inMilliseconds / v.duration.inMilliseconds,
                            ink: const Color(0xFFFFFFFF),
                            track: const Color(0x40FFFFFF),
                            label: 'Position',
                            onChanged: (f) => _c.seekTo(v.duration * f),
                          ),
                        ),
                        Text(
                          Controls.time(v.position),
                          style: t.text.xs.copyWith(color: const Color(0xB3FFFFFF)),
                        ),
                        tool(
                          'Back to Helmy',
                          AshlarIconsRoundedStroke.arrowUpLeft,
                          () => unawaited(_back(playing: v.isPlaying)),
                        ),
                        tool(
                          'Close',
                          AshlarIconsRoundedStroke.x,
                          () => unawaited(_back(playing: false)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
