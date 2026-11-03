// Ashlar UI: what every control is built on. Copied in by `ashlar add` with the first
// component that needs it; it is yours to change.

import 'dart:ui' show SemanticsRole;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'group.dart';
import 'theme.dart';

/// The states a control draws.
@immutable
class PressableState {
  const PressableState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.enabled = true,
  });

  /// The pointer is over it.
  final bool hovered;

  /// It is held down, by pointer or key.
  final bool pressed;

  /// It has focus that came from the keyboard: the time to show a focus ring.
  final bool focused;

  /// Whether it takes presses.
  final bool enabled;
}

/// A control's behaviour without its look: hover, press, keyboard focus, activation by
/// Enter and Space, a click cursor, and what a screen reader announces. [builder] draws
/// the look for each [PressableState].
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.semanticValue,
    this.button = true,
    this.toggled,
    this.checked,
    this.mixed = false,
    this.selected,
    this.expanded,
    this.link = false,
    this.exclusive = false,
    this.role,
  });

  /// Null disables it.
  final VoidCallback? onPressed;

  /// Builds how it looks, given whether it is hovered, pressed, focused or disabled.
  ///
  /// What it builds is centred and takes its own size, so a control hugs its content even
  /// in a stretched column. To fill the width a parent gives it (an Expanded, a stretched
  /// column), give what it builds `width: double.infinity`.
  final Widget Function(BuildContext context, PressableState state) builder;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// Takes the keyboard's focus when it first appears.
  final bool autofocus;

  /// Read out in place of the visible content, and everything it builds goes unread:
  /// buttons inside it too. A card or a row with buttons of its own keeps them out of
  /// the labelled area, beside it or over it in a Stack.
  final String? semanticLabel;

  /// Read out after the label: what a select or a field holds.
  final String? semanticValue;

  /// Announced as a button.
  final bool button;

  /// Announced as a switch that is on or off.
  final bool? toggled;

  /// Announced as a checkbox that is checked or not.
  final bool? checked;

  /// Announced as partly checked: a checkbox over a list where some are checked.
  final bool mixed;

  /// Announced as the chosen one of several: a tab, an option.
  final bool? selected;

  /// Announced as expanded or collapsed: an accordion's or a collapsible's trigger.
  final bool? expanded;

  /// Announced as a link rather than a button: a breadcrumb.
  final bool link;

  /// What a screen reader calls it, when it is not a button: a tab, a menu item.
  final SemanticsRole? role;

  /// One of a group where only one is checked: a radio button, to a screen reader.
  final bool exclusive;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  /// [child] in a press area at least the theme's [AshlarThemeData.minTapTarget] square,
  /// centred: for a finger on a phone. In a joined group only the height grows, so the
  /// group stays joined.
  Widget _target(BuildContext context, Widget child) {
    final size = AshlarTheme.of(context).minTapTarget;
    if (size <= 0) return child;
    final joined = JoinedPosition.maybeOf(context) != null;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: joined ? 0 : size, minHeight: size),
      child: Center(widthFactor: 1, heightFactor: 1, child: child),
    );
  }

  bool _hovered = false, _pressed = false, _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _activate([Intent? _]) {
    if (!_enabled) return;
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    // The visible text merges into the control's announcement: "Save, button".
    return MergeSemantics(
      child: Semantics(
        button:
            widget.button &&
            widget.toggled == null &&
            widget.checked == null &&
            widget.role == null &&
            !widget.link,
        link: widget.link,
        expanded: widget.expanded,
        role: widget.role,
        selected: widget.selected,
        toggled: widget.toggled,
        checked: widget.mixed ? null : widget.checked,
        inMutuallyExclusiveGroup: widget.exclusive ? true : null,
        mixed: widget.mixed ? true : null,
        enabled: _enabled,
        label: widget.semanticLabel,
        value: widget.semanticValue,
        onTap: _enabled ? _activate : null,
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enabled: _enabled,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: _activate),
          },
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          // Hover follows the mouse itself, not the focus highlight mode, so a mouse on a
          // touch device still gets it.
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapUp: _enabled
                  ? (_) => setState(() => _pressed = false)
                  : null,
              onTapCancel: _enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              onTap: _enabled ? _activate : null,
              child: _target(
                context,
                // A label replaces what the control shows, rather than adding to it. And a
                // control's text is never selected: a drag over a button is not a selection.
                SelectionContainer.disabled(
                  child: ExcludeSemantics(
                    excluding: widget.semanticLabel != null,
                    child: widget.builder(
                      context,
                      PressableState(
                        hovered: _hovered && _enabled,
                        pressed: _pressed,
                        focused: _focused,
                        enabled: _enabled,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
