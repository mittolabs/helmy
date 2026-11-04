import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../../utils/file_tree.dart';
import '../../../utils/platform.dart';
import '../../../utils/project_files.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/selection.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/code_highlight.dart';
import '../../core/markdown_preview.dart';
import '../view_models/chat_view_model.dart';
import 'chat_items.dart';
import 'project_menu.dart';
import 'step_input.dart';

/// The session's folder: its files as a tree (what git tracks and does not
/// ignore), what this session changed marked in it, and a file read beside
/// it, colored as code, Markdown as it reads, pictures as pictures. Wide,
/// the tree and the file side by side; narrow, one then the other.
class FilesPanel extends StatefulWidget {
  const FilesPanel({super.key, required this.vm, this.active = true});
  final ChatViewModel vm;
  final bool active;

  @override
  State<FilesPanel> createState() => _FilesPanelState();
}

/// What a file holds, as read for showing.
sealed class _Content {}

class _Text extends _Content {
  _Text(this.text);
  final String text;
}

class _Picture extends _Content {}

class _Unreadable extends _Content {
  _Unreadable(this.why);
  final String why;
}

class _FilesPanelState extends State<FilesPanel> {
  List<String>? _files;
  Map<String, String> _changed = const {};
  final _open = <String>{};
  final _filter = TextEditingController();
  String? _selected;
  _Content? _content;
  bool _asCode = false;
  bool _wasBusy = false;

  String get _cwd => widget.vm.session?.cwd ?? homeDir;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    widget.vm.addListener(_onVm);
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onVm);
    _filter.dispose();
    super.dispose();
  }

  /// A turn ended: what it changed shows.
  void _onVm() {
    final busy = widget.vm.busy;
    if (_wasBusy && !busy) unawaited(_load());
    _wasBusy = busy;
  }

  Future<void> _load() async {
    final files = await projectFiles(_cwd, limit: 20000);
    final changes = await widget.vm.changesIn(null) ?? const [];
    if (!mounted) return;
    setState(() {
      _files = files;
      _changed = {for (final c in changes) c.path: c.kind};
    });
    if (_selected != null) unawaited(_read(_selected!));
  }

  Future<void> _read(String path) async {
    final file = File('$_cwd/$path');
    _Content content;
    try {
      if (!file.existsSync()) {
        content = _Unreadable('This file is no longer here.');
      } else if (_isPicture(path)) {
        content = _Picture();
      } else if (file.lengthSync() > 2 * 1024 * 1024) {
        content = _Unreadable('This file is too large to show here.');
      } else {
        final bytes = await file.readAsBytes();
        // A zero byte in the first few thousand: not text.
        if (bytes.take(8000).contains(0)) {
          content = _Unreadable("This file isn't text.");
        } else {
          content = _Text(_untab(utf8.decode(bytes, allowMalformed: true)));
        }
      }
    } on Object {
      content = _Unreadable("This file couldn't be read.");
    }
    if (!mounted) return;
    setState(() => _content = content);
  }

  /// Tabs as the spaces they stand for, at every fourth column: text draws
  /// a tab as one space, which flattens a Makefile's or Go's indents.
  static String _untab(String text) {
    if (!text.contains('\t')) return text;
    return text
        .split('\n')
        .map((line) {
          if (!line.contains('\t')) return line;
          final out = StringBuffer();
          for (final ch in line.split('')) {
            if (ch == '\t') {
              out.write(' ' * (4 - out.length % 4));
            } else {
              out.write(ch);
            }
          }
          return out.toString();
        })
        .join('\n');
  }

  static bool _isPicture(String path) {
    final p = path.toLowerCase();
    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico'].any(p.endsWith);
  }

  void _choose(String path) {
    setState(() {
      _selected = path;
      _content = null;
      _asCode = false;
      _open.addAll(foldersOf(path));
    });
    unawaited(_read(path));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 640;
      final c = AshlarTheme.of(context).colors;
      if (wide) {
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            SizedBox(width: 280, child: _tree(context)),
            Container(width: 1, color: c.border),
            Expanded(child: _viewer(context, back: false)),
          ],
        );
      }
      return _selected == null ? _tree(context) : _viewer(context, back: true);
    },
  );

  Widget _tree(BuildContext context) {
    final t = AshlarTheme.of(context);
    final files = _files;
    final typed = _filter.text.trim();
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(8, 8, 8, 6),
          child: Row(
            spacing: 4,
            children: [
              Expanded(
                child: Input(
                  controller: _filter,
                  size: .sm,
                  placeholder: 'Find a file',
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 14),
                ),
              ),
              Tooltip(
                message: 'Read the folder again',
                child: Button(
                  variant: .ghost,
                  size: .iconSm,
                  semanticLabel: 'Read the folder again',
                  onPressed: _load,
                  child: const AshlarIcon(AshlarIconsRoundedStroke.refreshCw, size: 14),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (files) {
            null => const Center(child: Spinner()),
            [] => Center(
              child: Text(
                'This folder has no files.',
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
            _ when typed.isNotEmpty => _found(context, fuzzyPick(files, typed, count: 200)),
            _ => _rows(context, visibleRows(files, _open)),
          },
        ),
      ],
    );
  }

  /// Files matching what was typed, with the folder each is in.
  Widget _found(BuildContext context, List<String> paths) {
    final t = AshlarTheme.of(context);
    if (paths.isEmpty) {
      return Center(
        child: Text('No file matches.', style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
      );
    }
    return ScrollArea.builder(
      padding: const .fromLTRB(4, 0, 4, 8),
      itemCount: paths.length,
      itemExtent: 28,
      itemBuilder: (context, i) {
        final p = paths[i];
        final slash = p.lastIndexOf('/');
        return _Row(
          name: p.substring(slash + 1),
          detail: slash < 0 ? null : p.substring(0, slash),
          depth: 0,
          icon: _iconOf(p),
          selected: p == _selected,
          change: _changed[p],
          onPressed: () => _choose(p),
        );
      },
    );
  }

  Widget _rows(BuildContext context, List<FileRow> rows) => ScrollArea.builder(
    padding: const .fromLTRB(4, 0, 4, 8),
    itemCount: rows.length,
    itemExtent: 28,
    itemBuilder: (context, i) {
      final r = rows[i];
      final changedInside =
          r.folder && !r.open && _changed.keys.any((p) => p.startsWith('${r.path}/'));
      return _Row(
        name: r.name,
        depth: r.depth,
        folder: r.folder,
        open: r.open,
        icon: r.folder
            ? (r.open ? AshlarIconsRoundedStroke.folderOpen : AshlarIconsRoundedStroke.folder)
            : _iconOf(r.path),
        selected: r.path == _selected,
        change: r.folder ? (changedInside ? 'inside' : null) : _changed[r.path],
        onPressed: () => r.folder
            ? setState(() => r.open ? _open.remove(r.path) : _open.add(r.path))
            : _choose(r.path),
      );
    },
  );

  static IconData _iconOf(String path) => _isPicture(path)
      ? AshlarIconsRoundedStroke.image
      : languageOf(path.split('/').last) != null
      ? AshlarIconsRoundedStroke.fileCode
      : AshlarIconsRoundedStroke.fileText;

  Widget _viewer(BuildContext context, {required bool back}) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final path = _selected;
    if (path == null) {
      return Center(
        child: Text(
          'Choose a file to read it here.',
          style: t.text.sm.copyWith(color: c.mutedForeground),
        ),
      );
    }
    final vm = widget.vm;
    final full = '$_cwd/$path';
    final markdown = languageOf(path) == 'markdown';
    final content = _content;
    Widget tool(String label, Widget icon, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: icon,
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          height: 40,
          padding: const .symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            spacing: 2,
            children: [
              if (back)
                tool(
                  'Back to the files',
                  const AshlarIcon(AshlarIconsRoundedStroke.arrowLeft, size: 14),
                  () => setState(() => _selected = null),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
              ),
              if (markdown && content is _Text)
                tool(
                  _asCode ? 'Show as it reads' : 'Show its source',
                  AshlarIcon(
                    _asCode ? AshlarIconsRoundedStroke.fileText : AshlarIconsRoundedStroke.code,
                    size: 14,
                  ),
                  () => setState(() => _asCode = !_asCode),
                ),
              tool(
                'Ask about it',
                const AshlarIcon(AshlarIconsRoundedStroke.atSign, size: 14),
                () => vm.mention(path),
              ),
              if (vm.editor case final e?)
                tool('Open in ${e.name}', appIcon(e, size: 14), () => vm.openIn(null, full)),
              tool(
                'Copy its path',
                const AshlarIcon(AshlarIconsRoundedStroke.copy, size: 14),
                () => copyWithToast(context, vm, full),
              ),
              tool(
                'Show in Finder',
                const AshlarIcon(AshlarIconsRoundedStroke.folderOpen, size: 14),
                () => vm.reveal(full),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (content) {
            null => const Center(child: Spinner()),
            _Picture() => Padding(
              padding: const .all(16),
              child: Image.file(File(full), fit: .contain),
            ),
            _Unreadable(:final why) => Center(
              child: Column(
                mainAxisSize: .min,
                spacing: 10,
                children: [
                  Text(why, style: t.text.sm.copyWith(color: c.mutedForeground)),
                  Button(
                    size: .sm,
                    variant: .outline,
                    onPressed: () => vm.open(full),
                    child: const Text('Open in its app'),
                  ),
                ],
              ),
            ),
            _Text(:final text) when markdown && !_asCode => ScrollArea(
              padding: const .fromLTRB(20, 16, 20, 24),
              child: _selectable(context, MarkdownPreview(text)),
            ),
            _Text(:final text) => _Code(text: text, language: languageOf(path)),
          },
        ),
      ],
    );
  }
}

/// A file's text with its line numbers, colored as its language is.
class _Code extends StatelessWidget {
  const _Code({required this.text, this.language});
  final String text;
  final String? language;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final style = t.text.xs.copyWith(fontFamily: 'Menlo', fontSize: 12, height: 1.6);
    final lines = '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
    final colored = CodeHighlighter.spans(text, language, style, CodeColors.of(context));
    return ScrollArea(
      padding: const .symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          // The numbers: not selected with the text.
          Padding(
            padding: const .only(left: 12, right: 14),
            child: Text(
              [for (var i = 1; i <= lines; i++) '$i'].join('\n'),
              textAlign: .right,
              style: style.copyWith(color: t.colors.mutedForeground.withValues(alpha: .6)),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: .horizontal,
              padding: const .only(right: 16),
              child: _selectable(context, Text.rich(colored ?? TextSpan(text: text, style: style))),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the tree: indent, an arrow for a folder, its icon and name,
/// and a letter for what this session did to it.
class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.depth,
    required this.icon,
    required this.selected,
    required this.onPressed,
    this.detail,
    this.folder = false,
    this.open = false,
    this.change,
  });
  final String name;
  final String? detail;
  final int depth;
  final IconData icon;
  final bool folder, open, selected;
  final String? change;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final (letter, color, what) = switch (change) {
      'added' || 'new' || 'untracked' => ('A', const Color(0xFF57AB5A), 'Added this session'),
      'deleted' || 'removed' => ('D', c.destructive, 'Deleted this session'),
      'inside' => ('•', const Color(0xFFC69026), 'Something in it changed this session'),
      null => ('', c.mutedForeground, ''),
      _ => ('M', const Color(0xFFC69026), 'Changed this session'),
    };
    return Pressable(
      onPressed: onPressed,
      semanticLabel: folder ? '$name, folder' : name,
      builder: (context, state) => Container(
        padding: EdgeInsetsDirectional.only(start: 6 + depth * 14.0, end: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.accent
              : state.hovered
              ? c.accent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(6),
        ),
        child: Row(
          spacing: 6,
          children: [
            SizedBox(
              width: 12,
              child: folder
                  ? AshlarIcon(
                      open
                          ? AshlarIconsRoundedStroke.chevronDown
                          : AshlarIconsRoundedStroke.chevronRight,
                      size: 12,
                      color: c.mutedForeground,
                    )
                  : null,
            ),
            AshlarIcon(icon, size: 14, color: c.mutedForeground),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.sm.copyWith(
                  fontSize: 13,
                  color: change == null ? c.foreground : color,
                ),
              ),
            ),
            if (detail case final d?)
              Expanded(
                child: Text(
                  d,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
              )
            else
              const Spacer(),
            if (letter.isNotEmpty)
              Tooltip(
                message: what,
                child: Text(
                  letter,
                  style: t.text.xs.copyWith(color: color, fontWeight: .w600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// [child]'s text selectable and copyable, as the conversation's is.
Widget _selectable(BuildContext context, Widget child) => SelectableRegion(
  selectionControls: AshlarSelectionControls(AshlarTheme.of(context).colors.foreground),
  contextMenuBuilder: (context, state) =>
      AshlarSelectionMenu(anchors: state.contextMenuAnchors, items: state.contextMenuButtonItems),
  child: child,
);
