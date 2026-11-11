import '../../core/window_web_view.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../data/services/engines/attachments.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../../data/services/editors.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/markdown.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/selection.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/file_actions.dart';
import 'media.dart';
import 'player.dart';
import 'project_menu.dart' show appIcon;

/// Shows [path] in a popup over the app, whatever can be attached: a picture
/// as pixels; a video or a sound in Helmy's own player; a PDF's pages; an
/// office document (Word, Excel, PowerPoint, Pages, Numbers, Keynote, RTF),
/// a HEIC or a TIFF as the picture macOS makes of it; markdown read as a
/// document; any other text as plain text, a page's HTML and an SVG's
/// included; anything else by its name, with Open.
///
/// Only for you to look at. Nothing in the file runs: no page is rendered,
/// no script runs, no link is followed unless you press it, nothing is
/// fetched. The one web view, for a PDF's pages, has JavaScript off and goes
/// nowhere but the file. And nothing reaches the agent: this is not the
/// Preview panel the agent can see and drive, and it adds nothing to the
/// conversation. Words inside a file cannot become instructions by being
/// looked at.
Future<void> showFilePopup(
  BuildContext context,
  String path,
  MediaActions actions, {
  EditorChoice? editors,
}) async {
  if (!File(path).existsSync()) return;
  await showAshlarDialog<void>(
    context: context,
    builder: (context) => _FilePopup(path: path, actions: actions, editors: editors),
  );
}

/// The apps a code file can open in: the usual one first, the rest in a
/// menu; [open] opens the file in one (null: the usual), and a chosen one
/// becomes the usual.
typedef EditorChoice = ({
  List<Editor> all,
  Editor? usual,
  Future<bool> Function(Editor? app, String path) open,
});

/// Code, by extension, and the language its highlighting goes by.
const codeLanguages = {
  'dart': 'dart',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'rb': 'ruby',
  'go': 'go',
  'rs': 'rust',
  'swift': 'swift',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'java': 'java',
  'c': 'c',
  'h': 'c',
  'cc': 'cpp',
  'cpp': 'cpp',
  'hpp': 'cpp',
  'm': 'objectivec',
  'mm': 'objectivec',
  'cs': 'csharp',
  'php': 'php',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'fish': 'bash',
  'ps1': 'powershell',
  'sql': 'sql',
  'json': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'toml',
  'xml': 'xml',
  'html': 'xml',
  'htm': 'xml',
  'svg': 'xml',
  'css': 'css',
  'scss': 'scss',
  'less': 'less',
  'gradle': 'gradle',
  'lua': 'lua',
  'r': 'r',
  'scala': 'scala',
  'ex': 'elixir',
  'exs': 'elixir',
  'erl': 'erlang',
  'hs': 'haskell',
  'clj': 'clojure',
  'vue': 'xml',
  'svelte': 'xml',
  'dockerfile': 'dockerfile',
  'makefile': 'makefile',
  'tf': 'ini',
  'ini': 'ini',
  'env': 'bash',
  'graphql': 'graphql',
  'proto': 'protobuf',
  'diff': 'diff',
  'patch': 'diff',
};

/// The most lines highlighted; past it the rest is a press of Open away.
const _codeLines = 4000;

/// The largest text shown; the rest is a press of Open away.
const _textLimit = 200 * 1024;

class _FilePopup extends StatelessWidget {
  const _FilePopup({required this.path, required this.actions, this.editors});
  final String path;
  final MediaActions actions;
  final EditorChoice? editors;

  /// The language when it is code: by extension, or by name (Makefile, Dockerfile).
  String? get _language => codeLanguages[_ext] ?? codeLanguages[path.split('/').last.toLowerCase()];

  String get _ext => path.split('.').last.toLowerCase();

  /// Pictures drawn here directly; HEIC and TIFF go through macOS.
  bool get _picture => const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(_ext);

  /// The file as text when it is text: no NUL bytes in its start, and UTF-8
  /// (anything malformed shown as such, never interpreted).
  static ({String text, bool cut})? _textOf(String path) {
    try {
      final f = File(path);
      final size = f.lengthSync();
      final raf = f.openSync();
      final bytes = raf.readSync(math.min(size, _textLimit));
      raf.closeSync();
      if (bytes.take(4096).contains(0)) return null;
      return (text: utf8.decode(bytes, allowMalformed: true), cut: size > _textLimit);
    } on FileSystemException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final window = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final name = path.split('/').last;
    final maxW = window.width * .9, maxH = window.height * .9 - 52;
    final kind = kindOf(path);
    final shownElse =
        _picture ||
        kind == .video ||
        kind == .audio ||
        kind == .quickLook ||
        kind == .image ||
        _ext == 'pdf';
    final text = shownElse ? null : _textOf(path);
    final wide = math.min(maxW, 960.0), tall = math.min(maxH, 620.0);

    final Widget body;
    if ((kind == .video || kind == .audio) && playerHere) {
      body = SizedBox(
        width: wide,
        height: kind == .video ? tall : null,
        child: Player(path: path, words: name, video: kind == .video, actions: actions),
      );
    } else if (_ext == 'pdf' && webViewHere) {
      body = SizedBox(
        width: wide,
        height: tall,
        child: _Pdf(path: path),
      );
    } else if (_ext == 'rtf') {
      // Its words: macOS's picture of RTF is dark on dark in dark mode.
      body = FutureBuilder(
        future: actions.documentText(path),
        builder: (context, snap) => snap.connectionState != .done
            ? const SizedBox(width: 320, height: 200, child: Center(child: Spinner(size: 16)))
            : snap.data == null
            ? const _Unshown(text: 'No preview of this one. Open it in its own app.')
            : Container(
                constraints: BoxConstraints(maxWidth: math.min(maxW, 820), maxHeight: maxH),
                color: c.background,
                child: ScrollArea(
                  child: Padding(
                    padding: const .all(24),
                    child: Text(snap.data!, style: t.text.base),
                  ),
                ),
              ),
      );
    } else if (kind == .quickLook || (kind == .image && !_picture) || _ext == 'pdf') {
      body = _Look(path: path, actions: actions, maxHeight: maxH);
    } else if (_picture) {
      body = Image(
        // Decoded no larger than it can be shown: a huge or hostile picture
        // costs no more than a screenful.
        image: ResizeImage(
          FileImage(File(path)),
          width: (maxW * ratio).round(),
          policy: ResizeImagePolicy.fit,
          height: (maxH * ratio).round(),
        ),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: name,
        errorBuilder: (context, _, _) => _Unshown(text: "This picture can't be shown."),
      );
    } else if (text != null &&
        const {'md', 'markdown'}.contains(path.split('.').last.toLowerCase())) {
      // Read as a document, still never run: pictures only from beside the
      // file on this Mac (nothing fetched, so no tracking and nothing sent),
      // and a link opens in your browser only when you press it.
      final folder = File(path).parent.path;
      body = Container(
        constraints: BoxConstraints(maxWidth: math.min(maxW, 820), maxHeight: maxH),
        color: c.background,
        child: ScrollArea(
          child: Padding(
            padding: const .fromLTRB(28, 24, 28, 28),
            child: MarkdownMedia(
              show: (url, alt) {
                final local = url.startsWith('/') ? url : '$folder/$url';
                final ok =
                    !url.contains('://') &&
                    imageTypes.containsKey(local.split('.').last.toLowerCase()) &&
                    File(local).existsSync();
                if (ok) {
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: Image(
                      image: ResizeImage(FileImage(File(local)), width: (820 * ratio).round()),
                      fit: BoxFit.contain,
                      alignment: AlignmentDirectional.centerStart,
                      semanticLabel: alt,
                    ),
                  );
                }
                return Text(
                  '[${alt.isEmpty ? 'Picture' : alt}: from the web, not loaded]',
                  style: t.text.sm.copyWith(color: c.mutedForeground),
                );
              },
              child: Markdown(
                text.cut
                    ? '${text.text}\n\n*(The rest is longer than shown here: Open shows all of it.)*'
                    : text.text,
                size: .document,
                onLink: (url) => actions.open(url),
              ),
            ),
          ),
        ),
      );
    } else if (text != null && _language != null) {
      // Highlighted as the conversation's code blocks are; only drawn, never run.
      final lines = text.text.split('\n');
      final shown = lines.length > _codeLines ? lines.take(_codeLines).join('\n') : text.text;
      final more = text.cut || lines.length > _codeLines;
      final fence = '`' * 3 + (shown.contains('`' * 3) ? '`' : '');
      body = Container(
        constraints: BoxConstraints(maxWidth: math.min(maxW, 960), maxHeight: maxH),
        color: c.background,
        child: ScrollArea(
          child: Padding(
            padding: const .all(12),
            child: Markdown(
              '$fence${_language!}\n$shown\n$fence${more ? '\n\n*(Longer than shown here: open it to read the rest.)*' : ''}',
              size: .document,
            ),
          ),
        ),
      );
    } else if (text != null) {
      body = Container(
        constraints: BoxConstraints(maxWidth: math.min(maxW, 820), maxHeight: maxH),
        color: c.background,
        child: ScrollArea(
          child: Padding(
            padding: const .all(16),
            child: Text(
              text.cut
                  ? '${text.text}\n\n(The rest is longer than shown here: Open shows all of it.)'
                  : text.text,
              style: t.text.sm.copyWith(
                fontFamily: 'monospace',
                fontFamilyFallback: const ['Menlo', 'Courier'],
              ),
            ),
          ),
        ),
      );
    } else {
      body = const _Unshown(text: 'This file has nothing to show here. Open it in its own app.');
    }

    Widget action(String label, IconData icon, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconSm,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 15, color: c.foreground),
      ),
    );

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: window.height * .9),
            child: Container(
              decoration: BoxDecoration(
                color: c.popover,
                border: Border.all(color: c.border),
                borderRadius: .circular(12),
                boxShadow: t.shadowLg,
              ),
              clipBehavior: .antiAlias,
              // As wide as what it shows, its bar across all of it.
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .stretch,
                  children: [
                    Flexible(
                      child: SelectableRegion(
                        selectionControls: AshlarSelectionControls(c.foreground),
                        contextMenuBuilder: (context, state) => AshlarSelectionMenu(
                          anchors: state.contextMenuAnchors,
                          items: state.contextMenuButtonItems,
                        ),
                        child: actions is CodeFileActions
                            ? MarkdownCodeAction(
                                open: (code, language) {
                                  Navigator.pop(context);
                                  (actions as CodeFileActions).editCode(code, language);
                                },
                                child: body,
                              )
                            : body,
                      ),
                    ),
                    Container(
                      height: 44,
                      padding: const .symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: Row(
                        spacing: 2,
                        children: [
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: t.text.sm.copyWith(color: c.foreground),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_picture)
                            action(
                              'Copy',
                              AshlarIconsRoundedStroke.copy,
                              () => actions.copyImage(path),
                            ),
                          if (actions case final CodeFileActions code
                              when _language != null || text != null)
                            action('Edit in Helmy', AshlarIconsRoundedStroke.filePen, () {
                              Navigator.pop(context);
                              code.editFile(path);
                            }),
                          if (editors case final e?
                              when e.usual != null && (_language != null || text != null))
                            _EditorButton(path: path, choice: e),
                          action('Open', AshlarIconsRoundedStroke.externalLink, () {
                            Navigator.pop(context);
                            actions.open(path);
                          }),
                          action('Show in Finder', AshlarIconsRoundedStroke.folderOpen, () {
                            Navigator.pop(context);
                            actions.reveal(path);
                          }),
                          action('Close', AshlarIconsRoundedStroke.x, () => Navigator.pop(context)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Unshown extends StatelessWidget {
  const _Unshown({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 32, vertical: 40),
      child: Text(text, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
    );
  }
}

/// A PDF's pages, read in place: JavaScript off, and the view goes nowhere
/// but this file (a link in it opens nothing).
class _Pdf extends StatefulWidget {
  const _Pdf({required this.path});
  final String path;

  @override
  State<_Pdf> createState() => _PdfState();
}

class _PdfState extends State<_Pdf> {
  late final _c = WebViewController();

  @override
  void initState() {
    super.initState();
    final file = Uri.file(widget.path).toString();
    unawaited(() async {
      await _c.setJavaScriptMode(JavaScriptMode.disabled);
      await _c.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (r) =>
              r.url == file ? NavigationDecision.navigate : NavigationDecision.prevent,
        ),
      );
      await _c.loadFile(widget.path);
    }());
  }

  @override
  Widget build(BuildContext context) => WindowWebView(controller: _c);
}

/// The picture macOS makes of a file (Quick Look): an office document's
/// first page, a HEIC, a TIFF. Only pixels come back.
class _Look extends StatelessWidget {
  const _Look({required this.path, required this.actions, required this.maxHeight});
  final String path;
  final MediaActions actions;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: actions.documentPicture(path),
    builder: (context, snap) {
      if (snap.connectionState != .done) {
        return const SizedBox(width: 320, height: 200, child: Center(child: Spinner(size: 16)));
      }
      final picture = snap.data;
      if (picture == null) {
        return const _Unshown(text: 'No preview of this one. Open it in its own app.');
      }
      // A document is paper: its picture is drawn clear, so give it a page.
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          color: const Color(0xFFFFFFFF),
          child: Image.file(File(picture), fit: BoxFit.contain),
        ),
      );
    },
  );
}

/// Open in the usual editor, by its own icon, with the others in a menu.
class _EditorButton extends StatelessWidget {
  const _EditorButton({required this.path, required this.choice});
  final String path;
  final EditorChoice choice;

  @override
  Widget build(BuildContext context) {
    final usual = choice.usual!;
    final others = [
      for (final e in choice.all)
        if (e.id != usual.id && e.kind != .terminal) e,
    ];
    void go(Editor? app) {
      Navigator.pop(context);
      choice.open(app, path);
    }

    return Row(
      mainAxisSize: .min,
      children: [
        Tooltip(
          message: 'Open in ${usual.name}',
          child: Button(
            variant: .ghost,
            size: .sm,
            semanticLabel: 'Open in ${usual.name}',
            onPressed: () => go(null),
            leading: appIcon(usual, size: 15),
            child: Text(usual.name),
          ),
        ),
        if (others.isNotEmpty)
          DropdownMenu(
            side: .top,
            align: .end,
            items: [
              for (final e in others)
                MenuItem(
                  leading: appIcon(e, size: 15),
                  onPressed: () => go(e),
                  child: Text('Open in ${e.name}'),
                ),
            ],
            builder: (context, menu) => Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'Open in another app',
              onPressed: menu.open,
              child: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 13),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}
