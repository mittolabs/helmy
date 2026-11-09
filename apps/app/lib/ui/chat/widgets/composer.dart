import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/selection.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../../utils/platform.dart';

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
    this.listening = false,
    this.attachments = const [],
    this.actions = const [],
    this.trailing = const [],
    this.tray,
    this.onVoice,
    this.font,
  });

  final TextEditingController controller;

  /// The font chosen for messages, by family; null for the interface's.
  final String? font;

  /// Its key handler should send on Enter; see [handleEnter].
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final String placeholder;

  /// A short line above the text when something needs saying.
  final String? status;

  /// The microphone is on: [status] gets a pulsing red dot, so it is plain
  /// that Helmy is listening.
  final bool listening;

  /// Files going with the message, above the text.
  final List<Widget> attachments;

  /// Beside each other at the start of the row: attach, permissions.
  final List<Widget> actions;

  /// At the end of the row, before send: stop.
  final List<Widget> trailing;

  /// A strip tucked under the box: the chat's project, its files, its tools.
  final Widget? tray;

  /// A voice conversation: offered in Send's place while the box is empty.
  final VoidCallback? onVoice;

  /// Sends on Enter unless Shift is held, or with [withMeta] only on ⌘Enter.
  /// Call from the focus node's handler.
  static KeyEventResult handleEnter(KeyEvent e, VoidCallback send, {bool withMeta = false}) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.enter) return .ignored;
    final keys = HardwareKeyboard.instance;
    final sends = withMeta
        ? Desktop.current.commandHeld
        : !keys.isShiftPressed && !Desktop.current.commandHeld;
    if (!sends) return .ignored;
    send();
    return .handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final text = t.text.base.copyWith(
      color: c.foreground,
      height: 1.45,
      fontFamily: font ?? t.text.fontFamily,
    );
    final dark = t.brightness == .dark;
    final box = Container(
      padding: const .fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        // On black, a solid grey that stands off the page; on white, a tint.
        color: dark ? const Color(0xFF151515) : c.muted.withValues(alpha: .45),
        borderRadius: .circular(22),
        border: Border.all(
          color: dark ? const Color(0x24FFFFFF) : c.border.withValues(alpha: c.border.a * .8),
          width: dark ? 1 : .5,
        ),
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          if (status != null && listening)
            Row(
              spacing: 8,
              children: [
                const _Recording(),
                Expanded(
                  child: Text(status!, style: t.text.xs.copyWith(color: c.foreground)),
                ),
              ],
            )
          else if (status != null)
            Text(status!, style: t.text.xs.copyWith(color: c.mutedForeground)),
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
              // When the box is narrow they scroll, so Send is always in reach.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: .horizontal,
                  child: Row(spacing: 4, children: actions),
                ),
              ),
              ...trailing,
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final ready = controller.text.trim().isNotEmpty || attachments.isNotEmpty;
                  // Nothing to send: talk instead.
                  if (!ready && onVoice != null) {
                    return Tooltip(
                      message: 'Talk with Helmy',
                      child: Pressable(
                        onPressed: onVoice,
                        semanticLabel: 'Talk with Helmy',
                        builder: (context, state) => AnimatedContainer(
                          duration: t.duration,
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: .circle,
                            color: c.primary.withValues(alpha: state.hovered ? .85 : 1),
                          ),
                          alignment: .center,
                          child: AshlarIcon(
                            AshlarIconsRoundedStroke.waveSine,
                            size: 16,
                            color: c.primaryForeground,
                          ),
                        ),
                      ),
                    );
                  }
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
    final tray = this.tray;
    if (tray == null) return box;
    // Tucked under the box, a shade apart, as one piece with it.
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        box,
        Padding(
          padding: const .symmetric(horizontal: 14),
          child: Container(
            padding: const .fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF1E1E1E) : c.muted.withValues(alpha: .7),
              borderRadius: const .vertical(bottom: .circular(16)),
              border: Border(
                left: BorderSide(color: dark ? const Color(0x1AFFFFFF) : c.border),
                right: BorderSide(color: dark ? const Color(0x1AFFFFFF) : c.border),
                bottom: BorderSide(color: dark ? const Color(0x1AFFFFFF) : c.border),
              ),
            ),
            child: tray,
          ),
        ),
      ],
    );
  }
}

/// A small quiet button for the composer's row.
class ComposerButton extends StatelessWidget {
  const new({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.live = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Something is on that this button stops (the microphone): filled red.
  final bool live;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Button(
      variant: live ? .destructive : .ghost,
      size: .iconSm,
      round: true,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 16),
    ),
  );
}

/// A red dot that pulses while the microphone is on; still when the person
/// has asked for less motion.
class _Recording extends StatefulWidget {
  const _Recording();

  @override
  State<_Recording> createState() => _RecordingState();
}

class _RecordingState extends State<_Recording> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse
        ..stop()
        ..value = 1;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: AshlarTheme.of(context).colors.destructive,
        shape: BoxShape.circle,
      ),
    ),
  );
}
