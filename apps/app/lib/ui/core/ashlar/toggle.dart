// Ashlar UI: Toggle. Copied into your app by `ashlar add toggle`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'group.dart';
import 'pressable.dart';
import 'theme.dart';

enum ToggleVariant {
  /// No border until it is on.
  plain,

  /// A border all the time.
  outline,

  /// A filled pill, the secondary colour off and the primary on: a filter among several,
  /// set apart in a row with spacing.
  @Deprecated("chip: a look for one design, not Ashlar UI's. Draw it in your app on Pressable and the theme, or change your copy. Goes in a later release.")
  chip,
}

/// 32, 36, 40 and 48 tall: xl beside an xl button, on a phone.
enum ToggleSize { sm, md, lg, xl }

/// A button that stays pressed: bold, italic, a filter. Give an icon-only toggle a
/// [semanticLabel].
///
/// ```dart
/// Toggle(pressed: bold, onChanged: (v) => setState(() => bold = v), semanticLabel: 'Bold', child: AshlarIcon(AshlarIconsRoundedStroke.bold))
/// Toggle(variant: ToggleVariant.chip, pressed: open, onChanged: (v) => setState(() => open = v), child: Text('Open now'))
/// ```
class Toggle extends StatelessWidget {
  const Toggle({
    super.key,
    required this.pressed,
    required this.onChanged,
    required this.child,
    this.variant = ToggleVariant.plain,
    this.size = ToggleSize.md,
    this.semanticLabel,
  });

  /// Whether it is on.
  final bool pressed;

  /// Null disables it.
  final ValueChanged<bool>? onChanged;

  /// Its label or icon.
  final Widget child;

  /// Plain, with a border all the time, or a filled chip.
  final ToggleVariant variant;

  /// Small, medium, large or extra large.
  final ToggleSize size;

  /// What a screen reader calls it, for a toggle that shows an icon alone.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final height = t.control(switch (size) {
      ToggleSize.sm => 32.0,
      ToggleSize.md => 36.0,
      ToggleSize.lg => 40.0,
      ToggleSize.xl => 48.0,
    });
    final chip = variant == ToggleVariant.chip;
    return Pressable(
      onPressed: onChanged == null ? null : () => onChanged!(!pressed),
      toggled: pressed,
      semanticLabel: semanticLabel,
      builder: (context, state) {
        final fg = switch ((chip, pressed)) {
          (true, true) => c.primaryForeground,
          (true, false) => c.secondaryForeground,
          (false, true) => c.accentForeground,
          (false, false) => state.hovered ? c.mutedForeground : c.foreground,
        };
        final bg = switch ((chip, pressed)) {
          (true, true) =>
            state.hovered ? c.primary.withValues(alpha: .9) : c.primary,
          (true, false) =>
            state.hovered ? c.secondary.withValues(alpha: .8) : c.secondary,
          (false, true) => c.accent,
          (false, false) =>
            state.hovered ? c.muted : c.muted.withValues(alpha: 0),
        };
        return Opacity(
          opacity: state.enabled ? 1 : .5,
          child: AnimatedContainer(
            duration: t.duration,
            // Taller with larger text rather than cutting it off, and never stretched.
            height: grownHeight(context, height),
            constraints: BoxConstraints(minWidth: height),
            padding: EdgeInsets.symmetric(
              horizontal: switch (size) {
                ToggleSize.sm => chip ? 12 : 6,
                ToggleSize.xl => chip ? 20 : 12,
                _ => chip ? 16 : 8,
              },
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: joinedRadius(context, chip ? height : t.radiusMd),
              border: variant == ToggleVariant.outline
                  ? joinedBorder(context, state.focused ? c.ring : c.input)
                  : null,
              boxShadow: [
                if (state.focused) ...t.focusRing,
                if (variant == ToggleVariant.outline) ...t.shadowXs,
              ],
            ),
            // Centred, and as wide as its label unless a group stretches it.
            child: Align(
              widthFactor: 1,
              child: DefaultTextStyle.merge(
                style: (size == ToggleSize.xl ? t.text.base : t.text.sm)
                    .copyWith(color: fg, fontWeight: FontWeight.w500),
                maxLines: 1,
                child: IconTheme.merge(
                  data: IconThemeData(
                    color: fg,
                    size: size == ToggleSize.xl ? 20 : 16,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
