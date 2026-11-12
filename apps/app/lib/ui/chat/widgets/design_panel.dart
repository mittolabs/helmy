import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/design_server.dart';
import '../../../domain/design_export/export.dart';
import '../../../domain/design_export/subset.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/toast.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/popover.dart' show PopoverPanel, openOverlays;
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/window_web_view.dart';
import '../../core/windows.dart';
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
    final found = await DesignServer.shared.canvasFor(folder);
    // Where Helmy opens windows of its own, a screen previews in one.
    final canvas = HelmyWindows.supported
        ? found.replace(
            queryParameters: {
              ...found.queryParameters,
              'windows': '1',
              if (_presents) 'play': 'present',
            },
          )
        : found;
    // Where this chat last looked at its canvas, put back.
    final v = widget.vm.designView;
    await _c.loadRequest(
      v == null
          ? canvas
          : canvas.replace(
              queryParameters: {...canvas.queryParameters, 'v': '${v['x']},${v['y']},${v['s']}'},
            ),
    );
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
        unawaited(_check());
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
    // Where the canvas was looked at; what ▶ plays is kept beside it.
    if (m['view'] case final Map v) {
      widget.vm.setDesignView({...?widget.vm.designView, ...v.cast<String, Object?>()});
    }
    if (m['loaded'] case final Map l) {
      unawaited(_check());
      setState(() {
        _title = '${l['title'] ?? ''}';
        _screens = [
          for (final s in (l['screens'] as List? ?? const []).whereType<Map>())
            (file: '${s['file']}', title: '${s['title']}'),
        ];
      });
    }
    if (m['download'] case final String file) {
      // Its menu under the screen's button: the HTML file, or exported as code.
      _openScreenMenu(file, _ScreenMenu.save, m['at']);
    }
    // Beside ▶: Preview or Present.
    if (m['playMenu'] case final String file) _openScreenMenu(file, _ScreenMenu.play, m['at']);
    if (m['present'] case final Map p) unawaited(_present(p));
    // A screen opened in a browser tab of the panel, from its preview.
    if (m['open'] case final String url) widget.vm.preview(url);
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
  /// What in the design will not convert 1:1 to app code (Flutter), checked
  /// again as its files change.
  List<SubsetIssue> _issues = const [];
  int _checking = 0;

  Future<void> _check() async {
    final folder = _folder;
    if (folder == null || !File('$folder/canvas.json').existsSync()) return;
    final mine = ++_checking;
    try {
      final found = await checkDesign(folder);
      if (mounted && mine == _checking) setState(() => _issues = found);
    } on Object {
      // Mid-write: checked again when it settles.
    }
  }

  /// The screen's name on the canvas, for [file].
  String _screenTitle(String file) =>
      _screens.where((s) => s.file == file).firstOrNull?.title ?? file;

  /// Asks for the design to be brought inside what converts, in the chat.
  void _askToFix() {
    final lines = [
      for (final i in _issues) '- ${_screenTitle(i.file)} (design/${i.file}): ${i.what}. ${i.why}',
    ];
    widget.vm.send.execute(
      'Change the design so every screen converts exactly to app code. These are outside it:\n'
      '${lines.join('\n')}\n'
      'Keep each screen looking the same.',
    );
  }

  /// Writes the design out as [target], into a folder of its own inside one
  /// the person picks, and shows it.
  Future<void> _export(ExportTarget target, {String? screen}) async {
    final design = _folder;
    if (design == null) return;
    final into = await getDirectoryPath(confirmButtonText: 'Export here');
    if (into == null || !mounted) return;
    final whole = _title.isEmpty ? 'Design' : _title;
    final name = (screen == null ? whole : '$whole, ${_screenTitle(screen)}').replaceAll(
      RegExp(r'[/:\\]'),
      '-',
    );
    var to = Directory('$into/$name (${target.label})');
    for (var n = 2; to.existsSync(); n++) {
      to = Directory('$into/$name (${target.label}) $n');
    }
    try {
      final files = await exportDesign(
        design,
        to.path,
        target,
        only: screen == null ? null : {screen},
      );
      if (!mounted) return;
      showToast(
        context,
        title: 'Exported as ${target.label}',
        description: '${files.length} files in ${tildePath(to.path)}',
      );
      await widget.vm.reveal(to.path);
    } on Object catch (e) {
      if (!mounted) return;
      showToast(context, title: "Couldn't export it", description: '$e', type: .error);
    }
  }

  /// The menu a screen's buttons open (save, or what ▶ plays), which, and
  /// the screen it is for.
  final _screenMenu = MenuController();
  var _screenMenuKind = _ScreenMenu.save;
  String? _screenMenuFile;

  void _openScreenMenu(String file, _ScreenMenu kind, Object? at) {
    final xy = at is List ? at.whereType<num>().toList() : const <num>[];
    setState(() {
      _screenMenuFile = file;
      _screenMenuKind = kind;
    });
    _screenMenu.open(
      position: xy.length == 2 ? Offset(xy[0].toDouble(), xy[1].toDouble()) : Offset.zero,
    );
  }

  /// What ▶ plays, as this chat last chose: Preview (over the canvas) or
  /// Present (a window of its own).
  bool get _presents => widget.vm.designView?['play'] == 'present';

  /// ▶ plays [present] from now on, and plays it now on [file].
  void _choosePlay(String file, {required bool present}) {
    widget.vm.setDesignView({...?widget.vm.designView, 'play': present ? 'present' : 'preview'});
    unawaited(
      _run('HelmyCanvas.play(${jsonEncode(present ? 'present' : 'preview')}, ${jsonEncode(file)})'),
    );
  }

  /// Present: the screen, working, in a window of its own, the size of its
  /// device: a phone or tablet in its frame with room around it, a desktop
  /// screen as the window itself, its page reflowing as it is resized.
  Future<void> _present(Map p) async {
    final folder = _folder;
    final file = p['file'];
    if (folder == null || file is! String) return;
    final device = p['device'] is String ? p['device'] as String : 'desktop';
    final w = (p['w'] as num?)?.toDouble() ?? 1440;
    final h = (p['h'] as num?)?.toDouble() ?? 900;
    // The frame's border, the room around it and the bar above: as the page draws them.
    final size = switch (device) {
      'phone' => Size(w + 24 + 48, h + 24 + 80),
      'tablet' => Size(w + 32 + 48, h + 32 + 80),
      _ => Size(w, h + 44),
    };
    final canvas = await DesignServer.shared.canvasFor(folder);
    if (!mounted) return;
    final screen = '${p['title'] ?? file}';
    context.read<HelmyWindows>().present(
      canvas.replace(queryParameters: {...canvas.queryParameters, 'present': file}),
      title: _title.isEmpty ? screen : '$_title · $screen',
      size: size,
      device: device,
    );
  }

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
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _build(context, roomy: box.maxWidth >= 520));

  /// [roomy]: wide enough for the toolbar's larger buttons.
  Widget _build(BuildContext context, {required bool roomy}) {
    final button = roomy ? ButtonSize.iconSm : ButtonSize.iconXs;
    final double glyph = roomy ? 16 : 14;
    final t = AshlarTheme.of(context);
    final c = t.colors;
    Widget tool(IconData icon, String label, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: button,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: glyph),
      ),
    );
    // Between the groups: the tools, undo, then zoom and the files.
    final divider = Container(
      width: 1,
      height: 18,
      margin: const .symmetric(horizontal: 6),
      color: c.border,
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
                      trailing: AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
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
                  size: button,
                  semanticLabel: 'Select and edit',
                  onPressed: () => _useTool('select'),
                  child: AshlarIcon(AshlarIconsRoundedStroke.mousePointer2, size: glyph),
                ),
              ),
              Tooltip(
                message: 'Move around (H, or hold Space)',
                child: Button(
                  variant: _tool == 'hand' ? .secondary : .ghost,
                  size: button,
                  semanticLabel: 'Move around',
                  onPressed: () => _useTool('hand'),
                  child: AshlarIcon(AshlarIconsRoundedStroke.hand, size: glyph),
                ),
              ),
              Tooltip(
                message: 'Comment, for the agent (C)',
                child: Button(
                  variant: _tool == 'comment' ? .secondary : .ghost,
                  size: button,
                  semanticLabel: 'Comment',
                  onPressed: () => _useTool('comment'),
                  child: AshlarIcon(AshlarIconsRoundedStroke.messageSquarePlus, size: glyph),
                ),
              ),
              divider,
              tool(
                AshlarIconsRoundedStroke.undo2,
                'Undo (⌘Z)',
                () => unawaited(_run('HelmyCanvas.undo()')),
              ),
              divider,
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
              if (_issues.isNotEmpty)
                DropdownMenu(
                  align: .end,
                  width: 420,
                  items: [
                    for (final i in _issues.take(40))
                      MenuItem(
                        onPressed: () => unawaited(
                          _run(
                            'HelmyCanvas.show(${jsonEncode(i.file)}, ${jsonEncode(i.selector)})',
                          ),
                        ),
                        child: Tooltip(
                          message: i.why,
                          child: Text(
                            '${_screenTitle(i.file)}: ${i.what}',
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                      ),
                    if (_issues.length > 40)
                      MenuLabel(child: Text('And ${_issues.length - 40} more')),
                    const MenuSeparator(),
                    MenuItem(
                      leading: const AshlarIcon(AshlarIconsRoundedStroke.sparkles, size: 16),
                      onPressed: _askToFix,
                      child: const Text('Ask Helmy to fix them'),
                    ),
                  ],
                  builder: (context, menu) => Tooltip(
                    message:
                        'Outside what converts exactly to app code. The web and React exports '
                        'are still exact.',
                    child: Button(
                      variant: .ghost,
                      size: .sm,
                      onPressed: menu.open,
                      leading: AshlarIcon(
                        AshlarIconsRoundedStroke.triangleAlert,
                        size: 14,
                        color: c.mutedForeground,
                      ),
                      child: Text(
                        roomy ? '${_issues.length} won\'t convert to Flutter' : '${_issues.length}',
                        style: t.text.xs.copyWith(color: c.mutedForeground),
                      ),
                    ),
                  ),
                ),
              DropdownMenu(
                align: .end,
                items: [
                  for (final target in ExportTarget.values)
                    MenuItem(
                      onPressed: _screens.isEmpty ? null : () => unawaited(_export(target)),
                      child: Text('${target.label}: ${target.description}'),
                    ),
                ],
                builder: (context, menu) => Tooltip(
                  message: 'Export as code',
                  child: Button(
                    variant: .ghost,
                    size: button,
                    semanticLabel: 'Export as code',
                    onPressed: menu.open,
                    child: AshlarIcon(AshlarIconsRoundedStroke.download, size: glyph),
                  ),
                ),
              ),
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
              RawMenuAnchor(
                controller: _screenMenu,
                onOpen: () => openOverlays.value++,
                onClose: () => openOverlays.value = (openOverlays.value - 1).clamp(0, 1 << 30),
                overlayBuilder: (context, info) => PopoverPanel(
                  info: info,
                  child: MenuList(
                    children: _screenMenuKind == _ScreenMenu.play
                        ? [
                            for (final (present, name, what) in [
                              (false, 'Preview', 'Over the canvas'),
                              (true, 'Present', 'In a window of its own'),
                            ])
                              MenuItem(
                                onPressed: () {
                                  _screenMenu.close();
                                  if (_screenMenuFile case final f?) {
                                    _choosePlay(f, present: present);
                                  }
                                },
                                shortcut: Text(present == _presents ? '✓' : ''),
                                child: Text('$name: $what'),
                              ),
                          ]
                        : [
                            MenuItem(
                              onPressed: () {
                                _screenMenu.close();
                                if (_screenMenuFile case final f?) unawaited(_saveCopy(f));
                              },
                              child: const Text('Save the HTML file'),
                            ),
                            const MenuSeparator(),
                            const MenuLabel(child: Text('Export this screen as')),
                            for (final target in ExportTarget.values)
                              MenuItem(
                                onPressed: () {
                                  _screenMenu.close();
                                  if (_screenMenuFile case final f?) {
                                    unawaited(_export(target, screen: f));
                                  }
                                },
                                child: Text('${target.label}: ${target.description}'),
                              ),
                          ],
                  ),
                ),
                child: Focus(
                  focusNode: _keys,
                  child: WindowWebView(controller: _c),
                ),
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

/// Which menu a screen's buttons opened: saving it, or what ▶ plays.
enum _ScreenMenu { save, play }
