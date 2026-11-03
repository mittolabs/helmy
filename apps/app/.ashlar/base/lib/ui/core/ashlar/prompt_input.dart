// Ashlar UI: Prompt Input. Copied into your app by `ashlar add prompt-input`; it is yours to
// change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';
import 'input_group.dart';
import 'textarea.dart';
import 'theme.dart';

/// Where a person writes to an assistant: text that grows as it is written, what they
/// attached above it, your actions (attach, a model to choose) under it, and a send button
/// that becomes a stop button while the answer arrives.
///
/// With a keyboard, Enter sends and Shift+Enter starts a new line; on a phone's own
/// keyboard the return key starts a new line and the button sends. Enter while a word is
/// still being composed (as in Japanese or Chinese) finishes the word, not the message.
///
/// ```dart
/// PromptInput(
///   busy: answering,
///   onSubmit: (text) => ask(text),
///   onStop: cancel,
///   actions: [Button(variant: ButtonVariant.ghost, size: ButtonSize.icon, semanticLabel: 'Attach a file', onPressed: pick, child: AshlarIcon(AshlarIconsRoundedStroke.paperclip))],
/// )
/// ```
class PromptInput extends StatefulWidget {
  const PromptInput({
    super.key,
    required this.onSubmit,
    this.controller,
    this.focusNode,
    this.placeholder = 'Ask anything',
    this.busy = false,
    this.onStop,
    this.attachments = const [],
    this.actions = const [],
    this.minLines = 2,
    this.maxLines = 8,
    this.enabled = true,
    this.autofocus = false,
    this.clearOnSubmit = true,
  });

  /// Told the text when it is sent, trimmed. Not called for nothing at all, unless
  /// something is attached.
  final ValueChanged<String> onSubmit;

  /// Its text, to read and set from outside; one is made when not given.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Faint text shown while it is empty, and what a screen reader calls it.
  final String placeholder;

  /// An answer is arriving: the send button stops it instead, and Enter does nothing.
  final bool busy;

  /// Called by the stop button while [busy]; without it the button is not shown then.
  final VoidCallback? onStop;

  /// What is to go with the message, above the text: Attachments, say.
  final List<Widget> attachments;

  /// At the start of the row under the text: attach, a model to choose, a mode.
  final List<Widget> actions;

  /// The fewest lines it shows, and the most it grows to before scrolling.
  final int minLines, maxLines;

  final bool enabled;
  final bool autofocus;

  /// Empties the text once it is sent.
  final bool clearOnSubmit;

  @override
  State<PromptInput> createState() => _PromptInputState();
}

class _PromptInputState extends State<PromptInput> {
  TextEditingController? _own;
  TextEditingController get _text =>
      widget.controller ?? (_own ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
  }

  @override
  void didUpdateWidget(PromptInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _own)?.removeListener(_changed);
      _text.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  bool get _canSend =>
      widget.enabled &&
      !widget.busy &&
      (_text.text.trim().isNotEmpty || widget.attachments.isNotEmpty);

  void _send() {
    if (!_canSend) return;
    final text = _text.text.trim();
    if (widget.clearOnSubmit) _text.clear();
    widget.onSubmit(text);
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Shift+Enter is a new line, and Enter mid-composition finishes the word.
    if (HardwareKeyboard.instance.isShiftPressed ||
        _text.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final stopping = widget.busy && widget.onStop != null;
    return InputGroup(
      top: widget.attachments.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.attachments,
              ),
            ),
      bottom: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 8, 8),
        child: Row(
          children: [
            ...widget.actions,
            const Spacer(),
            if (stopping)
              Button(
                size: ButtonSize.icon,
                semanticLabel: 'Stop',
                onPressed: widget.onStop,
                child: AshlarIcon(
                  AshlarIconsRoundedSolid.square,
                  size: 14,
                  color: t.colors.primaryForeground,
                ),
              )
            else
              Button(
                size: ButtonSize.icon,
                semanticLabel: 'Send',
                onPressed: _canSend ? _send : null,
                child: const AshlarIcon(AshlarIconsRoundedStroke.arrowUp),
              ),
          ],
        ),
      ),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _key,
        child: Textarea(
          controller: _text,
          focusNode: widget.focusNode,
          placeholder: widget.placeholder,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          resizable: false,
          decorated: false,
        ),
      ),
    );
  }
}
