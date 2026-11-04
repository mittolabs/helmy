import 'dart:io';

import '../../../domain/helmy_voice.dart';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../utils/project_files.dart';
import '../../../utils/starters.dart';
import '../../../data/services/engines/attachments.dart';
import '../../../domain/models/chat_item.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/session.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/message_scroller.dart';
import '../../core/ashlar/pressable.dart';

import 'package:flutter/services.dart';

import '../../core/ashlar/attachment.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/markdown.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/toast.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/selection.dart';
import '../../core/ashlar/shimmer.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../../utils/result.dart';
import '../view_models/chat_view_model.dart';
import '../../core/helmy_dialog.dart';
import 'background_panel.dart';
import 'changes_panel.dart';
import 'media.dart';
import 'preview_panel.dart';
import 'ship_panel.dart';
import 'device_panel.dart';
import 'terminal_panel.dart';
import 'chat_items.dart';
import 'composer.dart';
import 'saved_toast.dart';
import '../../core/window_layout.dart';
import '../../../utils/platform.dart';

part 'screen/composer_area.dart';
part 'screen/empty.dart';
part 'screen/find.dart';
part 'screen/header.dart';
part 'screen/side_panels.dart';

class ChatScreen extends StatefulWidget {
  const new({super.key, required this.viewModel});
  final ChatViewModel viewModel;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// A suggestion under the cursor: what it shows, and the text it puts in place
/// of what was typed.
typedef _Suggestion = ({String label, String detail, String insert});

class _ChatScreenState extends State<ChatScreen> {
  late final _composer = FocusNode(onKeyEvent: _onKey);
  final _text = TextEditingController();
  List<_Suggestion> _suggestions = const [];

  // Find in this session (⌘F).
  bool _finding = false;
  final _find = TextEditingController();
  final _findFocus = FocusNode();
  final _scroller = MessageScrollerController();
  int _hit = 0;

  /// The rows whose text has what is searched for, in order.
  List<int> get _matches {
    final q = _find.text.trim().toLowerCase();
    if (!_finding || q.isEmpty) return const [];
    return [
      for (final (i, item) in vm.items.indexed)
        if (switch (item) {
          UserMessage(:final text) || AssistantText(:final text) => text.toLowerCase().contains(q),
          _ => false,
        })
          i,
    ];
  }

  void _openFind() {
    setState(() => _finding = true);
    _find.selection = TextSelection(baseOffset: 0, extentOffset: _find.text.length);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    setState(() => _finding = false);
    _composer.requestFocus();
  }

  /// Whether the row [id] is the match being shown.
  bool _isHit(Object id) {
    final m = _matches;
    return m.isNotEmpty && m[_hit % m.length] == id;
  }

  /// Moves to the next match ([step] 1) or the one before (-1).
  void _go(int step) {
    final m = _matches;
    if (m.isEmpty) return;
    setState(() => _hit = (_hit + step) % m.length);
    _scroller.scrollToMessage(m[_hit]);
  }

  /// Where the up arrow is in what you sent before; null when not browsing.
  int? _back;

  ChatViewModel get vm => widget.viewModel;

  @override
  void initState() {
    super.initState();
    vm.focusRequests.addListener(_focus);
    _text.addListener(_suggest);
  }

  /// "/" at the start offers commands; "@word" at the cursor offers files.
  Future<void> _suggest() async {
    final text = _text.text;
    final caret = _text.selection.baseOffset < 0 ? text.length : _text.selection.baseOffset;
    final before = text.substring(0, caret.clamp(0, text.length));
    final command = RegExp(r'^/([\w:.-]*)$').firstMatch(before);
    final mention = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    List<_Suggestion> next = const [];
    if (command != null) {
      final typed = command.group(1)!;
      final all = await vm.commands();
      next = [
        for (final c in all.where((c) => c.name.startsWith(typed)).take(8))
          (label: '/${c.name}', detail: withoutNames(c.description), insert: '/${c.name} '),
      ];
    } else if (mention != null) {
      final typed = mention.group(1)!;
      final picked = fuzzyPick(await vm.files(fresh: typed.isEmpty), typed);
      next = [for (final p in picked) (label: p, detail: '', insert: '@$p ')];
    }
    if (!mounted || _text.text != text) return;
    setState(() => _suggestions = next);
  }

  void _sendStarter(String prompt) {
    _text.clear();
    vm.send.execute(prompt);
  }

  /// Puts [s] in place of the word being typed.
  void _take(_Suggestion s) {
    final text = _text.text;
    final caret = _text.selection.baseOffset < 0 ? text.length : _text.selection.baseOffset;
    final before = text.substring(0, caret);
    final start = s.insert.startsWith('/') ? 0 : before.lastIndexOf('@');
    final after = text.substring(caret);
    _text.value = TextEditingValue(
      text: '${text.substring(0, start)}${s.insert}$after',
      selection: TextSelection.collapsed(offset: start + s.insert.length),
    );
    setState(() => _suggestions = const []);
    _composer.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return .ignored;
    final key = e.logicalKey;
    if (key == LogicalKeyboardKey.enter && _suggestions.isNotEmpty) {
      _take(_suggestions.first);
      return .handled;
    }
    // ⇧⌘Enter while the agent works: send now, redirecting it.
    if (key == LogicalKeyboardKey.enter &&
        vm.busy &&
        Desktop.current.commandHeld &&
        HardwareKeyboard.instance.isShiftPressed) {
      final text = _text.text;
      if (text.trim().isEmpty && vm.attachments.isEmpty) return .handled;
      _text.clear();
      _back = null;
      setState(() => _suggestions = const []);
      vm.sendNow(text);
      return .handled;
    }
    final withMeta = !context.read<SettingsRepository>().settings.sendWithEnter;
    if (Composer.handleEnter(e, () => _submit(_text.text), withMeta: withMeta) == .handled) {
      return .handled;
    }
    final meta = Desktop.current.commandHeld;
    if (key == LogicalKeyboardKey.tab && _suggestions.isNotEmpty) {
      _take(_suggestions.first);
      return .handled;
    }
    if (key == LogicalKeyboardKey.escape && _suggestions.isNotEmpty) {
      setState(() => _suggestions = const []);
      return .handled;
    }
    // Up and down walk what you sent before, from an empty box or while walking.
    final history = vm.history;
    if (key == LogicalKeyboardKey.arrowUp &&
        (_text.text.isEmpty || _back != null) &&
        history.isNotEmpty) {
      _back = ((_back ?? history.length) - 1).clamp(0, history.length - 1);
      _put(history[_back!]);
      return .handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && _back != null) {
      _back = _back! + 1;
      if (_back! >= history.length) {
        _back = null;
        _put('');
      } else {
        _put(history[_back!]);
      }
      return .handled;
    }
    // ⌘V: a picture becomes an attachment; anything else pastes as text.
    if (meta && key == LogicalKeyboardKey.keyV) {
      _paste();
      return .handled;
    }
    return .ignored;
  }

  void _put(String text) => _text.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  Future<void> _paste() async {
    if (await vm.pasteImage()) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final paste = data?.text;
    if (paste == null || paste.isEmpty) return;
    final v = _text.value;
    final start = v.selection.start < 0 ? v.text.length : v.selection.start;
    final end = v.selection.end < 0 ? v.text.length : v.selection.end;
    _text.value = TextEditingValue(
      text: v.text.replaceRange(start, end, paste),
      selection: TextSelection.collapsed(offset: start + paste.length),
    );
  }

  void _submit(String text) {
    if (text.trim().isEmpty && vm.attachments.isEmpty) return;
    _text.clear();
    _back = null;
    setState(() => _suggestions = const []);
    vm.send.execute(text);
  }

  void _focus() => _composer.requestFocus();

  @override
  void dispose() {
    vm.focusRequests.removeListener(_focus);
    _composer.dispose();
    _text.dispose();
    _find.dispose();
    _findFocus.dispose();
    _scroller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    // How wide the conversation reads, from settings.
    final column = context.watch<SettingsRepository>().settings.width.pixels;
    Widget inColumn(Widget child) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: column),
        child: child,
      ),
    );
    return CallbackShortcuts(
      bindings: {Desktop.current.shortcut(LogicalKeyboardKey.keyF): _openFind},
      child: ColoredBox(
        color: t.colors.background,
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final session = vm.session;
            if (session == null) {
              return const Center(child: Text('This session no longer exists.'));
            }
            final rows = buildRows(vm);
            return DropTarget(
              onDragDone: (detail) => vm.attach(detail.files.map((f) => f.path)),
              child: _SidePanels(
                vm: vm,
                chat: Column(
                  children: [
                    TitleBar(
                      // Redrawn into or out of full screen, where its start moves.
                      child: ListenableBuilder(
                        listenable: windowFullScreen,
                        builder: (context, _) => _Header(vm: vm, session: session),
                      ),
                    ),
                    if (_finding)
                      _FindBar(
                        controller: _find,
                        focus: _findFocus,
                        count: _matches.length,
                        at: _hit,
                        onChanged: () {
                          setState(() => _hit = 0);
                          final m = _matches;
                          if (m.isNotEmpty) _scroller.scrollToMessage(m.first);
                        },
                        onNext: () => _go(1),
                        onPrevious: () => _go(-1),
                        onClose: _closeFind,
                      ),
                    if (vm.items.isEmpty && !vm.busy && !_finding)
                      Expanded(child: _Hello(offline: vm.onlyThisMac))
                    else
                      Expanded(
                        // As AshlarPageRoute does; go_router pages do not get it by themselves.
                        // What answers show (`![words](where)`): pictures,
                        // players, documents, pages.
                        child: MarkdownMedia(
                          show: (where, words) =>
                              Media(where: where, words: words, cwd: session.cwd, actions: vm),
                          child: _FadeUnderHeader(
                            child: SelectableRegion(
                              selectionControls: AshlarSelectionControls(t.colors.foreground),
                              contextMenuBuilder: (context, state) => AshlarSelectionMenu(
                                anchors: state.contextMenuAnchors,
                                items: state.contextMenuButtonItems,
                              ),
                              child: MessageScroller(
                                controller: _scroller,
                                busy: vm.busy,
                                gap: 14,
                                padding: .fromLTRB(sideMargin(context), 8, sideMargin(context), 32),
                                semanticLabel: 'Conversation',
                                items: [
                                  for (final r in rows)
                                    MessageScrollerItem(
                                      id: r.id,
                                      anchor: r.anchor,
                                      child: inColumn(
                                        Container(
                                          decoration: _isHit(r.id)
                                              ? BoxDecoration(
                                                  color: t.colors.foreground.withValues(alpha: .06),
                                                  borderRadius: .circular(t.radiusLg),
                                                )
                                              : null,
                                          child: Align(
                                            alignment: AlignmentDirectional.centerStart,
                                            child: r.child,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (vm.busy)
                                    MessageScrollerItem(
                                      id: 'working',
                                      child: inColumn(_Working(vm: vm)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (vm.queue.isNotEmpty) inColumn(_Queue(vm: vm)),
                    if (_suggestions.isNotEmpty)
                      inColumn(_SuggestionList(items: _suggestions, onPick: _take))
                    else if (vm.items.isEmpty && !vm.busy)
                      inColumn(_Starters(vm: vm, text: _text, onSend: _sendStarter)),
                    Padding(
                      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 20),
                      child: inColumn(
                        Composer(
                          controller: _text,
                          focusNode: _composer,
                          onSubmit: _submit,
                          placeholder: vm.pendingNeeds.contains(Capability.imageGeneration)
                              ? 'Describe the change to this image'
                              : 'Type / for commands, @ for files',
                          status: vm.busy
                              ? 'Working. What you send waits its turn; ${Desktop.current.keys('⇧⌘Enter')} sends it now instead.'
                              : null,
                          attachments: [
                            for (final path in vm.attachments) _Attached(path: path, vm: vm),
                          ],
                          actions: [
                            ComposerButton(
                              icon: AshlarIconsRoundedStroke.plus,
                              label: 'Attach files (or paste a picture)',
                              onPressed: () async {
                                final files = await openFiles(confirmButtonText: 'Attach');
                                vm.attach(files.map((f) => f.path));
                              },
                            ),
                            Tooltip(
                              message: vm.busy
                                  ? 'Wait for the turn to end to change this'
                                  : 'What Helmy may do without asking',
                              child: _LevelChip(vm: vm, level: session.level),
                            ),
                          ],
                          trailing: [
                            if (vm.busy)
                              ComposerButton(
                                icon: AshlarIconsRoundedStroke.square,
                                label: 'Stop',
                                onPressed: vm.interrupt,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
