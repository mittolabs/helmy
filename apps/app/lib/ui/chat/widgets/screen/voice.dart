part of '../chat_screen.dart';

/// Where a voice conversation is.
enum _Voice { listening, thinking, speaking, stopped }

/// Talking with Helmy out loud: it listens, sends what was said when you
/// pause, waits for the answer, says it in the Mac's voice, and listens
/// again, until you end it. The conversation is the chat's, as if typed.
class _VoiceSession extends StatefulWidget {
  const _VoiceSession({required this.vm});
  final ChatViewModel vm;

  @override
  State<_VoiceSession> createState() => _VoiceSessionState();
}

class _VoiceSessionState extends State<_VoiceSession> with SingleTickerProviderStateMixin {
  ChatViewModel get vm => widget.vm;
  _Voice _state = .stopped;
  String _heard = '';
  String? _trouble;
  StreamSubscription<({String text, bool last})>? _words;
  StreamSubscription<bool>? _said;
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  /// Where the conversation stood when the last thing said was sent, and
  /// whether its turn has started yet.
  int _from = 0;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _words = dictation.stream.listen(_onWords);
    _said = spoken.stream.listen((_) {
      if (mounted && _state == .speaking) unawaited(_listen());
    });
    unawaited(_listen());
  }

  @override
  void dispose() {
    unawaited(_words?.cancel());
    unawaited(_said?.cancel());
    vm.removeListener(_onTurn);
    unawaited(vm.dictate(on: false));
    unawaited(vm.stopSpeaking());
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    setState(() {
      _state = .listening;
      _heard = '';
      _trouble = null;
    });
    final why = await vm.dictate(on: true);
    if (why != null && mounted) {
      setState(() {
        _state = .stopped;
        _trouble = why;
      });
    }
  }

  void _onWords(({String text, bool last}) w) {
    if (!mounted || _state != .listening) return;
    setState(() => _heard = w.text);
    if (!w.last) return;
    final said = w.text.trim();
    if (said.isEmpty) {
      unawaited(_listen());
      return;
    }
    // What was said goes into the chat, as typed.
    _from = vm.items.length;
    _started = false;
    setState(() => _state = .thinking);
    vm.addListener(_onTurn);
    unawaited(vm.send.execute(said));
  }

  /// The answer is in: said aloud, plainly (no Markdown, not too long).
  void _onTurn() {
    if (_state != .thinking) return;
    if (vm.busy) {
      _started = true;
      return;
    }
    if (!_started || vm.items.length <= _from) return;
    vm.removeListener(_onTurn);
    final answer = [
      for (final i in vm.items.skip(_from))
        if (i is AssistantText) i.text,
    ].join('\n\n');
    final plain = _plain(answer);
    if (!mounted) return;
    setState(() => _state = .speaking);
    unawaited(vm.speak(plain.isEmpty ? 'Done.' : plain));
  }

  /// [md] as words to say: no code, links as their words, no marks.
  static String _plain(String md) {
    var s = md
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' (code is in the chat) ')
        .replaceAllMapped(RegExp(r'!?\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!)
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'[*_~|>]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    s = s.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m[1]!);
    return s.length > 900
        ? '${s.substring(0, s.lastIndexOf(' ', 900).clamp(1, 900))}. The rest is in the chat.'
        : s;
  }

  void _interrupt() {
    if (_state == .speaking) {
      unawaited(vm.stopSpeaking());
      unawaited(_listen());
    } else if (_state == .stopped) {
      unawaited(_listen());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final (title, line) = switch (_state) {
      .listening => ('Listening', _heard.isEmpty ? 'Say what you want done.' : _heard),
      .thinking => ('Working on it', _heard),
      .speaking => ('Helmy', 'Tap the circle to talk over it.'),
      .stopped => ('Not listening', _trouble ?? 'Tap the circle to start again.'),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: HelmyDialog(
          title: 'Talking with Helmy',
          icon: AshlarIconsRoundedStroke.waveSine,
          maxWidth: 400,
          content: Column(
            mainAxisSize: .min,
            spacing: 16,
            children: [
              const SizedBox(height: 4),
              Pressable(
                onPressed: _interrupt,
                semanticLabel: _state == .speaking ? 'Talk over it' : 'Listen',
                builder: (context, state) => AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final live = _state == .listening || _state == .speaking;
                    final grow = live ? 1 + _pulse.value * .12 : 1.0;
                    return Transform.scale(
                      scale: grow,
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: _state == .stopped ? c.muted : c.primary,
                          boxShadow: live
                              ? [
                                  BoxShadow(
                                    color: c.primary.withValues(alpha: .35),
                                    blurRadius: 24 + _pulse.value * 16,
                                  ),
                                ]
                              : null,
                        ),
                        alignment: .center,
                        child: _state == .thinking
                            ? Spinner(size: 24, color: c.primaryForeground)
                            : AshlarIcon(
                                _state == .speaking
                                    ? AshlarIconsRoundedStroke.volume
                                    : AshlarIconsRoundedStroke.microphone,
                                size: 32,
                                color: _state == .stopped ? c.mutedForeground : c.primaryForeground,
                              ),
                      ),
                    );
                  },
                ),
              ),
              Text(title, style: t.text.base.copyWith(fontWeight: .w600)),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: Text(
                  line,
                  textAlign: .center,
                  maxLines: 4,
                  overflow: .ellipsis,
                  style: t.text.sm.copyWith(
                    color: _trouble != null && _state == .stopped
                        ? c.destructive
                        : c.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Button(
              variant: .outline,
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('End'),
            ),
          ],
        ),
      ),
    );
  }
}
