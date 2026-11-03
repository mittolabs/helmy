import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ashlar/dialog.dart';
import 'ashlar/input.dart';
import 'ashlar/pressable.dart';
import 'ashlar/theme.dart';

/// Helmy's own dialog: a quiet rounded panel with a small mark for what
/// kind of thing is being asked, the question, a muted line of why, and the
/// answers at its foot. Enter takes the main answer; Esc or a click outside
/// cancels. Built on Ashlar's parts, in this app's look.
class HelmyDialog extends StatelessWidget {
  const new({
    super.key,
    required this.title,
    required this.actions,
    this.icon,
    this.destructive = false,
    this.body,
    this.content,
  });

  final String title;
  final IconData? icon;

  /// Marks the question as one that removes something.
  final bool destructive;
  final String? body;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final tone = destructive ? c.destructive : c.foreground;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          margin: const .all(24),
          padding: const .fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: c.popover,
            borderRadius: .circular(18),
            border: Border.all(color: c.border.withValues(alpha: .45), width: .5),
            boxShadow: t.shadowLg,
          ),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              if (icon != null) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: tone.withValues(alpha: .1), shape: .circle),
                    alignment: .center,
                    child: AshlarIcon(icon!, size: 18, color: tone),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                title,
                style: t.text.lg.copyWith(fontWeight: .w600, color: c.foreground),
              ),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(body!, style: t.text.sm.copyWith(color: c.mutedForeground, height: 1.5)),
              ],
              if (content != null) ...[const SizedBox(height: 16), content!],
              const SizedBox(height: 22),
              Row(mainAxisAlignment: .end, spacing: 8, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

/// An answer at the foot of a [HelmyDialog]: the main one filled, the other
/// plain, a destructive one in a soft tint of the danger colour rather than a
/// block of it.
class DialogButton extends StatelessWidget {
  const new(
    this.label, {
    super.key,
    required this.onPressed,
    this.main = false,
    this.destructive = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool main;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) {
        final (bg, fg) = destructive
            ? (c.destructive.withValues(alpha: state.hovered ? .22 : .14), c.destructive)
            : main
            ? (c.foreground.withValues(alpha: state.hovered ? .88 : 1), c.background)
            : (c.foreground.withValues(alpha: state.hovered ? .08 : 0), c.foreground);
        return AnimatedContainer(
          duration: t.duration,
          padding: const .symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: .circular(10),
            boxShadow: [if (state.focused) BoxShadow(color: c.ring, spreadRadius: 2)],
          ),
          child: Text(
            label,
            style: t.text.sm.copyWith(color: fg, fontWeight: .w500),
          ),
        );
      },
    );
  }
}

/// Opens a [HelmyDialog], with Enter for the main answer.
Future<T?> _show<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  T? onEnter,
}) => showAshlarDialog<T>(
  context: context,
  builder: (context) => CallbackShortcuts(
    bindings: {
      if (onEnter != null)
        const SingleActivator(LogicalKeyboardKey.enter): () => Navigator.pop(context, onEnter),
      const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
    },
    child: Focus(autofocus: true, child: builder(context)),
  ),
);

/// Asks yes or no. True only when the main answer was chosen.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  IconData? icon,
  bool destructive = false,
}) async =>
    await _show<bool>(
      context,
      onEnter: true,
      builder: (context) => HelmyDialog(
        title: title,
        body: body,
        icon: icon ?? (destructive ? AshlarIconsRoundedStroke.trash : null),
        destructive: destructive,
        actions: [
          DialogButton('Cancel', onPressed: () => Navigator.pop(context, false)),
          DialogButton(
            action,
            main: true,
            destructive: destructive,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    ) ==
    true;

/// Asks for a line of text, starting from [initial]. Null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String action,
  String initial = '',
  String? body,
  IconData? icon,
}) async {
  final text = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final answer = await _show<String>(
    context,
    builder: (context) => HelmyDialog(
      title: title,
      body: body,
      icon: icon,
      content: Input(
        controller: text,
        autofocus: true,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
        DialogButton(action, main: true, onPressed: () => Navigator.pop(context, text.text)),
      ],
    ),
  );
  text.dispose();
  return answer;
}
