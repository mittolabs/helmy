// Ashlar UI: Toggle Group. Copied into your app by `ashlar add toggle-group`; it is yours to
// change.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'group.dart';
import 'theme.dart';
import 'toggle.dart';

/// One choice in a [ToggleGroup].
@immutable
class ToggleGroupItem<T> {
  const ToggleGroupItem(
    this.value,
    this.child, {
    this.semanticLabel,
    this.enabled = true,
  });

  /// The value it stands for, given back when it is pressed.
  final T value;

  /// Its label or icon.
  final Widget child;

  /// What a screen reader calls it, for an item that shows an icon alone.
  final String? semanticLabel;

  /// False fades it and leaves it out of the group's choices.
  final bool enabled;
}

/// Toggles joined into one piece. Without [multiple], pressing one releases the rest, and
/// pressing the pressed one releases it. The arrow keys move between them.
///
/// ```dart
/// ToggleGroup<TextAlign>(
///   values: {align},
///   onChanged: (v) => setState(() => align = v.firstOrNull ?? TextAlign.left),
///   items: [
///     ToggleGroupItem(TextAlign.left, AshlarIcon(AshlarIconsRoundedStroke.textAlignStart), semanticLabel: 'Align left'),
///     ToggleGroupItem(TextAlign.center, AshlarIcon(AshlarIconsRoundedStroke.textAlignCenter), semanticLabel: 'Centre'),
///   ],
/// )
/// ```
///
/// Filters as chips, one chosen at a time, set apart:
///
/// ```dart
/// ToggleGroup<String>(
///   variant: ToggleVariant.chip,
///   size: ToggleSize.xl,
///   spacing: 8,
///   values: {filter},
///   onChanged: (v) => setState(() => filter = v.firstOrNull ?? filter),
///   items: [ToggleGroupItem('all', Text('All')), ToggleGroupItem('new', Text('New'))],
/// )
/// ```
class ToggleGroup<T> extends StatelessWidget {
  const ToggleGroup({
    super.key,
    required this.values,
    required this.onChanged,
    required this.items,
    this.multiple = false,
    this.variant = ToggleVariant.outline,
    this.size = ToggleSize.md,
    this.semanticLabel,
    this.spacing = 0,
    this.axis = Axis.horizontal,
  });

  /// The pressed ones.
  final Set<T> values;

  /// Null disables the group.
  final ValueChanged<Set<T>>? onChanged;

  /// The toggles, in order.
  final List<ToggleGroupItem<T>> items;

  /// Several may be on at once, not one.
  final bool multiple;

  /// Plain, with borders all the time, or filled chips.
  final ToggleVariant variant;

  /// Small, medium, large or extra large.
  final ToggleSize size;

  /// What the group sets, read before it: 'Text alignment'.
  final String? semanticLabel;

  /// The gap between toggles. None joins them into one piece; any sets them apart, each
  /// with all its corners round.
  final double spacing;

  /// Vertical stacks them, the up and down arrows moving between them.
  final Axis axis;

  Widget _layout(List<Widget> toggles) {
    if (spacing == 0) {
      final joined = JoinedGroup(axis: axis, children: toggles);
      return axis == Axis.horizontal
          ? IntrinsicHeight(child: joined)
          : IntrinsicWidth(child: joined);
    }
    return Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, toggle) in toggles.indexed) ...[
          if (i > 0)
            SizedBox(
              width: axis == Axis.horizontal ? spacing : 0,
              height: axis == Axis.vertical ? spacing : 0,
            ),
          toggle,
        ],
      ],
    );
  }

  void _press(T value, bool on) {
    final next = multiple ? {...values} : <T>{};
    if (on) {
      next.add(value);
    } else {
      next.remove(value);
    }
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semanticLabel,
    child: Shortcuts(
      // Right is next in left-to-right text, and back in right-to-left.
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.arrowRight): isRtl(context)
            ? const PreviousFocusIntent()
            : const NextFocusIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const NextFocusIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): isRtl(context)
            ? const NextFocusIntent()
            : const PreviousFocusIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const PreviousFocusIntent(),
      },
      child: FocusTraversalGroup(
        child: _layout([
          for (final item in items)
            Toggle(
              pressed: values.contains(item.value),
              onChanged: onChanged == null || !item.enabled
                  ? null
                  : (on) => _press(item.value, on),
              variant: variant,
              size: size,
              semanticLabel: item.semanticLabel,
              child: item.child,
            ),
        ]),
      ),
    ),
  );
}
