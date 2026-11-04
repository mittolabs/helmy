part of '../chat_items.dart';

/// A message of yours, with Copy and Edit under it while the pointer is near.
/// Edit opens it in place; sending it again takes back what came after.
class _User extends StatefulWidget {
  const new(
    this.text,
    this.index,
    this.vm, {
    super.key,
    this.attachments = const [],
    this.sentAt,
    this.from,
  });
  final String text;

  /// Sent by something other than the person: what, after "From".
  final String? from;

  /// When it was sent; unknown for older messages.
  final DateTime? sentAt;
  final List<String> attachments;
  final int index;
  final ChatViewModel vm;

  @override
  State<_User> createState() => _UserState();
}

class _UserState extends State<_User> {
  bool _hovered = false;
  ({Duration at, Offset where})? _lastClick;

  /// A second click soon after the first, near it, opens the message to edit.
  void _clicked(Offset where) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    final last = _lastClick;
    _lastClick = (at: now, where: where);
    if (last == null ||
        now - last.at > kDoubleTapTimeout ||
        (where - last.where).distance > kDoubleTapSlop) {
      return;
    }
    _lastClick = null;
    if (!widget.vm.busy) widget.vm.startEdit(widget.index);
  }

  /// Puts the folder's files back as they were before this message.
  Future<void> _undo(BuildContext context) async {
    final vm = widget.vm;
    final changed = await vm.changesFrom(widget.index);
    if (!context.mounted) return;
    if (changed.isEmpty) {
      showToast(context, title: 'No files changed since this message');
      return;
    }
    final names = changed.take(4).map((c) => c.path).join(', ');
    final ok = await confirm(
      context,
      title: 'Undo file changes from here?',
      body:
          '${changed.length} file${changed.length == 1 ? '' : 's'} go back to how they were '
          'before this message: $names${changed.length > 4 ? ', ...' : ''}. The conversation '
          'stays as it is.',
      action: 'Undo changes',
      icon: AshlarIconsRoundedStroke.undo2,
    );
    if (!ok) return;
    final n = await vm.undoFrom(widget.index);
    if (context.mounted) showToast(context, title: '$n file${n == 1 ? '' : 's'} put back');
  }

  late final _edit = TextEditingController(text: widget.text)..addListener(_editChanged);

  /// Enter saves and Esc cancels; Shift+Enter is a new line.
  late final _editFocus = FocusNode(
    onKeyEvent: (node, e) {
      if (e is! KeyDownEvent) return .ignored;
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        return .handled;
      }
      if (e.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
        _saveEdit();
        return .handled;
      }
      return .ignored;
    },
  );

  void _editChanged() => setState(() {});

  /// Whether the editor was showing at the last build, to focus it once.
  bool _editing = false;

  void _cancelEdit() {
    _edit.text = widget.text;
    widget.vm.cancelEdit();
  }

  void _saveEdit() {
    final text = _edit.text.trim();
    if (text.isEmpty || text == widget.text.trim()) return;
    widget.vm.resend(widget.index, text);
  }

  /// The message edited in place: the bubble itself, with a ring, as wide as
  /// its words up to the bubble's own limit; Cancel and Save under it.
  Widget _editor(BuildContext context) {
    // Typing goes here at once: autofocus alone yields to the composer,
    // which already has focus.
    if (!_editing) {
      _editing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _editFocus.requestFocus();
        _edit.selection = TextSelection.collapsed(offset: _edit.text.length);
      });
    }
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final changed = _edit.text.trim().isNotEmpty && _edit.text.trim() != widget.text.trim();
    return Padding(
      padding: const .only(top: 12, bottom: 4),
      child: LayoutBuilder(
        // As wide as the row, so the message stays on the right where it was.
        builder: (context, box) => SizedBox(
          width: box.maxWidth,
          child: Column(
            crossAxisAlignment: .end,
            spacing: 6,
            children: [
              ConstrainedBox(
                // Room to type in, never wider than a message is.
                constraints: BoxConstraints(
                  minWidth: (box.maxWidth * .8).clamp(0, 360),
                  maxWidth: box.maxWidth * .8,
                ),
                child: IntrinsicWidth(
                  child: Container(
                    padding: const .symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: .circular(t.radiusXl),
                      border: Border.all(color: c.ring, width: 1.5),
                    ),
                    child: EditableText(
                      controller: _edit,
                      focusNode: _editFocus,
                      autofocus: true,
                      maxLines: null,
                      style: t.text.sm.copyWith(color: c.foreground, height: 1.6),
                      cursorColor: c.foreground,
                      backgroundCursorColor: c.mutedForeground,
                      selectionColor: c.foreground.withValues(alpha: .2),
                      keyboardType: TextInputType.multiline,
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: .min,
                spacing: 4,
                children: [
                  Tooltip(
                    message: 'Saving sends it again. What came after stays as a version you can go back to; files are not changed.',
                    child: AshlarIcon(
                      AshlarIconsRoundedStroke.info,
                      size: 14,
                      color: c.mutedForeground,
                    ),
                  ),
                  Button(
                    size: .sm,
                    variant: .ghost,
                    onPressed: _cancelEdit,
                    child: const Text('Cancel'),
                  ),
                  Button(
                    size: .sm,
                    variant: .secondary,
                    onPressed: changed ? _saveEdit : null,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _edit.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    if (vm.editing == widget.index) return _editor(context);
    _editing = false;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const .only(top: 12, bottom: 4),
        child: Column(
          crossAxisAlignment: .end,
          spacing: 2,
          children: [
            // Not the person's words: said where they came from.
            if (widget.from case final from?)
              Padding(
                padding: const .only(bottom: 2),
                child: Row(
                  mainAxisSize: .min,
                  spacing: 4,
                  children: [
                    AshlarIcon(
                      AshlarIconsRoundedStroke.messagesSquare,
                      size: 12,
                      color: AshlarTheme.of(context).colors.mutedForeground,
                    ),
                    Flexible(
                      child: Text(
                        'From $from',
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: AshlarTheme.of(context).text.xs
                            .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.attachments.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: .end,
                children: [
                  for (final path in widget.attachments)
                    Attachment(
                      title: path.split('/').last,
                      size: .sm,
                      onPressed: () => vm.showFile(path),
                      image:
                          imageTypes.containsKey(path.split('.').last.toLowerCase()) &&
                              File(path).existsSync()
                          ? FileImage(File(path))
                          : null,
                    ),
                ],
              ),
            if (widget.text.isNotEmpty)
              // Double-click to edit. Read from raw pointer events, since the
              // conversation's text selection claims double-clicks for itself.
              Listener(
                onPointerDown: (e) => _clicked(e.position),
                child: Message(
                  align: .end,
                  child: Bubble(variant: .muted, child: Text(widget.text)),
                ),
              ),
            Row(
              mainAxisSize: .min,
              children: [
                // Kept in the layout while hidden, so nothing below jumps.
                Opacity(
                  opacity: _hovered ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_hovered,
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        if (widget.sentAt case final at?)
                          Tooltip(
                            message: 'Sent ${fullTime(at)}',
                            child: Padding(
                              padding: const .symmetric(horizontal: 6),
                              child: Text(
                                shortWhen(at),
                                style: AshlarTheme.of(context).text.xs.copyWith(
                                  color: AshlarTheme.of(context).colors.mutedForeground,
                                ),
                              ),
                            ),
                          ),
                        _IconAction(
                          icon: AshlarIconsRoundedStroke.copy,
                          label: 'Copy',
                          onPressed: () => copyWithToast(context, vm, widget.text),
                        ),
                        _IconAction(
                          icon: AshlarIconsRoundedStroke.pencil,
                          label: 'Edit',
                          onPressed: vm.busy ? null : () => vm.startEdit(widget.index),
                        ),
                        if (vm.canUndoFrom(widget.index))
                          _IconAction(
                            icon: AshlarIconsRoundedStroke.fileDiff,
                            label: "Show this message's changes",
                            onPressed: () => vm.showChanges(from: widget.index),
                          ),
                        if (vm.canUndoFrom(widget.index))
                          _IconAction(
                            icon: AshlarIconsRoundedStroke.undo2,
                            label: 'Undo file changes from here',
                            onPressed: vm.busy ? null : () => _undo(context),
                          ),
                      ],
                    ),
                  ),
                ),
                // Always shown: that there are other versions is worth knowing.
                if (vm.branchesAt(widget.index) != null) _BranchSwitch(index: widget.index, vm: vm),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Under an edited message: which version of the conversation is showing,
/// arrows to step between them, and the count opening a list of them all.
class _BranchSwitch extends StatelessWidget {
  const new({required this.index, required this.vm});
  final int index;
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final b = vm.branchesAt(index)!;
    final versions = vm.versionsAt(index);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    void go(int to) => vm.showBranch(index, to);
    return Row(
      mainAxisSize: .min,
      children: [
        _IconAction(
          icon: AshlarIconsRoundedStroke.chevronLeft,
          label: 'Previous version',
          onPressed: vm.busy || b.active == 0 ? null : () => go(b.active - 1),
        ),
        DropdownMenu(
          align: .end,
          width: 300,
          items: [
            MenuLabel(child: Text('Versions from this message')),
            for (var i = 0; i < versions.length; i++)
              MenuItem(
                onPressed: vm.busy || i == b.active ? null : () => go(i),
                leading: i == b.active
                    ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14)
                    : const SizedBox(width: 14),
                trailing: Text(
                  '${versions[i].asks} message${versions[i].asks == 1 ? '' : 's'}',
                  style: muted,
                ),
                child: Text(
                  '${i + 1}  ${versions[i].first.replaceAll('\n', ' ')}',
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
              ),
            const MenuSeparator(),
            Padding(
              padding: const .fromLTRB(8, 4, 8, 6),
              child: Text(
                "Switching changes the conversation, not your files. Use undo file "
                'changes for those.',
                style: muted,
              ),
            ),
          ],
          builder: (context, menu) => Tooltip(
            message: 'All versions',
            child: Pressable(
              onPressed: menu.isOpen ? menu.close : menu.open,
              semanticLabel: 'Version ${b.active + 1} of ${b.length}, show all',
              builder: (context, state) => Container(
                padding: const .symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: state.hovered ? t.colors.accent : null,
                  borderRadius: .circular(t.radiusMd),
                ),
                child: Text(
                  '${b.active + 1} / ${b.length}',
                  style: muted.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
        ),
        _IconAction(
          icon: AshlarIconsRoundedStroke.chevronRight,
          label: 'Next version',
          onPressed: vm.busy || b.active == b.length - 1 ? null : () => go(b.active + 1),
        ),
      ],
    );
  }
}
