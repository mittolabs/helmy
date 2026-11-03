// Ashlar UI: Kbd. Copied into your app by `ashlar add kbd`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// A key on the keyboard, for showing a shortcut. [Kbd.group] sets several side by side.
///
/// ```dart
/// Kbd(child: Text('Esc'))
/// Kbd.group([Kbd(child: Text('⌘')), Kbd(child: Text('K'))])
/// ```
class Kbd extends StatelessWidget {
  const Kbd({super.key, required this.child});

  /// The key's name or symbol: Text('⌘'), Text('Enter').
  final Widget child;

  /// Keys pressed together, with a small gap between them.
  static Widget group(List<Widget> keys) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, k) in keys.indexed) ...[
        if (i > 0) const SizedBox(width: 4),
        k,
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Container(
      // A height at least: larger text makes it taller rather than being cut off.
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: t.colors.muted,
        borderRadius: BorderRadius.circular(t.radiusSm),
      ),
      child: DefaultTextStyle.merge(
        style: t.text.xs.copyWith(
          color: t.colors.mutedForeground,
          fontWeight: FontWeight.w500,
          height: 1,
          // The font's spare leading split above and below, so the text sits centred.
          leadingDistribution: TextLeadingDistribution.even,
        ),
        maxLines: 1,
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: IconTheme.merge(
            data: IconThemeData(color: t.colors.mutedForeground, size: 12),
            child: child,
          ),
        ),
      ),
    );
  }
}
