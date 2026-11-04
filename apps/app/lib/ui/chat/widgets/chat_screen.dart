import 'dart:io';

import '../../../domain/helmy_voice.dart';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/desktop_service.dart';
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
import 'chat_items.dart';
import 'composer.dart';
import 'saved_toast.dart';
import '../../core/window_layout.dart';
import '../../../utils/platform.dart';

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
    if (await vm.pasteImage(context.read<DesktopService>().pasteImage)) return;
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
                          show: (where, words) => Media(
                            where: where,
                            words: words,
                            cwd: session.cwd,
                            onPreview: vm.preview,
                          ),
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

/// Messages written while the agent works, waiting their turn.
class _Queue extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 8),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 4,
        children: [
          for (final (i, q) in vm.queue.indexed)
            Container(
              padding: const .fromLTRB(12, 6, 4, 6),
              decoration: BoxDecoration(
                border: Border.all(color: t.colors.border),
                borderRadius: .circular(t.radiusMd),
              ),
              child: Row(
                spacing: 8,
                children: [
                  AshlarIcon(
                    AshlarIconsRoundedStroke.clock,
                    size: 14,
                    color: t.colors.mutedForeground,
                  ),
                  Expanded(
                    child: Text(
                      q.text,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                    ),
                  ),
                  Text(
                    i == 0 ? 'Sends next' : 'Waiting',
                    style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                  ),
                  Tooltip(
                    message:
                        'Send now: Helmy takes this up straight away (${Desktop.current.keys('⇧⌘Enter')})',
                    child: Button(
                      variant: .ghost,
                      size: .sm,
                      semanticLabel: 'Send now',
                      onPressed: () => vm.steer(i),
                      child: const Text('Send now'),
                    ),
                  ),
                  Button(
                    variant: .ghost,
                    size: .iconXs,
                    semanticLabel: 'Do not send',
                    onPressed: () => vm.unqueue(i),
                    child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// An empty session's welcome: Helmy waving, or rubbing its eyes when only
/// the model on this Mac can answer.
class _Hello extends StatelessWidget {
  const new({required this.offline});
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const .all(24),
        child: Column(
          mainAxisSize: .min,
          spacing: 12,
          children: [
            Image.asset(
              offline ? 'assets/helmy/offline.png' : 'assets/helmy/hello.png',
              width: 132,
              height: 132,
              semanticLabel: 'Helmy',
            ),
            Text(
              offline
                  ? "I'm working on ${Desktop.current.thisComputer} only"
                  : 'What should we get done?',
              style: t.text.lg.copyWith(fontWeight: .w600),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                offline
                    ? "Nothing online is available right now, so I'm slower, and "
                          "your accounts are out of reach. Your folders aren't."
                    : 'Dream it, do it: tell me what you want, in this folder or '
                          'in your accounts.',
                textAlign: .center,
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An empty session's suggestions, from what its folder holds: one press
/// sends one. Gone once you start typing.
class _Starters extends StatelessWidget {
  const new({required this.vm, required this.text, required this.onSend});
  final ChatViewModel vm;
  final TextEditingController text;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return ValueListenableBuilder(
      valueListenable: text,
      builder: (context, value, _) => value.text.isNotEmpty
          ? const SizedBox.shrink()
          : FutureBuilder(
              future: vm.starters(),
              builder: (context, snap) => Padding(
                padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 8),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final s in snap.data ?? const <Starter>[])
                      Pressable(
                        onPressed: () => onSend(s.prompt),
                        semanticLabel: s.label,
                        builder: (context, state) => Container(
                          padding: const .symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: state.hovered ? t.colors.accent : null,
                            borderRadius: .circular(t.radiusMd),
                          ),
                          child: Row(
                            spacing: 10,
                            children: [
                              AshlarIcon(
                                AshlarIconsRoundedStroke.sparkles,
                                size: 14,
                                color: t.colors.mutedForeground,
                              ),
                              Expanded(
                                child: Text(
                                  s.label,
                                  style: t.text.sm.copyWith(
                                    color: state.hovered
                                        ? t.colors.foreground
                                        : t.colors.mutedForeground,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Commands or files matching what is typed; Tab takes the first.
class _SuggestionList extends StatelessWidget {
  const new({required this.items, required this.onPick});
  final List<_Suggestion> items;
  final ValueChanged<_Suggestion> onPick;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 6),
      child: Container(
        padding: const .all(4),
        decoration: BoxDecoration(
          color: t.colors.popover,
          border: Border.all(color: t.colors.border),
          borderRadius: .circular(t.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            for (final (i, s) in items.indexed)
              Pressable(
                onPressed: () => onPick(s),
                semanticLabel: s.label,
                builder: (context, state) => Container(
                  padding: const .symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: state.hovered || i == 0 ? t.colors.accent : null,
                    borderRadius: .circular(t.radiusMd),
                  ),
                  child: Row(
                    spacing: 12,
                    children: [
                      Text(
                        s.label,
                        style: t.text.sm.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: monoFonts,
                        ),
                      ),
                      if (s.detail.isNotEmpty)
                        Expanded(
                          child: Text(
                            s.detail,
                            maxLines: 1,
                            overflow: .ellipsis,
                            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                          ),
                        ),
                      if (i == 0)
                        Text('Tab', style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The conversation, and beside it the one open panel, as wide as it was
/// last dragged. The conversation keeps room to read: in a narrow window the
/// panel gives way first, and steps aside when even that is too little.
class _SidePanels extends StatelessWidget {
  const new({required this.vm, required this.chat});
  final ChatViewModel vm;
  final Widget chat;

  static const _chatMin = 420.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final p = vm.panel;
      // No room left beside the conversation (a narrow window): no panel.
      final room = box.maxWidth - _chatMin - _Divider.width;
      final width = room <= 0 ? 0.0 : vm.panelWidth.clamp(0.0, room);
      return Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(child: chat),
          if (p != null && width >= 260) ...[
            _Divider(onDrag: (dx) => vm.resize(width - dx)),
            SizedBox(
              width: width,
              child: switch (p) {
                .changes => ChangesPanel(vm: vm),
                .background => BackgroundPanel(vm: vm),
                .preview => PreviewPanel(vm: vm),
              },
            ),
          ],
        ],
      );
    },
  );
}

/// The edge between two columns: a hairline, and a wider strip to drag.
class _Divider extends StatefulWidget {
  const new({required this.onDrag});
  final ValueChanged<double> onDrag;

  static const width = 1.0;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return SizedBox(
      width: _Divider.width,
      child: OverflowBox(
        maxWidth: 9,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hot = true),
          onExit: (_) => setState(() => _hot = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
            child: Center(
              child: Container(
                width: _hot ? 2 : 1,
                color: _hot ? c.foreground.withValues(alpha: .3) : c.border.withValues(alpha: .6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Find in this session: the words, how many places have them, and which one
/// is shown. Enter goes to the next, Shift+Enter back, Esc closes.
class _FindBar extends StatelessWidget {
  const new({
    required this.controller,
    required this.focus,
    required this.count,
    required this.at,
    required this.onChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
  });
  final TextEditingController controller;
  final FocusNode focus;
  final int count, at;
  final VoidCallback onChanged, onNext, onPrevious, onClose;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .fromLTRB(24, 0, 20, 8),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter): onNext,
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): onPrevious,
          const SingleActivator(LogicalKeyboardKey.escape): onClose,
        },
        child: Row(
          spacing: 6,
          children: [
            Expanded(
              child: Input(
                controller: controller,
                focusNode: focus,
                autofocus: true,
                placeholder: 'Find in this session',
                leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 14),
                onChanged: (_) => onChanged(),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                controller.text.trim().isEmpty
                    ? ''
                    : count == 0
                    ? 'No matches'
                    : '${at % count + 1} of $count',
                textAlign: .end,
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ),
            Tooltip(
              message: 'Previous (⇧Enter)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Previous match',
                onPressed: count == 0 ? null : onPrevious,
                child: const AshlarIcon(AshlarIconsRoundedStroke.chevronUp, size: 14),
              ),
            ),
            Tooltip(
              message: 'Next (Enter)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Next match',
                onPressed: count == 0 ? null : onNext,
                child: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
              ),
            ),
            Tooltip(
              message: 'Close (Esc)',
              child: Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Close find',
                onPressed: onClose,
                child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Softens the top of the conversation into the header, so text scrolling up
/// fades out rather than meeting a line.
class _FadeUnderHeader extends StatelessWidget {
  const new({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = AshlarTheme.of(context).colors.background;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 28,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg, bg.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const new({required this.vm, required this.session});
  final ChatViewModel vm;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    return Container(
      // The title on the window buttons' line; past the sidebar's button
      // when the sidebar is not beside the page.
      // One row, centered on the window buttons' line, as a Mac title bar is:
      // the title, its folder, and the controls.
      padding: .fromLTRB(sidebarBeside(context) ? 24 : titleRowStart + 40, titleLine - 16, 20, 8),
      child: Row(
        spacing: 16,
        children: [
          Expanded(
            child: SizedBox(
              height: 32,
              // Text keeps room under its letters for descenders, so centered it
              // reads low: lifted, its capitals center on the line the window's
              // buttons and the sidebar's share (measured: 1.5 points low).
              child: Transform.translate(
                offset: const Offset(0, -1.5),
                child: Row(
                  spacing: 10,
                  children: [
                    Flexible(
                      flex: 3,
                      child: Text(
                        session.title,
                        style: t.text.sm.copyWith(
                          fontWeight: .w600,
                          height: 1,
                          leadingDistribution: .even,
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                    Flexible(
                      child: _FolderButton(vm: vm, cwd: session.cwd, style: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (vm.context case final ctx?)
            Tooltip(
              message:
                  '${(ctx.used / 1000).round()}k of ${(ctx.window / 1000).round()}k tokens, as last measured. '
                  'Compact from the menu to free some.',
              child: Text('Context ${(ctx.fraction * 100).round()}%', style: muted),
            ),
          for (final p in vm.panels)
            Tooltip(
              message: switch (p) {
                .changes => 'What this session changed in the folder',
                .background => 'Work running in the background',
                .preview => 'The page or document an answer pointed at',
              },
              child: Button(
                variant: vm.isOpen(p) ? .secondary : .ghost,
                size: .sm,
                semanticLabel: switch (p) {
                  .changes => 'Changes',
                  .background => 'Background',
                  .preview => 'Preview',
                },
                onPressed: () => vm.toggle(p),
                leading: AshlarIcon(switch (p) {
                  .changes => AshlarIconsRoundedStroke.fileDiff,
                  .background => AshlarIconsRoundedStroke.loader,
                  .preview => AshlarIconsRoundedStroke.appWindow,
                }, size: 14),
                child: Text(switch (p) {
                  .changes => 'Changes ${vm.changedFiles ?? ''}'.trim(),
                  .background =>
                    '${vm.backgroundSteps.where((c) => c.background!.status == .running).length} running',
                  .preview => 'Preview',
                }),
              ),
            ),
          _SessionMenu(vm: vm),
        ],
      ),
    );
  }
}

/// What can be done with the whole session: rename it, copy or save the
/// conversation, delete it.
class _SessionMenu extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  Future<void> _rename(BuildContext context) async {
    final title = await askText(
      context,
      title: 'Rename session',
      action: 'Rename',
      initial: vm.session?.title ?? '',
      icon: AshlarIconsRoundedStroke.pencil,
    );
    if (title != null) await vm.rename(title);
  }

  Future<void> _save(BuildContext context) async {
    final title = (vm.session?.title ?? 'conversation').replaceAll(RegExp(r'[/:\\]'), '-');
    final where = await getSaveLocation(
      suggestedName: '$title.md',
      initialDirectory: vm.session?.cwd,
      confirmButtonText: 'Save',
    );
    if (where == null) return;
    final result = await vm.saveMarkdown(where.path);
    if (!context.mounted) return;
    if (result is Ok) return showSavedToast(context, where.path);
    showToast(
      context,
      title: 'Could not save',
      description: '${(result as Error).error}',
      type: .error,
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ok =
        !context.read<SettingsRepository>().settings.confirmDelete ||
        await confirm(
          context,
          title: 'Delete this session?',
          body: 'The conversation leaves Helmy. Files in the folder stay as they are.',
          action: 'Delete',
          destructive: true,
        );
    if (!ok) return;
    await vm.delete();
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) => DropdownMenu(
    align: .end,
    items: [
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.pencil, size: 16),
        onPressed: () => _rename(context),
        child: const Text('Rename'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.copy, size: 16),
        onPressed: () => copyWithToast(context, vm, vm.markdown),
        child: const Text('Copy conversation'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.minimize2, size: 16),
        onPressed: vm.busy ? null : vm.compact,
        child: const Text('Compact conversation'),
      ),
      MenuItem(
        leading: const AshlarIcon(AshlarIconsRoundedStroke.download, size: 16),
        onPressed: () => _save(context),
        child: const Text('Save as Markdown...'),
      ),
      const MenuSeparator(),
      MenuItem(
        destructive: true,
        leading: const AshlarIcon(AshlarIconsRoundedStroke.trash, size: 16),
        onPressed: vm.busy ? null : () => _delete(context),
        child: const Text('Delete session'),
      ),
    ],
    builder: (context, menu) => Tooltip(
      message: 'Session',
      child: Button(
        variant: .ghost,
        size: .icon,
        semanticLabel: 'Session actions',
        onPressed: menu.open,
        child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsis, size: 16),
      ),
    ),
  );
}

/// The session's folder, which a click changes.
class _FolderButton extends StatelessWidget {
  const new({required this.vm, required this.cwd, required this.style});
  final ChatViewModel vm;
  final String cwd;
  final TextStyle style;

  Future<void> _pick() async {
    final dir = await getDirectoryPath(initialDirectory: cwd, confirmButtonText: 'Work here');
    if (dir != null) await vm.changeFolder(dir);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Tooltip(
      message: vm.busy ? 'Wait for the turn to end to change the folder' : 'Change folder',
      child: Pressable(
        onPressed: vm.busy ? null : _pick,
        semanticLabel: 'Folder ${tildePath(cwd)}, change',
        builder: (context, state) => Row(
          mainAxisSize: .min,
          spacing: 4,
          children: [
            AshlarIcon(AshlarIconsRoundedStroke.folder, size: 13, color: style.color),
            Flexible(
              child: Text(
                tildePath(cwd),
                maxLines: 1,
                overflow: .ellipsis,
                style: style.copyWith(
                  color: state.hovered ? t.colors.foreground : style.color,
                  decoration: state.hovered ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The permission level, as a quiet chip that opens a menu.
class _LevelChip extends StatelessWidget {
  const new({required this.vm, required this.level});
  final ChatViewModel vm;
  final PermissionLevel level;

  /// What the agent may do at [l], in a line.
  static String _what(PermissionLevel l) => switch (l) {
    .ask => 'Asks before changing files or running commands',
    .edit => 'Edits files without asking',
    .readOnly => 'Reads and plans; changes nothing',
    .full => 'Does anything without asking',
  };

  static IconData _icon(PermissionLevel l) => switch (l) {
    .ask => AshlarIconsRoundedStroke.shield,
    .edit => AshlarIconsRoundedStroke.pencil,
    .readOnly => AshlarIconsRoundedStroke.eye,
    .full => AshlarIconsRoundedStroke.zap,
  };

  @override
  Widget build(BuildContext context) => DropdownMenu(
    side: .top,
    width: 300,
    items: [
      for (final l in PermissionLevel.values)
        MenuItem(
          leading: AshlarIcon(_icon(l), size: 15),
          trailing: l == level ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14) : null,
          onPressed: () => vm.setLevel(l),
          child: Padding(
            padding: const .symmetric(vertical: 1),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 1,
              children: [
                Text(l.label),
                Text(
                  _what(l),
                  style: AshlarTheme.of(context).text.xs
                      .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
                ),
              ],
            ),
          ),
        ),
    ],
    builder: (context, menu) => Button(
      variant: .ghost,
      size: .sm,
      semanticLabel: 'Permissions: ${level.label}',
      onPressed: vm.busy ? null : menu.open,
      leading: AshlarIcon(_icon(level), size: 14),
      trailing: const AshlarIcon(AshlarIconsRoundedStroke.chevronDown, size: 14),
      child: Text(level.label),
    ),
  );
}

/// A file waiting to go with the next message.
class _Attached extends StatelessWidget {
  const new({required this.path, required this.vm});
  final String path;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final name = path.split('/').last;
    final picture = imageTypes.containsKey(name.split('.').last.toLowerCase());
    return Attachment(
      title: name,
      size: .sm,
      icon: picture ? AshlarIconsRoundedStroke.image : AshlarIconsRoundedStroke.file,
      image: picture ? FileImage(File(path)) : null,
      actions: [
        Button(
          variant: .ghost,
          size: .iconXs,
          semanticLabel: 'Remove $name',
          onPressed: () => vm.detach(path),
          child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 12),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const new({required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final waiting = vm.items.whereType<PermissionPrompt>().any((p) => p.decision == .pending);
    final label = waiting
        ? 'Waiting for you'
        : vm.thinking
        ? 'Thinking'
        : 'Working';
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Shimmer(
        enabled: !waiting,
        child: Text(label, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
      ),
    );
  }
}
