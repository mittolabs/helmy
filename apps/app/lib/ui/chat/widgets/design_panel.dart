import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(_c.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_c.addJavaScriptChannel('Helmy', onMessageReceived: (m) => _fromPage(m.message)));
    widget.vm.addListener(_follow);
    _follow();
  }

  @override
  void dispose() {
    widget.vm.removeListener(_follow);
    unawaited(_watch?.cancel());
    _settle?.cancel();
    _look?.cancel();
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
      _changed.add(e.path.substring(folder.length + 1));
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
        Container(height: 1, color: c.border),
        Expanded(
          child: Stack(
            children: [
              WindowWebView(controller: _c),
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
