import 'dart:async';
import 'dart:io';

import '../../../domain/helmy_voice.dart';
import '../../../domain/problem.dart' show clockAt;

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior, kSecondaryMouseButton;
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
import '../../../data/repositories/stash_repository.dart';
import '../../shell/view_models/sidebar_view_model.dart';
import '../../core/helmy_dialog.dart';
import 'background_panel.dart';
import 'changes_panel.dart';
import 'media.dart';
import 'bottom_terminal.dart';
import 'files_panel.dart';
import 'window_picker.dart';
import '../../../data/services/window_snapshots.dart';
import 'side_chat_panel.dart';
import 'preview_panel.dart';
import 'project_menu.dart';
import 'ship_panel.dart';
import 'device_panel.dart';
import 'terminal_panel.dart';
import 'chat_items.dart';
import 'composer.dart';
import 'saved_toast.dart';
import 'webhook_dialog.dart';
import '../../core/window_layout.dart';
import '../../../utils/platform.dart';
import 'file_popup.dart';

part 'screen/composer_area.dart';
part 'screen/empty.dart';
part 'screen/find.dart';
part 'screen/header.dart';
part 'screen/side_panels.dart';

class ChatScreen extends StatefulWidget {
  const new({super.key, required this.viewModel, this.bar});
  final ChatViewModel viewModel;

  /// Shown inside another screen's panel (a side chat): this bar in place of
  /// the header, and no panel of its own.
  final Widget? bar;

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

  /// The words chosen in the conversation, for a comment on them.
  String _chosen = '';

  /// A right-click is down: on macOS it picks the word under it, which
  /// would put a longer choice it landed in out of reach.
  bool _rightDown = false;

  void _choose(String words) {
    // A word picked by a right-click inside what was chosen keeps the choice.
    if (_rightDown && _chosen.contains(words.trim()) && words.trim().isNotEmpty) return;
    _chosen = words;
  }

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
    vm.draftInserts.addListener(_insert);
    vm.openThread.addListener(_openThread);
    snapshotRequests.addListener(_snapshot);
    // One asked for before this screen was open (both Shift keys from
    // another app, with no conversation showing).
    WidgetsBinding.instance.addPostFrameCallback((_) => _snapshot());
    // What was being written here when the thread was last left.
    _text.text = vm.draft;
    _text.addListener(_suggest);
    _text.addListener(_keepDraft);
  }

  /// A message went to a new thread: that is where the conversation is now.
  void _openThread() {
    final id = vm.openThread.value;
    if (id == null || !mounted) return;
    _text.clear();
    context.go('/s/$id');
  }

  String _kept = '';

  void _keepDraft() {
    if (_text.text == _kept) return;
    _kept = _text.text;
    vm.keepDraft(_text.text);
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.viewModel == widget.viewModel) return;
    old.viewModel.openThread.removeListener(_openThread);
    vm.openThread.addListener(_openThread);
    // Another thread in the same place: this one's words stay with it.
    old.viewModel.keepDraft(_text.text);
    unawaited(old.viewModel.saveDraft());
    _kept = vm.draft;
    _text.text = vm.draft;
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
      if (text.trim().isEmpty && !vm.hasExtras) return .handled;
      _text.clear();
      _back = null;
      setState(() => _suggestions = const []);
      vm.sendNow(text);
      return .handled;
    }
    final withMeta = !context.read<SettingsRepository>().settings.sendWithEnter;
    // Sent in the background (⌘Enter; ⌥⌘Enter where ⌘Enter sends): this chat
    // works on it while a new one opens, to send the next.
    if (key == LogicalKeyboardKey.enter &&
        e is KeyDownEvent &&
        widget.bar == null &&
        Desktop.current.commandHeld &&
        !HardwareKeyboard.instance.isShiftPressed &&
        (!withMeta || HardwareKeyboard.instance.isAltPressed)) {
      if (_text.text.trim().isEmpty && !vm.hasExtras) return .handled;
      unawaited(_sendInBackground());
      return .handled;
    }
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
    // ⌘S: what is written goes aside; in an empty box, the latest comes back.
    if (meta && key == LogicalKeyboardKey.keyS && widget.bar == null) {
      unawaited(_stashOrTake());
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
    if (text.trim().isEmpty && !vm.hasExtras) return;
    // "/side" or "/btw", and a question: asked in a side chat, not here.
    final side = RegExp(r'^/(?:side|btw)\b\s*([\s\S]*)$').firstMatch(text.trim());
    if (side != null && widget.bar == null) {
      _text.clear();
      setState(() => _suggestions = const []);
      final ask = side.group(1)!.trim();
      unawaited(vm.sideChat(ask: ask.isEmpty ? null : ask));
      return;
    }
    _text.clear();
    _back = null;
    setState(() => _suggestions = const []);
    vm.send.execute(text);
  }

  StashRepository? get _stash {
    try {
      return context.read<StashRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Puts what is written aside (words, files, pictures), or, with nothing
  /// written, brings back the latest put aside.
  Future<void> _stashOrTake() async {
    final stash = _stash;
    if (stash == null) return;
    if (_text.text.trim().isEmpty && vm.attachments.isEmpty) {
      final s = await stash.takeLatest();
      if (s == null || !mounted) return;
      _put(s.text);
      vm.attach(s.attachments);
      return;
    }
    await stash.stash(_text.text, [
      ...vm.attachments,
    ], from: vm.chatTitle ?? vm.session?.title ?? '');
    _text.clear();
    vm.attachments.clear();
    vm.keepDraft('');
    if (!mounted) return;
    setState(() {});
    showToast(
      context,
      title: 'Put aside',
      description: '${Desktop.current.keys('⌘S')} in an empty box, in any chat, brings it back.',
    );
  }

  /// Sends what is written, then opens a new chat in the same folder: this
  /// one goes on working where it is.
  Future<void> _sendInBackground() async {
    final title = vm.chatTitle ?? vm.session?.title ?? 'this chat';
    final cwd = vm.session?.cwd;
    final router = GoRouter.of(context);
    _submit(_text.text);
    final SidebarViewModel list;
    try {
      list = context.read<SidebarViewModel>();
    } on ProviderNotFoundException {
      return;
    }
    if (cwd == null) return;
    final made = await list.createIn(cwd);
    if (!mounted) return;
    if (made case Ok(:final value)) {
      showToast(context, title: 'Sent to "$title". It goes on working there.');
      router.go('/s/${value.id}');
    }
  }

  void _focus() => _composer.requestFocus();

  /// A window asked to go into this message (the conversation on screen,
  /// not a side chat's).
  Future<void> _snapshot() async {
    final asked = snapshotRequests.value;
    if (asked == null || widget.bar != null || !mounted) return;
    snapshotRequests.value = null;
    final snaps = context.read<WindowSnapshots>();
    final result = await vm.snapshotWindow(asked.window);
    if (asked.fromKeys) await snaps.activate();
    if (!mounted || result == .taken) return;
    showToast(
      context,
      title: result == .notAllowed
          ? "macOS isn't letting Helmy see that window"
          : "That window couldn't be snapshotted",
      description: result == .notAllowed
          ? 'Allow Helmy under Screen Recording in Privacy & Security, then try again.'
          : 'It may have closed. Try again with it in front.',
      type: .error,
      duration: const Duration(seconds: 8),
      action: result == .notAllowed
          ? Button(
              size: .sm,
              onPressed: () => vm.open(screenRecordingPane),
              child: const Text('Open Screen Recording'),
            )
          : null,
    );
  }

  /// Text asked to go into the message (a file mentioned from the Files
  /// tab): at the cursor, a space before it if it would join a word.
  void _insert() {
    final add = vm.draftInserts.value;
    if (add == null) return;
    vm.draftInserts.value = null;
    final text = _text.text;
    final at = _text.selection.isValid ? _text.selection.start : text.length;
    final gap = at > 0 && !RegExp(r'\s').hasMatch(text[at - 1]) ? ' ' : '';
    final next =
        '${text.substring(0, at)}$gap$add${text.substring(_text.selection.isValid ? _text.selection.end : at)}';
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + gap.length + add.length),
    );
    _composer.requestFocus();
  }

  @override
  void dispose() {
    // Left: what was being written stays with the thread.
    vm.keepDraft(_text.text);
    unawaited(vm.saveDraft());
    vm.focusRequests.removeListener(_focus);
    vm.draftInserts.removeListener(_insert);
    vm.openThread.removeListener(_openThread);
    snapshotRequests.removeListener(_snapshot);
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
      bindings: {
        Desktop.current.shortcut(LogicalKeyboardKey.keyF): _openFind,
        // The project's action again (the last run, else its first).
        Desktop.current.shortcut(LogicalKeyboardKey.keyR): () {
          if (actionToRun(vm) case final a?) vm.run(a);
        },
        Desktop.current.shortcut(LogicalKeyboardKey.keyO, shift: true): () => vm.openIn(),
        // A new thread in this chat, as ⌘N is a new chat.
        Desktop.current.shortcut(LogicalKeyboardKey.keyN, shift: true): () {
          if (vm.session?.chatId != null && widget.bar == null) newThreadIn(context, vm);
        },
        // The terminal under the conversation, as in an editor.
        Desktop.current.shortcut(LogicalKeyboardKey.keyJ): vm.toggleBottom,
        // ⌘⌥1 to ⌘⌥9: the actions in the project menu's order.
        for (final (i, key) in actionKeys.indexed)
          SingleActivator(
            key,
            meta: Desktop.current.commandIsMeta,
            control: !Desktop.current.commandIsMeta,
            alt: true,
          ): () {
            if (i < vm.actions.length) vm.run(vm.actions[i]);
          },
      },
      child: ColoredBox(
        color: t.colors.background,
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            final session = vm.session;
            if (session == null) {
              return const Center(child: Text('This chat no longer exists.'));
            }
            // The chat's earlier threads above, folded; then this one.
            final rows = [...threadRows(vm), ...buildRows(vm)];
            final alone = vm.earlierThreads.isEmpty;
            return DropTarget(
              onDragDone: (detail) => vm.attach(detail.files.map((f) => f.path)),
              child: _SidePanels(
                vm: vm,
                chat: Column(
                  children: [
                    if (widget.bar case final bar?)
                      bar
                    else
                      TitleBar(
                        // Redrawn into or out of full screen, where its start moves.
                        child: ListenableBuilder(
                          listenable: windowFullScreen,
                          builder: (context, _) => _Header(vm: vm, session: session),
                        ),
                      ),
                    // A thread started on its own after a quiet gap, said once.
                    if (widget.bar == null && ChatViewModel.startedAfter.containsKey(vm.sessionId))
                      Padding(
                        padding: .symmetric(horizontal: sideMargin(context)),
                        child: inColumn(_FreshThreadChip(vm: vm)),
                      ),
                    // Where filing put this thread, said once.
                    if (widget.bar == null && vm.filing != null)
                      Padding(
                        padding: .symmetric(horizontal: sideMargin(context)),
                        child: inColumn(_FilingChip(vm: vm)),
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
                    if (vm.items.isEmpty && !vm.busy && !_finding && alone)
                      Expanded(
                        child: _Hello(offline: vm.onlyThisMac, vm: vm),
                      )
                    else
                      Expanded(
                        // As AshlarPageRoute does; go_router pages do not get it by themselves.
                        // What answers show (`![words](where)`): pictures,
                        // players, documents, pages.
                        child: MarkdownMedia(
                          show: (where, words) =>
                              Media(where: where, words: words, cwd: session.cwd, actions: vm),
                          child: _FadeUnderHeader(
                            child: Listener(
                              onPointerDown: (e) =>
                                  _rightDown = e.buttons & kSecondaryMouseButton != 0,
                              onPointerUp: (_) => _rightDown = false,
                              child: SelectableRegion(
                                selectionControls: AshlarSelectionControls(t.colors.foreground),
                                onSelectionChanged: (chosen) => _choose(chosen?.plainText ?? ''),
                                contextMenuBuilder: (context, state) => AshlarSelectionMenu(
                                  anchors: state.contextMenuAnchors,
                                  items: [
                                    ...state.contextMenuButtonItems,
                                    // A comment on the words chosen, to go with the next message.
                                    if (_chosen.trim().isNotEmpty)
                                      ContextMenuButtonItem(
                                        label: 'Comment',
                                        onPressed: () {
                                          vm.comment(_chosen);
                                          state.hideToolbar();
                                          state.clearSelection();
                                        },
                                      ),
                                  ],
                                ),
                                child: MessageScroller(
                                  controller: _scroller,
                                  busy: vm.busy,
                                  gap: 14,
                                  padding: .fromLTRB(
                                    sideMargin(context),
                                    8,
                                    sideMargin(context),
                                    32,
                                  ),
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
                                                    color: t.colors.foreground.withValues(
                                                      alpha: .06,
                                                    ),
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
                      ),
                    if (vm.queue.isNotEmpty) inColumn(_Queue(vm: vm)),
                    // A draft put aside, offered back while the box is empty.
                    if (widget.bar == null)
                      ValueListenableBuilder(
                        valueListenable: _text,
                        builder: (context, value, _) => value.text.isEmpty
                            ? inColumn(_StashChip(onTake: () => unawaited(_stashOrTake())))
                            : const SizedBox.shrink(),
                      ),
                    if (_suggestions.isNotEmpty)
                      inColumn(_SuggestionList(items: _suggestions, onPick: _take))
                    else if (vm.items.isEmpty && !vm.busy && alone)
                      inColumn(_Starters(vm: vm, text: _text, onSend: _sendStarter)),
                    Padding(
                      padding: .fromLTRB(sideMargin(context), 0, sideMargin(context), 20),
                      child: inColumn(
                        Composer(
                          controller: _text,
                          focusNode: _composer,
                          font: context.watch<SettingsRepository>().settings.promptFont,
                          onSubmit: _submit,
                          placeholder: vm.pendingNeeds.contains(Capability.imageGeneration)
                              ? 'Describe the change to this image'
                              : widget.bar != null
                              ? 'Ask on the side'
                              : 'Type / for commands, @ for files',
                          status: vm.heldUntil != null
                              ? 'Waiting for room. What you send waits its turn.'
                              : vm.busy
                              ? 'Working. What you send waits its turn; ${Desktop.current.keys('⇧⌘Enter')} sends it now instead.'
                              : null,
                          attachments: [
                            for (final path in vm.attachments) _Attached(path: path, vm: vm),
                            for (var i = 0; i < vm.comments.length; i++)
                              _Comment(i: i, vm: vm, latest: i == vm.comments.length - 1),
                          ],
                          actions: [
                            DropdownMenu(
                              side: .top,
                              items: [
                                MenuItem(
                                  leading: const AshlarIcon(
                                    AshlarIconsRoundedStroke.paperclip,
                                    size: 16,
                                  ),
                                  onPressed: () async {
                                    final files = await openFiles(confirmButtonText: 'Attach');
                                    vm.attach(files.map((f) => f.path));
                                  },
                                  child: const Text('Attach files...'),
                                ),
                                if (Platform.isMacOS)
                                  MenuItem(
                                    leading: const AshlarIcon(
                                      AshlarIconsRoundedStroke.appWindow,
                                      size: 16,
                                    ),
                                    onPressed: () => pickWindow(context, vm),
                                    child: const Text('Snapshot a window...'),
                                  ),
                              ],
                              builder: (context, menu) => ComposerButton(
                                icon: AshlarIconsRoundedStroke.plus,
                                label: 'Attach files or a window (or paste a picture)',
                                onPressed: menu.open,
                              ),
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
                    // The terminal under the conversation: hidden, it keeps running.
                    if (widget.bar == null && vm.bottomTerminals.isNotEmpty)
                      Offstage(
                        offstage: !vm.bottomOpen,
                        child: BottomTerminal(vm: vm),
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
