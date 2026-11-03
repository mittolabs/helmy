// Ashlar UI: Switch. Copied into your app by `ashlar add switch`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'pressable.dart';
import 'theme.dart';

/// An on and off switch, for a setting that takes effect at once. Give it a
/// [semanticLabel], or put it in a row with a Text.
///
/// ```dart
/// Switch(value: notify, onChanged: (v) => setState(() => notify = v), semanticLabel: 'Notifications')
/// ```
enum SwitchSize {
  /// 24 by 14.
  sm,

  /// 32 by 18.
  md,
}

class Switch extends StatelessWidget {
  const Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.size = SwitchSize.md,
    this.focusNode,
    this.autofocus = false,
  });

  /// Whether it is on.
  final bool value;

  /// Null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// What a screen reader calls it when its visible text does not say, as for an icon
  /// alone.
  final String? semanticLabel;

  /// Medium, or small to sit in a dense row.
  final SwitchSize size;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// Takes the keyboard's focus when it first appears.
  final bool autofocus;

  // Its own size, at the start, even where its parent stretches what it holds: a
  // stacked Field, a column that fills its width.
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: 1,
    heightFactor: 1,
    child: _control(context),
  );

  Widget _control(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!value),
      toggled: value,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      autofocus: autofocus,
      builder: (context, state) => Opacity(
        opacity: state.enabled ? 1 : .5,
        child: AnimatedContainer(
          duration: t.duration,
          width: size == SwitchSize.sm ? 24 : 32,
          height: size == SwitchSize.sm ? 14 : 18,
          padding: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: value ? c.primary : c.input,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [if (state.focused) ...t.focusRing, ...t.shadowXs],
          ),
          child: AnimatedAlign(
            duration: t.duration,
            curve: Curves.easeOutCubic,
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Container(
              width: size == SwitchSize.sm ? 12 : 16,
              height: size == SwitchSize.sm ? 12 : 16,
              decoration: BoxDecoration(
                color: t.brightness == Brightness.dark && !value
                    ? c.foreground
                    : c.background,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
