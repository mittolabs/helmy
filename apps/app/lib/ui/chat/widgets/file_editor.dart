import 'dart:async';

import 'package:file_selector/file_selector.dart';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/code_highlight.dart';
import '../view_models/chat_view_model.dart';
import '../view_models/file_document.dart';
import '../../../utils/file_tree.dart' show languageOf;
import 'step_input.dart' show CodeColors;
import 'numbered_code_input.dart';

class _CodeController extends TextEditingController {
  _CodeController(this.path, this.language);
  final String path;
  final String? language;
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = (style ?? const TextStyle()).copyWith(fontFamily: 'monospace', height: 1.6);
    if (withComposing && value.composing.isValid && !value.composing.isCollapsed) {
      return super.buildTextSpan(context: context, style: base, withComposing: true);
    }
    return CodeHighlighter.spans(
          text,
          language ?? languageOf(path),
          base,
          CodeColors.of(context),
        ) ??
        TextSpan(text: text, style: base);
  }
}

/// A file in its own side-panel tab, with explicit saves and conflict detection.
class FileEditor extends StatefulWidget {
  const FileEditor({
    super.key,
    required this.vm,
    required this.tab,
    this.document,
    this.onDirtyChanged,
    this.showPath = true,
  });
  final ChatViewModel vm;
  final PanelTab tab;
  final FileDocument? document;
  final ValueChanged<bool>? onDirtyChanged;
  final bool showPath;
  @override
  State<FileEditor> createState() => _FileEditorState();
}

class _FileEditorState extends State<FileEditor> {
  late final FileDocument _doc;
  late final _CodeController _code;
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _findFocus = FocusNode();
  bool _find = false;
  String? _findStatus;

  @override
  void initState() {
    super.initState();
    _doc =
        widget.document ??
        (widget.tab.filePath != null
            ? FileDocument(widget.tab.filePath!)
            : FileDocument.fromText('', widget.tab.codeDraft ?? ''));
    _code = _CodeController(_doc.path, widget.tab.codeLanguage);
    _doc.addListener(_changed);
    _code.addListener(_edited);
    if (_doc.loaded) {
      _code.text = _doc.text;
    } else {
      unawaited(_reload());
    }
  }

  Future<void> _reload() async {
    await _doc.load();
    if (mounted && _doc.loaded) _code.text = _doc.text;
  }

  Future<void> _save() async {
    if (_doc.path.isEmpty) {
      final extension = switch (widget.tab.codeLanguage) {
        'javascript' => 'js',
        'typescript' => 'ts',
        'python' => 'py',
        'bash' || 'shell' => 'sh',
        'ruby' => 'rb',
        'rust' => 'rs',
        final language? when RegExp(r'^[a-z0-9]+$').hasMatch(language) => language,
        _ => 'txt',
      };
      final location = await getSaveLocation(
        suggestedName: 'snippet.$extension',
        initialDirectory: widget.vm.session?.cwd,
      );
      if (location == null || !mounted) return;
      if (await _doc.saveAs(location.path) && mounted) {
        widget.tab
          ..filePath = _doc.path
          ..codeDraft = null;
        widget.vm.fileSaved();
      }
    } else if (await _doc.save() && mounted) {
      widget.vm.fileSaved();
    }
  }

  void _edited() {
    if (_code.text != _doc.text) _doc.edit(_code.text);
    if (mounted) setState(() {});
  }

  void _changed() {
    widget.tab.hasUnsavedEdits = _doc.dirty;
    widget.onDirtyChanged?.call(_doc.dirty);
    widget.vm.panelChanged();
    if (mounted) setState(() {});
  }

  void _showFind() {
    setState(() => _find = true);
    _findFocus.requestFocus();
  }

  void _findNext() {
    final q = _search.text;
    if (q.isEmpty) return;
    final text = _code.text.toLowerCase();
    var at = text.indexOf(q.toLowerCase(), _code.selection.isValid ? _code.selection.end : 0);
    if (at < 0) at = text.indexOf(q.toLowerCase());
    setState(() => _findStatus = at < 0 ? 'No matches' : null);
    if (at >= 0) {
      _code.selection = TextSelection(baseOffset: at, extentOffset: at + q.length);
      _focus.requestFocus();
    }
  }

  void _tab() {
    if (!_focus.hasFocus) {
      FocusScope.of(context).nextFocus();
      return;
    }
    final value = _code.value;
    final selection = value.selection;
    if (!selection.isValid) return;
    _code.value = value.copyWith(
      text: value.text.replaceRange(selection.start, selection.end, '  '),
      selection: TextSelection.collapsed(offset: selection.start + 2),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _doc.removeListener(_changed);
    _doc.dispose();
    _code.dispose();
    _search.dispose();
    _focus.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final cwd = widget.vm.session?.cwd;
    final shownPath = cwd != null && _doc.path.startsWith('$cwd/')
        ? _doc.path.substring(cwd.length + 1)
        : _doc.path;
    final offset = _code.selection.isValid ? _code.selection.extentOffset : 0;
    final before = _code.text.substring(0, offset.clamp(0, _code.text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = before.length - before.lastIndexOf('\n');
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () => unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _showFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _showFind,
        const SingleActivator(LogicalKeyboardKey.tab): _tab,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Button(
                  size: .sm,
                  onPressed: !_doc.dirty || _doc.saving ? null : _save,
                  child: Text(_doc.saving ? 'Saving…' : (_doc.path.isEmpty ? 'Save as…' : 'Save')),
                ),
                Button(
                  size: .sm,
                  variant: .ghost,
                  onPressed: !_doc.dirty || _doc.saving
                      ? null
                      : () {
                          if (_doc.path.isEmpty) {
                            widget.tab.hasUnsavedEdits = false;
                            widget.vm.closeTab(widget.tab);
                            return;
                          }
                          _doc.discard();
                          _code.text = _doc.text;
                        },
                  child: Text(_doc.path.isEmpty ? 'Discard draft' : 'Discard edits'),
                ),
                Button(
                  size: .iconSm,
                  variant: .ghost,
                  semanticLabel: 'Find in file',
                  onPressed: () => setState(() => _find = !_find),
                  child: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 16),
                ),
                Button(
                  size: .sm,
                  variant: .ghost,
                  onPressed: _doc.dirty || _doc.saving || _doc.path.isEmpty ? null : _reload,
                  child: const Text('Reload'),
                ),
              ],
            ),
          ),
          if (widget.showPath)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
              child: Text(
                _doc.path.isEmpty ? 'Code draft · choose Save as… to create a file' : shownPath,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          if (_find)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Input(
                      controller: _search,
                      focusNode: _findFocus,
                      autofocus: true,
                      placeholder: 'Find in file',
                      semanticLabel: 'Find in file',
                      onSubmitted: (_) => _findNext(),
                    ),
                  ),
                  Button(
                    size: .sm,
                    variant: .ghost,
                    onPressed: _findNext,
                    child: const Text('Next'),
                  ),
                  if (_findStatus != null) Text(_findStatus!, style: t.text.xs),
                ],
              ),
            ),
          if (_doc.error case final error?)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
              child: Text(error, style: t.text.sm.copyWith(color: t.colors.destructive)),
            ),
          Expanded(
            child: !_doc.loaded
                ? (_doc.error == null ? const Center(child: Spinner()) : const SizedBox.shrink())
                : ScrollArea(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 16),
                    child: NumberedCodeInput(controller: _code, focusNode: _focus),
                  ),
          ),
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 6),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.colors.border)),
            ),
            child: Text(
              '${_doc.dirty ? 'Unsaved edits — save or discard to close' : (_doc.loaded ? 'Saved' : 'Loading…')} · Ln $line, Col $column · ${widget.tab.codeLanguage ?? languageOf(_doc.path) ?? 'Plain text'}',
              style: t.text.xs.copyWith(color: t.colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
