import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/design_server.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/popover.dart' show openOverlays;
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/window_web_view.dart';
import '../view_models/chat_view_model.dart';

/// Where a chat's design lives: `design/` in its folder.
String designFolderOf(String cwd) => '$cwd/design';

/// The design canvas beside the conversation: the chat's `design/` folder,
/// its screens laid out as `canvas.json` places them, live pages drawn on a
/// canvas to pan and zoom. Redrawn as the files change, so the agent's work
/// shows as it writes it.
class DesignPanel extends StatefulWidget {
  const DesignPanel({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<DesignPanel> createState() => _DesignPanelState();
}

class _DesignPanelState extends State<DesignPanel> {
  final _c = WebViewController();
  String? _folder;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _settle, _look;
  final _changed = <String>{};

  // What the canvas says of itself.
  String _title = '';
  List<({String file, String title})> _screens = const [];
  double _zoom = 1;

  /// Keyboard focus while the canvas is used: every key goes on to the
  /// page (Enter keeps typing, Esc lets go, arrows nudge), none to Helmy's
  /// own shortcuts or the message box.
  late final _keys = FocusNode(debugLabel: 'Design canvas', onKeyEvent: _onKey);

  /// Whether text on a screen is being typed into.
  bool _typing = false;

  /// The canvas's keys, as the page names them. macOS gives some keys to
  /// the app before the page: these are passed on to it from here. While
  /// typing, only Enter and Esc are; the rest stay with the text.
  static final _canvasKeys = {
    LogicalKeyboardKey.enter: 'Enter',
    LogicalKeyboardKey.numpadEnter: 'Enter',
    LogicalKeyboardKey.escape: 'Escape',
    LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
    LogicalKeyboardKey.arrowRight: 'ArrowRight',
    LogicalKeyboardKey.arrowUp: 'ArrowUp',
    LogicalKeyboardKey.arrowDown: 'ArrowDown',
    LogicalKeyboardKey.delete: 'Delete',
    LogicalKeyboardKey.backspace: 'Backspace',
    LogicalKeyboardKey.space: ' ',
    LogicalKeyboardKey.keyV: 'v',
    LogicalKeyboardKey.keyH: 'h',
    LogicalKeyboardKey.keyC: 'c',
    LogicalKeyboardKey.keyZ: 'z',
    LogicalKeyboardKey.equal: '=',
    LogicalKeyboardKey.minus: '-',
    LogicalKeyboardKey.digit1: '!',
  };

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final key = _canvasKeys[e.logicalKey];
    final keys = HardwareKeyboard.instance;
    if (key == null ||
        (_typing && key != 'Enter' && key != 'Escape') ||
        (key == '!' && !keys.isShiftPressed) ||
        ((key == 'z' || key == '=' || key == '-') && !keys.isMetaPressed)) {
      return KeyEventResult.skipRemainingHandlers;
    }
    final up = e is KeyUpEvent;
    if (up && key != ' ') return KeyEventResult.handled;
    unawaited(
      _run(
        'HelmyCanvas.key(${jsonEncode(key)}, ${keys.isShiftPressed}, ${keys.isMetaPressed}, $up)',
      ),
    );
    return KeyEventResult.handled;
  }

  /// A change the canvas could not save, for a moment.
  String? _problem;
  Timer? _problemTimer;

  /// Comments made on the canvas, by the pin's key: their ids in the
  /// message box. A pin goes when its comment is sent or removed.
  final _pins = <String, int>{};

  void _comment(Map<dynamic, dynamic> c) {
    final key = '${c['key']}';
    final file = '${c['file']}';
    final screen = '${c['screen']}';
    final el = c['element'];
    final what = el is Map
        ? [
            'the ${el['tag']}',
            if ('${el['words']}'.isNotEmpty) '"${el['words']}"',
            'at ${el['path']}',
          ].join(' ')
        : 'the whole screen';
    final id = widget.vm.comment(
      '${ChatViewModel.designComment}"$screen" (design/$file), $what',
      note: '${c['note'] ?? ''}',
    );
    if (id != null) _pins[key] = id;
  }

  /// The pins whose comments still wait to go.
  void _syncPins() {
    if (_pins.isEmpty) return;
    final waiting = {for (final c in widget.vm.comments) c.id};
    final before = _pins.length;
    _pins.removeWhere((_, id) => !waiting.contains(id));
    if (_pins.length != before) {
      unawaited(_run('HelmyCanvas.pins(${jsonEncode(_pins.keys.toList())})'));
    }
  }

  /// Move (select, edit, drag) or hand (pan only).
  String _tool = 'select';

  void _useTool(String tool) {
    setState(() => _tool = tool);
    unawaited(_run('HelmyCanvas.tool(${jsonEncode(tool)})'));
  }

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_c.addJavaScriptChannel('Helmy', onMessageReceived: (m) => _fromPage(m.message)));
    widget.vm.addListener(_follow);
    widget.vm.addListener(_syncPins);
    _follow();
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    widget.vm.removeListener(_syncPins);
    unawaited(_watch?.cancel());
    _settle?.cancel();
    _look?.cancel();
    _problemTimer?.cancel();
    _keys.dispose();
    super.dispose();
  }

  /// The chat's folder: its design, again when the chat moves to another.
  void _follow() {
    final cwd = widget.vm.session?.cwd;
    if (cwd == null) return;
    final folder = designFolderOf(cwd);
    if (folder == _folder) return;
    _folder = folder;
    unawaited(_open(folder));
  }

  Future<void> _open(String folder) async {
    await _c.loadRequest(await DesignServer.shared.canvasFor(folder));
    _startWatching(folder);
  }

  // The folder may not be there yet: looked for until it is.
  void _startWatching(String folder) {
    unawaited(_watch?.cancel());
    _look?.cancel();
    final dir = Directory(folder);
    if (!dir.existsSync()) {
      _look = Timer(const Duration(seconds: 2), () {
        if (mounted && folder == _folder) {
          if (dir.existsSync()) unawaited(_run('HelmyCanvas.reload()'));
          _startWatching(folder);
        }
      });
      return;
    }
    _watch = dir.watch(recursive: true).listen((e) {
      // The canvas's own saves are already on screen.
      final path = e is FileSystemMoveEvent ? (e.destination ?? e.path) : e.path;
      if (path.endsWith('.helmy-saving') || DesignServer.shared.savedJustNow(path)) return;
      if (!path.startsWith('$folder/')) return;
      _changed.add(path.substring(folder.length + 1));
      // A burst of writes, redrawn once.
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 150), () {
        final changed = [..._changed];
        _changed.clear();
        unawaited(_run('HelmyCanvas.reload(${jsonEncode(changed)})'));
      });
    });
  }

  Future<void> _run(String script) async {
    try {
      await _c.runJavaScript(script);
    } on Object {
      // Not loaded yet: it reads the files when it is.
    }
  }

  void _fromPage(String message) {
    final Object? m;
    try {
      m = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (m is! Map || !mounted) return;
    if (m['zoom'] case final num z) setState(() => _zoom = z.toDouble());
    if (m['loaded'] case final Map l) {
      setState(() {
        _title = '${l['title'] ?? ''}';
        _screens = [
          for (final s in (l['screens'] as List? ?? const []).whereType<Map>())
            (file: '${s['file']}', title: '${s['title']}'),
        ];
      });
    }
    if (m['download'] case final String file) unawaited(_saveCopy(file));
    if (m['comment'] case final Map c) _comment(c);
    if (m['tool'] case final String tool when tool != _tool) setState(() => _tool = tool);
    if (m['typing'] case final bool t) {
      _typing = t;
      // Typing: the web view keeps the keyboard, for the text.
      unawaited(widget.vm.keysTo(toPage: t));
    }
    if (m['active'] == true && !_typing) {
      if (!_keys.hasFocus) _keys.requestFocus();
      unawaited(widget.vm.keysTo(toPage: false));
    }
    if (m['problem'] case final String why) {
      _problemTimer?.cancel();
      setState(() => _problem = why);
      _problemTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _problem = null);
      });
    }
  }

  /// A copy of [file] (a screen) in Downloads, shown in the Finder.
  Future<void> _saveCopy(String file) async {
    final folder = _folder;
    final from = folder == null ? null : DesignServer.fileIn(folder, file);
    if (from == null || !from.existsSync()) return;
    final name = file.split('/').last;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var to = File('$homeDir/Downloads/$name');
    for (var n = 2; to.existsSync(); n++) {
      to = File('$homeDir/Downloads/$stem $n$ext');
    }
    await from.copy(to.path);
    await widget.vm.reveal(to.path);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    Widget tool(IconData icon, String label, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 14),
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(8, 6, 8, 6),
          child: Row(
            spacing: 4,
            children: [
              // Its screens, to go to one.
              Expanded(
                child: Align(
                  alignment: .centerLeft,
                  child: DropdownMenu(
                    items: [
                      for (final s in _screens)
                        MenuItem(
                          onPressed: () =>
                              unawaited(_run('HelmyCanvas.focus(${jsonEncode(s.file)})')),
                          child: Text(s.title),
                        ),
                    ],
                    builder: (context, menu) => Button(
                      variant: .ghost,
                      size: .sm,
                      onPressed: _screens.isEmpty ? null : menu.open,
                      trailing: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
                      child: Text(
                        [
                          if (_title.isNotEmpty) _title,
                          '${_screens.length} screen${_screens.length == 1 ? '' : 's'}',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: 'Select and edit (V)',
                child: Button(
                  variant: _tool == 'select' ? .secondary : .ghost,
                  size: .iconXs,
                  semanticLabel: 'Select and edit',
                  onPressed: () => _useTool('select'),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.mousePointer2, size: 14),
                ),
              ),
              Tooltip(
                message: 'Move around (H, or hold Space)',
                child: Button(
                  variant: _tool == 'hand' ? .secondary : .ghost,
                  size: .iconXs,
                  semanticLabel: 'Move around',
                  onPressed: () => _useTool('hand'),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.hand, size: 14),
                ),
              ),
              Tooltip(
                message: 'Comment, for the agent (C)',
                child: Button(
                  variant: _tool == 'comment' ? .secondary : .ghost,
                  size: .iconXs,
                  semanticLabel: 'Comment',
                  onPressed: () => _useTool('comment'),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.messageSquarePlus, size: 14),
                ),
              ),
              tool(
                AshlarIconsRoundedStroke.undo2,
                'Undo (⌘Z)',
                () => unawaited(_run('HelmyCanvas.undo()')),
              ),
              Container(
                width: 1,
                height: 16,
                margin: const .symmetric(horizontal: 4),
                color: c.border,
              ),
              tool(
                AshlarIconsRoundedStroke.zoomOut,
                'Zoom out',
                () => unawaited(_run('HelmyCanvas.zoomOut()')),
              ),
              Tooltip(
                message: 'Fit everything',
                child: Button(
                  variant: .ghost,
                  size: .sm,
                  semanticLabel: 'Zoom ${(_zoom * 100).round()}%. Fit everything',
                  onPressed: () => unawaited(_run('HelmyCanvas.fit()')),
                  child: Text(
                    '${(_zoom * 100).round()}%',
                    style: t.text.xs.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
              tool(
                AshlarIconsRoundedStroke.zoomIn,
                'Zoom in',
                () => unawaited(_run('HelmyCanvas.zoomIn()')),
              ),
              tool(AshlarIconsRoundedStroke.folderOpen, 'Show the files', () {
                if (_folder case final f?) unawaited(widget.vm.reveal(f));
              }),
            ],
          ),
        ),
        if (_problem != null)
          Padding(
            padding: const .fromLTRB(12, 0, 12, 6),
            child: Text(_problem!, style: t.text.xs.copyWith(color: c.destructive)),
          ),
        Container(height: 1, color: c.border),
        Expanded(
          child: Stack(
            children: [
              Focus(
                focusNode: _keys,
                child: WindowWebView(controller: _c),
              ),
              // A click on the canvas while a menu is open closes the menu.
              ValueListenableBuilder(
                valueListenable: openOverlays,
                builder: (context, open, _) => open > 0
                    ? const Positioned.fill(child: ColoredBox(color: Color(0x00000000)))
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
