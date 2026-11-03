// Ashlar UI: Collapsible. Copied into your app by `ashlar add collapsible`; it is yours to
// change.

import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Content that opens and closes under a trigger. [builder] draws the trigger and gets
/// whether it is open and a function that opens or closes it; give that to a Button.
/// Closed, the content is out of the Tab order and out of what screen readers read.
///
/// Give [open] and [onChanged] to hold the state yourself; leave them out and it holds
/// its own, starting at [initiallyOpen].
///
/// ```dart
/// Collapsible(
///   builder: (context, open, toggle) => Button(variant: ButtonVariant.ghost, onPressed: toggle, child: Text(open ? 'Hide' : 'Show')),
///   child: Text('The details.'),
/// )
/// ```
class Collapsible extends StatefulWidget {
  const Collapsible({
    super.key,
    required this.builder,
    required this.child,
    this.open,
    this.onChanged,
    this.initiallyOpen = false,
  });

  /// Builds what opens and closes it, given whether it is open and a way to toggle it.
  final Widget Function(BuildContext context, bool open, VoidCallback toggle)
  builder;

  /// What shows when it is open.
  final Widget child;

  /// Whether it is open, when you hold its state.
  final bool? open;

  /// Told when it opens or closes.
  final ValueChanged<bool>? onChanged;

  /// Whether it starts open, when nothing holds its state from outside.
  final bool initiallyOpen;

  @override
  State<Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<Collapsible>
    with SingleTickerProviderStateMixin {
  late bool _own = widget.initiallyOpen;
  bool get _open => widget.open ?? _own;
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: _open ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final _size = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  void _toggle() {
    if (widget.open == null) setState(() => _own = !_own);
    widget.onChanged?.call(!_open);
    _run();
  }

  void _run() {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _c.value = _open ? 1 : 0;
    } else if (_open) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void didUpdateWidget(Collapsible old) {
    super.didUpdateWidget(old);
    if (old.open != widget.open) _run();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.builder(context, _open, _toggle),
        SizeTransition(
          sizeFactor: _size,
          alignment: AlignmentDirectional.topStart,
          child: Visibility(
            // Fully closed: kept, but not drawn, focused or read.
            visible: !_c.isDismissed,
            maintainState: true,
            child: ExcludeFocus(
              excluding: !_open,
              child: DefaultTextStyle.merge(
                style: t.text.sm,
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
