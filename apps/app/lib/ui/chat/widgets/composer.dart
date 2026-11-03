import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/selection.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';

/// Where a message is written: one soft rounded box, the text on top and a
/// single quiet row under it, the controls to the left and a round send button
/// to the right. Enter sends, Shift+Enter starts a new line.
class Composer extends StatelessWidget {
  const new({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.placeholder,
    this.status,
    this.attachments = const [],
    this.actions = const [],
    this.trailing = const [],
  });

  final TextEditingController controller;

  /// Its key handler should send on Enter; see [handleEnter].
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final String placeholder;

  /// A short line above the text when something needs saying.
  final String? status;

  /// Files going with the message, above the text.
  final List<Widget> attachments;

  /// Beside each other at the start of the row: attach, permissions.
  final List<Widget> actions;

  /// At the end of the row, before send: stop.
  final List<Widget> trailing;

  /// Sends on Enter unless Shift is held, or with [withMeta] only on ⌘Enter.
  /// Call from the focus node's handler.
  static KeyEventResult handleEnter(KeyEvent e, VoidCallback send, {bool withMeta = false}) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.enter) return .ignored;
    final keys = HardwareKeyboard.instance;
    final sends = withMeta ? keys.isMetaPressed : !keys.isShiftPressed && !keys.isMetaPressed;
    if (!sends) return .ignored;
    send();
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final text = t.text.base.copyWith(color: c.foreground, height: 1.45);
    return Container(
      padding: const .fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .45),
        borderRadius: .circular(22),
        border: Border.all(color: c.border.withValues(alpha: .8), width: .5),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          if (status != null) Text(status!, style: t.text.xs.copyWith(color: c.mutedForeground)),
          if (attachments.isNotEmpty) Wrap(spacing: 6, runSpacing: 6, children: attachments),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Stack(
              children: [
                if (controller.text.isEmpty)
                  IgnorePointer(
                    child: Text(placeholder, style: text.copyWith(color: c.mutedForeground)),
                  ),
                EditableText(
                  controller: controller,
                  focusNode: focusNode,
                  style: text,
                  cursorColor: c.foreground,
                  backgroundCursorColor: c.mutedForeground,
                  selectionColor: c.foreground.withValues(alpha: .25),
                  selectionControls: AshlarSelectionControls(c.foreground),
                  minLines: 1,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  autofocus: true,
                ),
              ],
            ),
          ),
          Row(
            spacing: 4,
            children: [
              ...actions,
              const Spacer(),
              ...trailing,
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final ready = controller.text.trim().isNotEmpty || attachments.isNotEmpty;
                  return Tooltip(
                    message: 'Send (Enter)',
                    child: Pressable(
                      onPressed: ready ? () => onSubmit(controller.text) : null,
                      semanticLabel: 'Send',
                      builder: (context, state) => AnimatedContainer(
                        duration: t.duration,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: ready
                              ? c.foreground.withValues(alpha: state.hovered ? .85 : 1)
                              : c.foreground.withValues(alpha: .25),
                        ),
                        alignment: .center,
                        child: AshlarIcon(
                          AshlarIconsRoundedStroke.arrowUp,
                          size: 16,
                          color: c.background,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A small quiet button for the composer's row.
class ComposerButton extends StatelessWidget {
  const new({super.key, required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Button(
      variant: .ghost,
      size: .iconSm,
      round: true,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 16),
    ),
  );
}
