import 'dart:async';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../../data/services/watch_service.dart';
import 'floating_player.dart';
import '../../core/file_actions.dart';

/// A video, or a sound, played in place: play and pause (or play again at the
/// end), where it is and a bar to move through it, speed, sound, and for a
/// video, full screen. A click on the picture plays or pauses it; with the
/// player focused, Space plays and pauses, ← and → move 5 seconds, M mutes,
/// F goes full screen and Esc comes back.
class Player extends StatefulWidget {
  const Player({
    super.key,
    this.path,
    this.web,
    required this.words,
    required this.video,
    required this.actions,
  });

  /// Where its bar's preview frames come from.
  final MediaActions actions;

  /// A file on this computer, or else [web], an address.
  final String? path;
  final Uri? web;
  final String words;

  /// A video, with its picture; false for a sound, controls only.
  final bool video;

  @override
  State<Player> createState() => _PlayerState();
}

/// The speeds offered, in the order a click steps through them.
const _speeds = [1.0, 1.25, 1.5, 2.0, 0.5];

class _PlayerState extends State<Player> {
  late final VideoPlayerController _c = widget.path != null
      ? VideoPlayerController.file(File(widget.path!))
      : VideoPlayerController.networkUrl(widget.web!);
  final _focus = FocusNode(debugLabel: 'player');
  bool _failed = false;

  /// The corner player, the app's one (given by provider).
  late final PoppedOut _corner = context.read<PoppedOut>();

  /// Small frames along the video, for the bar's preview on hover; made once,
  /// for a file, where ffmpeg is.
  List<Frame> _strip = const [];

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    _corner.addListener(_changed);
    _c.initialize().then(
      (_) => _changed(),
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
      },
    );
    if (widget.video && widget.path != null) {
      widget.actions.frames(widget.path!, count: 40, width: 240).then((f) {
        if (mounted) setState(() => _strip = f);
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _corner.removeListener(_changed);
    // Playing in the corner, it is the corner's now; else it ends here.
    if (_corner.controller == _c) {
      _corner.orphan();
    } else {
      _c.dispose();
    }
    _focus.dispose();
    super.dispose();
  }

  /// The floating window it plays in now, if any.
  String? _floating;

  /// Out to Helmy's own small window above every app; in a corner of this
  /// window where no other window can be opened.
  Future<void> _popOut() async {
    final where = widget.path ?? widget.web.toString();
    await _c.pause();
    final id = await FloatingPlayers.open(_c, where: where, words: widget.words, onBack: _takeBack);
    if (!mounted) return;
    if (id == null) {
      _corner.take(_c, widget.words);
      unawaited(_c.play());
    } else {
      setState(() => _floating = id);
    }
  }

  /// The floating player came back: take up where it was.
  void _takeBack(Place place) {
    if (!mounted) return;
    setState(() => _floating = null);
    unawaited(_c.seekTo(place.at).then((_) => place.playing ? _c.play() : null));
  }

  Future<void> _bringBack() async {
    final id = _floating;
    if (id == null) return;
    final place = await FloatingPlayers.bringBack(id);
    _takeBack(place ?? (at: _c.value.position, playing: false));
  }

  Future<void> _fullScreen() => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, _, _) => _FullScreen(controller: _c, words: widget.words),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final v = _c.value;
    if (_failed || v.hasError) {
      return _Frame(
        child: Padding(
          padding: const .all(12),
          child: Text(
            "This can't play here. Open it to play it in its own app.",
            style: t.text.sm.copyWith(color: t.colors.mutedForeground),
          ),
        ),
      );
    }
    if (!v.isInitialized) {
      return const _Frame(height: 48, child: Center(child: Spinner(size: 16)));
    }
    if (_floating != null) {
      return _Frame(
        child: Padding(
          padding: const .all(12),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  'Playing in its own window.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              ),
              Button(
                variant: .outline,
                size: .sm,
                onPressed: _bringBack,
                child: const Text('Bring it back'),
              ),
            ],
          ),
        ),
      );
    }
    if (_corner.controller == _c) {
      return _Frame(
        child: Padding(
          padding: const .all(12),
          child: Row(
            spacing: 10,
            children: [
              Expanded(
                child: Text(
                  'Playing in the corner.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              ),
              Button(
                variant: .outline,
                size: .sm,
                onPressed: _corner.giveBack,
                child: const Text('Bring it back'),
              ),
            ],
          ),
        ),
      );
    }
    final controls = Controls(
      controller: _c,
      onFullScreen: widget.video ? _fullScreen : null,
      onPopOut: widget.video ? _popOut : null,
      strip: _strip,
    );
    return _Keys(
      controller: _c,
      focus: _focus,
      onFullScreen: widget.video ? _fullScreen : null,
      child: _Frame(
        maxHeight: widget.video ? 440 : null,
        child: !widget.video
            ? controls
            : Column(
                mainAxisSize: .min,
                children: [
                  Flexible(
                    child: AspectRatio(
                      aspectRatio: v.aspectRatio,
                      child: _Picture(
                        controller: _c,
                        words: widget.words,
                        onTap: () {
                          _focus.requestFocus();
                          togglePlay(_c);
                        },
                        onDoubleTap: _fullScreen,
                      ),
                    ),
                  ),
                  controls,
                ],
              ),
      ),
    );
  }
}

/// Plays, pauses, or at the end plays again from the start.
void togglePlay(VideoPlayerController c) {
  final v = c.value;
  if (v.isPlaying) {
    unawaited(c.pause());
  } else if (v.isCompleted || (v.duration > Duration.zero && v.position >= v.duration)) {
    unawaited(c.seekTo(Duration.zero).then((_) => c.play()));
  } else {
    unawaited(c.play());
  }
}

/// Moves [by] (back when negative), within the video.
void nudge(VideoPlayerController c, Duration by) {
  final v = c.value;
  var to = v.position + by;
  if (to < Duration.zero) to = Duration.zero;
  if (to > v.duration) to = v.duration;
  unawaited(c.seekTo(to));
}

/// The keys a focused player answers to.
class _Keys extends StatelessWidget {
  const _Keys({
    required this.controller,
    required this.focus,
    required this.onFullScreen,
    required this.child,
    this.onEscape,
  });
  final VideoPlayerController controller;
  final FocusNode focus;
  final VoidCallback? onFullScreen;

  /// What Esc does: leave full screen; nothing in the conversation.
  final VoidCallback? onEscape;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: focus,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) return .ignored;
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.space && event is KeyDownEvent) {
        togglePlay(controller);
      } else if (k == LogicalKeyboardKey.arrowLeft) {
        nudge(controller, const Duration(seconds: -5));
      } else if (k == LogicalKeyboardKey.arrowRight) {
        nudge(controller, const Duration(seconds: 5));
      } else if (k == LogicalKeyboardKey.keyM && event is KeyDownEvent) {
        toggleMute(controller);
      } else if (k == LogicalKeyboardKey.keyF && event is KeyDownEvent && onFullScreen != null) {
        onFullScreen!();
      } else if (k == LogicalKeyboardKey.escape && event is KeyDownEvent && onEscape != null) {
        onEscape!();
      } else {
        return .ignored;
      }
      return .handled;
    },
    // A click anywhere on it gives it the keys.
    child: Listener(onPointerDown: (_) => focus.requestFocus(), child: child),
  );
}

/// The volume a mute put aside, per player, to give back on unmute.
final _beforeMute = Expando<double>();

void toggleMute(VideoPlayerController c) {
  if (c.value.volume > 0) {
    _beforeMute[c] = c.value.volume;
    unawaited(c.setVolume(0));
  } else {
    unawaited(c.setVolume(_beforeMute[c] ?? 1));
  }
}

/// The picture: a click plays or pauses, a double-click goes full screen,
/// and a large play button sits over it while it is paused.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.controller,
    required this.words,
    required this.onTap,
    required this.onDoubleTap,
  });
  final VideoPlayerController controller;
  final String words;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final v = controller.value;
    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Stack(
        fit: .expand,
        children: [
          Semantics(label: words, child: VideoPlayer(controller)),
          if (!v.isPlaying)
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: Color(0x99000000), shape: .circle),
                alignment: .center,
                child: AshlarIcon(
                  v.isCompleted
                      ? AshlarIconsRoundedStroke.rotateCcw
                      : AshlarIconsRoundedStroke.play,
                  size: 24,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ),
          if (v.isBuffering && v.isPlaying)
            Center(child: Spinner(size: 24, color: t.colors.foreground)),
        ],
      ),
    );
  }
}

/// The row under a video (or all of a sound): play, the time, the bar,
/// speed, sound, and full screen when [onFullScreen] is given.
class Controls extends StatelessWidget {
  const Controls({
    super.key,
    required this.controller,
    this.onFullScreen,
    this.onPopOut,
    this.strip = const [],
    this.onLight = false,
  });
  final VideoPlayerController controller;
  final VoidCallback? onFullScreen;

  /// Moves the video to a corner of the window, to keep watching while
  /// reading or working elsewhere in Helmy.
  final VoidCallback? onPopOut;

  /// Small frames along it, shown over the bar where the pointer is.
  final List<Frame> strip;

  /// Drawn over a video in full screen: light on dark, whatever the theme.
  final bool onLight;

  static String time(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final v = controller.value;
    final ink = onLight ? const Color(0xFFFFFFFF) : t.colors.foreground;
    final faint = onLight ? const Color(0xB3FFFFFF) : t.colors.mutedForeground;
    final total = v.duration.inMilliseconds;
    double part(Duration d) => total == 0 ? 0 : (d.inMilliseconds / total).clamp(0.0, 1.0);
    final loaded = v.buffered.isEmpty ? 0.0 : part(v.buffered.last.end);
    Widget tool(String label, IconData icon, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 14, color: ink),
      ),
    );
    final speed = v.playbackSpeed;
    return Padding(
      padding: const .symmetric(horizontal: 8, vertical: 6),
      child: Row(
        spacing: 6,
        children: [
          tool(
            v.isPlaying ? 'Pause (Space)' : (v.isCompleted ? 'Play again' : 'Play (Space)'),
            v.isPlaying
                ? AshlarIconsRoundedStroke.pause
                : v.isCompleted
                ? AshlarIconsRoundedStroke.rotateCcw
                : AshlarIconsRoundedStroke.play,
            () => togglePlay(controller),
          ),
          Text(
            '${time(v.position)} / ${time(v.duration)}',
            style: t.text.xs.copyWith(color: faint, fontFeatures: const [.tabularFigures()]),
          ),
          Expanded(
            child: Bar(
              value: part(v.position),
              loaded: loaded,
              ink: ink,
              track: onLight ? const Color(0x40FFFFFF) : t.colors.muted,
              label: 'Position',
              onChanged: (f) => controller.seekTo(Duration(milliseconds: (total * f).round())),
              // Where the pointer is on the bar: the frame there, and its time.
              preview: total == 0
                  ? null
                  : (f) {
                      final at = Duration(milliseconds: (total * f).round());
                      final near = strip.isEmpty
                          ? null
                          : strip.reduce((a, b) => (a.at - at).abs() <= (b.at - at).abs() ? a : b);
                      return _Preview(frame: near?.path, time: time(at));
                    },
            ),
          ),
          Tooltip(
            message: 'Speed',
            child: Button(
              variant: .ghost,
              size: .xs,
              semanticLabel: 'Speed ${_speedLabel(speed)}',
              onPressed: () {
                final i = _speeds.indexOf(speed);
                unawaited(controller.setPlaybackSpeed(_speeds[(i + 1) % _speeds.length]));
              },
              child: Text(_speedLabel(speed), style: t.text.xs.copyWith(color: ink)),
            ),
          ),
          tool(
            v.volume == 0 ? 'Sound on (M)' : 'Mute (M)',
            v.volume == 0
                ? AshlarIconsRoundedStroke.volumeX
                : v.volume < .5
                ? AshlarIconsRoundedStroke.volume1
                : AshlarIconsRoundedStroke.volume2,
            () => toggleMute(controller),
          ),
          SizedBox(
            width: 56,
            child: Bar(
              value: v.volume,
              ink: ink,
              track: onLight ? const Color(0x40FFFFFF) : t.colors.muted,
              label: 'Volume',
              onChanged: (f) => controller.setVolume(f),
            ),
          ),
          if (onPopOut != null)
            tool(
              'Keep watching in a small window on top',
              AshlarIconsRoundedStroke.pictureInPicture2,
              onPopOut!,
            ),
          if (onFullScreen != null)
            tool(
              onLight ? 'Exit full screen (Esc)' : 'Full screen (F)',
              onLight ? AshlarIconsRoundedStroke.minimize2 : AshlarIconsRoundedStroke.maximize2,
              onFullScreen!,
            ),
        ],
      ),
    );
  }
}

String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}×';

/// A thin bar to show and set a share (0 to 1) by a click or a drag: where a
/// video is, how loud. [loaded] shows, fainter, how much has arrived; with
/// [preview], what is at the pointer floats above it.
class Bar extends StatefulWidget {
  const Bar({
    super.key,
    required this.value,
    required this.onChanged,
    required this.ink,
    required this.track,
    required this.label,
    this.loaded = 0,
    this.preview,
  });

  /// What shows above the bar where the pointer is, given that share of it.
  final Widget Function(double share)? preview;
  final double value;
  final double loaded;
  final ValueChanged<double> onChanged;
  final Color ink;
  final Color track;
  final String label;

  @override
  State<Bar> createState() => _BarState();
}

class _BarState extends State<Bar> {
  final _link = LayerLink();
  final _over = OverlayPortalController();

  /// Where the pointer is along the bar, as a share; null when it is not on it.
  double? _at;
  double _width = 0;

  void _hover(double x) {
    if (widget.preview == null || _width <= 0) return;
    setState(() => _at = (x / _width).clamp(0.0, 1.0));
    _over.show();
  }

  void _leave() {
    setState(() => _at = null);
    _over.hide();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    slider: true,
    label: widget.label,
    value: '${(widget.value * 100).round()}%',
    child: LayoutBuilder(
      builder: (context, box) {
        _width = box.maxWidth;
        void set(double x) {
          if (box.maxWidth > 0) widget.onChanged((x / box.maxWidth).clamp(0.0, 1.0));
        }

        Widget line(double share, Color color) => FractionallySizedBox(
          widthFactor: share.clamp(0.0, 1.0),
          child: Container(
            height: 4,
            decoration: BoxDecoration(color: color, borderRadius: .circular(2)),
          ),
        );
        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _over,
            // Above the bar, centered on the pointer, kept inside the bar's ends.
            overlayChildBuilder: (context) => _at == null || widget.preview == null
                ? const SizedBox.shrink()
                : CompositedTransformFollower(
                    link: _link,
                    targetAnchor: Alignment.topLeft,
                    followerAnchor: Alignment.bottomCenter,
                    offset: Offset((_at! * _width).clamp(64, (_width - 64).clamp(64, 1e9)), -6),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: IgnorePointer(child: widget.preview!(_at!)),
                    ),
                  ),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (e) => _hover(e.localPosition.dx),
              onExit: (_) => _leave(),
              child: GestureDetector(
                behavior: .opaque,
                onTapDown: (d) => set(d.localPosition.dx),
                onHorizontalDragUpdate: (d) {
                  set(d.localPosition.dx);
                  _hover(d.localPosition.dx);
                },
                child: SizedBox(
                  height: 20,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Stack(
                      children: [
                        line(1, widget.track),
                        if (widget.loaded > 0)
                          line(widget.loaded, widget.ink.withValues(alpha: .3)),
                        line(widget.value, widget.ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// The frame where the pointer is on a video's bar, with its time; the time
/// alone where there are no frames (a web video, or no ffmpeg).
class _Preview extends StatelessWidget {
  const _Preview({required this.frame, required this.time});
  final String? frame;
  final String time;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: t.colors.popover,
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusMd),
        boxShadow: t.shadowSm,
      ),
      padding: const .all(3),
      child: Column(
        mainAxisSize: .min,
        spacing: 3,
        children: [
          if (frame != null)
            ClipRRect(
              borderRadius: .circular(t.radiusSm),
              child: Image.file(File(frame!), width: 128, fit: .contain, gaplessPlayback: true),
            ),
          Padding(
            padding: const .symmetric(horizontal: 4, vertical: 1),
            child: Text(time, style: t.text.xs.copyWith(color: t.colors.popoverForeground)),
          ),
        ],
      ),
    );
  }
}

/// A video moved out of the conversation, playing in a corner of the window
/// while you read or work elsewhere in Helmy. One at a time: popping out
/// another gives the first back. The corner owns it once the message it came
/// from is gone, and ends it when closed.
class PoppedOut extends ChangeNotifier {
  VideoPlayerController? controller;
  String words = '';

  /// Its message is gone: closing the corner ends it.
  bool _orphan = false;

  void take(VideoPlayerController c, String words) {
    if (controller != null && controller != c) giveBack();
    controller = c;
    this.words = words;
    _orphan = false;
    notifyListeners();
  }

  /// Its message left the screen; the corner keeps it until closed.
  void orphan() => _orphan = true;

  /// Back to its message, still playing; ended if the message is gone.
  void giveBack() {
    final c = controller;
    controller = null;
    if (_orphan) unawaited(c?.dispose());
    _orphan = false;
    notifyListeners();
  }

  /// Closed: paused, and back in its message (or ended, if that is gone).
  void close() {
    unawaited(controller?.pause());
    giveBack();
  }
}

/// The corner player: the popped-out video, small, over the bottom right of
/// the window, with play, back to where it came from, and close.
class CornerPlayer extends StatelessWidget {
  const CornerPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    // None given (a screen drawn on its own, in a test): no corner player.
    final corner = context.read<PoppedOut?>();
    if (corner == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: corner,
      builder: (context, _) {
        final c = corner.controller;
        if (c == null) return const SizedBox.shrink();
        final t = AshlarTheme.of(context);
        return PositionedDirectional(
          end: 16,
          bottom: 16,
          width: 320,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Container(
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                border: Border.all(color: t.colors.border),
                borderRadius: .circular(t.radiusLg),
                boxShadow: t.shadowLg,
              ),
              clipBehavior: .antiAlias,
              child: Column(
                mainAxisSize: .min,
                children: [
                  AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: _Picture(
                      controller: c,
                      words: corner.words,
                      onTap: () => togglePlay(c),
                      onDoubleTap: corner.giveBack,
                    ),
                  ),
                  Padding(
                    padding: const .symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      children: [
                        Button(
                          variant: .ghost,
                          size: .iconXs,
                          semanticLabel: c.value.isPlaying ? 'Pause' : 'Play',
                          onPressed: () => togglePlay(c),
                          child: AshlarIcon(
                            c.value.isPlaying
                                ? AshlarIconsRoundedStroke.pause
                                : AshlarIconsRoundedStroke.play,
                            size: 14,
                            color: const Color(0xFFFFFFFF),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            corner.words,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: t.text.xs.copyWith(color: const Color(0xB3FFFFFF)),
                          ),
                        ),
                        Tooltip(
                          message: 'Back to the conversation',
                          child: Button(
                            variant: .ghost,
                            size: .iconXs,
                            semanticLabel: 'Back to the conversation',
                            onPressed: corner.giveBack,
                            child: const AshlarIcon(
                              AshlarIconsRoundedStroke.arrowUpLeft,
                              size: 14,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Close',
                          child: Button(
                            variant: .ghost,
                            size: .iconXs,
                            semanticLabel: 'Close the corner player',
                            onPressed: corner.close,
                            child: const AshlarIcon(
                              AshlarIconsRoundedStroke.x,
                              size: 14,
                              color: Color(0xFFFFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The video filling the window, on black, its controls over the bottom.
/// Esc, F or the button comes back; the same video keeps playing.
class _FullScreen extends StatefulWidget {
  const _FullScreen({required this.controller, required this.words});
  final VideoPlayerController controller;
  final String words;

  @override
  State<_FullScreen> createState() => _FullScreenState();
}

class _FullScreenState extends State<_FullScreen> {
  final _focus = FocusNode(debugLabel: 'full screen player');

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    // Once on screen: asked for sooner, the keys (Esc among them) go nowhere.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) => _Keys(
    controller: _c,
    focus: _focus,
    onFullScreen: _close,
    onEscape: _close,
    child: ColoredBox(
      color: const Color(0xFF000000),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _c.value.aspectRatio,
                child: _Picture(
                  controller: _c,
                  words: widget.words,
                  onTap: () => togglePlay(_c),
                  onDoubleTap: _close,
                ),
              ),
            ),
          ),
          Controls(controller: _c, onFullScreen: _close, onLight: true),
        ],
      ),
    ),
  );
}

/// A frame for the player: rounded, bordered, at most [maxHeight] tall.
class _Frame extends StatelessWidget {
  const _Frame({required this.child, this.maxHeight, this.height});
  final Widget child;
  final double? maxHeight;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      height: height,
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: ClipRRect(borderRadius: .circular(t.radiusLg - 1), child: child),
    );
  }
}
