import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';

/// A terminal in the session's folder, running the user's own shell: as in
/// their terminal app, in Helmy's colors. It keeps running while another
/// tab shows; closing the tab ends it.
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.cwd, this.active = true});
  final String cwd;

  /// The tab showing: it takes the keyboard.
  final bool active;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final _terminal = Terminal(maxLines: 10000);
  final _focus = FocusNode();
  Pty? _pty;
  int? _exit;

  /// The shell to run: the user's own, else the platform's.
  static String get _shell {
    if (Platform.isWindows) return Platform.environment['COMSPEC'] ?? 'cmd.exe';
    return Platform.environment['SHELL'] ?? '/bin/zsh';
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _exit = null;
    final cwd = Directory(widget.cwd).existsSync() ? widget.cwd : homeDir;
    final pty = _pty = Pty.start(
      _shell,
      // A login shell, so the user's own setup (PATH, prompt) is there.
      arguments: Platform.isWindows ? const [] : const ['-l'],
      workingDirectory: cwd,
      environment: {...Platform.environment, 'TERM': 'xterm-256color', 'COLORTERM': 'truecolor'},
      columns: _terminal.viewWidth,
      rows: _terminal.viewHeight,
    );
    pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(_terminal.write);
    unawaited(
      pty.exitCode.then((code) {
        if (mounted) setState(() => _exit = code);
      }),
    );
    _terminal.onOutput = (data) => pty.write(const Utf8Encoder().convert(data));
    _terminal.onResize = (w, h, pw, ph) {
      pty.resize(h, w);
    };
  }

  @override
  void didUpdateWidget(TerminalPanel old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _focus.requestFocus();
  }

  @override
  void dispose() {
    _pty?.kill();
    _focus.dispose();
    super.dispose();
  }

  /// Helmy's colors for the terminal: its own background and text, and the
  /// usual sixteen, tuned to read on black.
  TerminalTheme _theme(AshlarThemeData t) {
    final c = t.colors;
    final dark = t.brightness == Brightness.dark;
    return TerminalTheme(
      cursor: c.foreground,
      selection: c.foreground.withValues(alpha: .25),
      foreground: c.foreground,
      background: c.background,
      black: dark ? const Color(0xFF3B3B3B) : const Color(0xFF000000),
      red: const Color(0xFFE5534B),
      green: const Color(0xFF57AB5A),
      yellow: const Color(0xFFC69026),
      blue: const Color(0xFF539BF5),
      magenta: const Color(0xFFB083F0),
      cyan: const Color(0xFF39C5CF),
      white: dark ? const Color(0xFFD4D4D4) : const Color(0xFF6E6E6E),
      brightBlack: const Color(0xFF7A7A7A),
      brightRed: const Color(0xFFFF7B72),
      brightGreen: const Color(0xFF7EE787),
      brightYellow: const Color(0xFFE3B341),
      brightBlue: const Color(0xFF79C0FF),
      brightMagenta: const Color(0xFFD2A8FF),
      brightCyan: const Color(0xFF56D4DD),
      brightWhite: dark ? const Color(0xFFFFFFFF) : const Color(0xFF3B3B3B),
      searchHitBackground: const Color(0xFFC69026),
      searchHitBackgroundCurrent: const Color(0xFFE3B341),
      searchHitForeground: const Color(0xFF000000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: TerminalView(
            _terminal,
            focusNode: _focus,
            autofocus: widget.active,
            theme: _theme(t),
            textStyle: const TerminalStyle(
              fontSize: 13,
              fontFamily: 'Menlo',
              fontFamilyFallback: ['SF Mono', 'Consolas', 'DejaVu Sans Mono', 'monospace'],
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            keyboardAppearance: t.brightness,
          ),
        ),
        // The shell ended (exit, or it closed): said so, with a way to start it.
        if (_exit != null)
          Container(
            padding: const .fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _exit == 0 ? 'The shell ended.' : 'The shell ended with code $_exit.',
                    style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                  ),
                ),
                Button(
                  size: .xs,
                  variant: .outline,
                  onPressed: () => setState(() {
                    _terminal.write('\r\n');
                    _start();
                    _focus.requestFocus();
                  }),
                  child: const Text('Start again'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bytes for a string, as the shell reads them.
Uint8List utf8Bytes(String s) => const Utf8Encoder().convert(s);
