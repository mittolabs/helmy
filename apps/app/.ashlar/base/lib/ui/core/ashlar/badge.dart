// Ashlar UI: Badge. Copied into your app by `ashlar add badge`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

enum BadgeVariant {
  primary,
  secondary,
  destructive,
  outline,

  /// No fill or border: a quiet label beside other text.
  ghost,

  /// Text in the primary colour, underlined: a label that leads somewhere.
  link,
}

/// A small label: a status, a count, a tag. [leading] is usually a 12px icon.
///
/// ```dart
/// Badge(child: Text('New'))
/// Badge(variant: BadgeVariant.outline, leading: AshlarIcon(AshlarIconsRoundedStroke.check, size: 12), child: Text('Paid'))
/// ```
class Badge extends StatelessWidget {
  const Badge({
    super.key,
    required this.child,
    this.variant = BadgeVariant.primary,
    this.leading,
  });

  /// Its text.
  final Widget child;

  /// Its fill: primary, secondary, destructive, outline, ghost or link.
  final BadgeVariant variant;

  /// Before its text: usually an icon.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final (Color bg, Color fg, Color? border) = switch (variant) {
      BadgeVariant.primary => (c.primary, c.primaryForeground, null),
      BadgeVariant.secondary => (c.secondary, c.secondaryForeground, null),
      BadgeVariant.destructive => (
        c.destructive,
        c.destructiveForeground,
        null,
      ),
      BadgeVariant.outline => (const Color(0x00000000), c.foreground, c.border),
      BadgeVariant.ghost => (const Color(0x00000000), c.foreground, null),
      BadgeVariant.link => (const Color(0x00000000), c.primary, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: border ?? const Color(0x00000000)),
      ),
      child: DefaultTextStyle.merge(
        style: t.text.xs.copyWith(
          color: fg,
          fontWeight: FontWeight.w500,
          decoration: variant == BadgeVariant.link
              ? TextDecoration.underline
              : null,
          decorationColor: fg,
        ),
        maxLines: 1,
        child: IconTheme.merge(
          data: IconThemeData(color: fg, size: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 4)],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
