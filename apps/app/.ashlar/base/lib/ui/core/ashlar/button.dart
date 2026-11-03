// Ashlar UI: Button. Copied into your app by `ashlar add button`; it is yours to change.

import 'package:flutter/widgets.dart';

import 'group.dart';
import 'pressable.dart';
import 'theme.dart';

enum ButtonVariant {
  /// The main action on a screen.
  primary,

  /// A quieter action beside the main one.
  secondary,

  /// An action with a border and no fill.
  outline,

  /// An action with no border or fill until it is hovered: toolbars, menus.
  ghost,

  /// An action that deletes or cannot be undone.
  destructive,

  /// Text that acts like a link, with no padding at its sides so it sits among words.
  link,
}

enum ButtonSize {
  /// 32 tall.
  sm,

  /// 36 tall.
  md,

  /// 40 tall.
  lg,

  /// A 36 square for one icon: give it a semanticLabel.
  icon,

  /// 24 tall, for dense rows.
  xs,

  /// Squares for one icon: 24, 32 and 40.
  iconXs,
  iconSm,
  iconLg,

  /// 48 tall, for the main action on a phone screen.
  xl,

  /// A 48 square for one icon, beside an [xl] button.
  iconXl,

  /// A 64 square for one icon: the one control a screen is built round, a player's play.
  @Deprecated("icon2xl: a look for one design, not Ashlar UI's. Draw it in your app on Pressable and the theme, or change your copy. Goes in a later release.")
  icon2xl,
}

/// A button. [child] is usually a Text; [leading] and [trailing] an icon each side.
///
/// ```dart
/// Button(onPressed: save, child: Text('Save'))
/// Button(variant: ButtonVariant.outline, leading: AshlarIcon(AshlarIconsRoundedStroke.plus), onPressed: add, child: Text('Add'))
/// Button(size: ButtonSize.icon, semanticLabel: 'Settings', onPressed: open, child: AshlarIcon(AshlarIconsRoundedStroke.settings))
/// Button(size: ButtonSize.xl, expand: true, onPressed: book, child: Text('Book'))
/// Button(size: ButtonSize.iconLg, round: true, badge: unread, semanticLabel: 'Notifications', onPressed: open, child: AshlarIcon(AshlarIconsRoundedStroke.bell))
/// ```
class Button extends StatelessWidget {
  const Button({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.md,
    this.leading,
    this.trailing,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.expand = false,
    this.error = false,
    this.round = false,
    this.badge,
  });

  /// Null disables the button.
  final VoidCallback? onPressed;

  /// What it shows: usually a Text, an icon, or both.
  final Widget child;

  /// Its fill: primary for the main action, then secondary, outline, ghost, destructive
  /// or link.
  final ButtonVariant variant;

  /// Its height and room, or a square for an icon alone.
  final ButtonSize size;

  /// Before the label: usually an icon.
  final Widget? leading;

  /// After the label: usually an icon.
  final Widget? trailing;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// Takes the keyboard's focus when it first appears.
  final bool autofocus;

  /// What a screen reader calls it when its visible text does not say, as for an icon
  /// alone.
  final String? semanticLabel;

  /// Fills the width it is given.
  final bool expand;

  /// Draws it as invalid: a destructive border and ring, as on a field.
  final bool error;

  /// Fully rounded: a pill, or a circle for an icon alone.
  final bool round;

  /// Over its top end corner: a dot that something is new, or a count.
  final Widget? badge;

  bool get _square =>
      size == ButtonSize.icon ||
      size == ButtonSize.iconXs ||
      size == ButtonSize.iconSm ||
      size == ButtonSize.iconLg ||
      size == ButtonSize.iconXl ||
      size == ButtonSize.icon2xl;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder: (context, state) {
        final (Color bg, Color fg, Color? border) = switch (variant) {
          ButtonVariant.primary => (
            state.hovered ? c.primary.withValues(alpha: .9) : c.primary,
            c.primaryForeground,
            null,
          ),
          ButtonVariant.secondary => (
            state.hovered ? c.secondary.withValues(alpha: .8) : c.secondary,
            c.secondaryForeground,
            null,
          ),
          ButtonVariant.destructive => (
            state.hovered ? c.destructive.withValues(alpha: .9) : c.destructive,
            c.destructiveForeground,
            null,
          ),
          ButtonVariant.outline => (
            state.hovered ? c.accent : c.background,
            state.hovered ? c.accentForeground : c.foreground,
            c.input,
          ),
          ButtonVariant.ghost => (
            state.hovered ? c.accent : c.accent.withValues(alpha: 0),
            state.hovered ? c.accentForeground : c.foreground,
            null,
          ),
          ButtonVariant.link => (const Color(0x00000000), c.primary, null),
        };
        final (double standard, double padding, double gap) = switch (size) {
          ButtonSize.sm => (32.0, 12.0, 6.0),
          ButtonSize.md => (36.0, 16.0, 8.0),
          ButtonSize.lg => (40.0, 24.0, 8.0),
          ButtonSize.icon => (36.0, 0.0, 0.0),
          ButtonSize.xs => (24.0, 8.0, 4.0),
          ButtonSize.iconXs => (24.0, 0.0, 0.0),
          ButtonSize.iconSm => (32.0, 0.0, 0.0),
          ButtonSize.iconLg => (40.0, 0.0, 0.0),
          ButtonSize.xl => (48.0, 28.0, 8.0),
          ButtonSize.iconXl => (48.0, 0.0, 0.0),
          ButtonSize.icon2xl => (64.0, 0.0, 0.0),
        };
        final large = size == ButtonSize.xl ||
            size == ButtonSize.iconXl ||
            size == ButtonSize.icon2xl;
        // Taller or shorter with the theme's density.
        final height = t.control(standard);
        final label = DefaultTextStyle.merge(
          style: switch (size) {
            ButtonSize.xs => t.text.xs,
            ButtonSize.xl => t.text.base,
            _ => t.text.sm,
          }.copyWith(
            color: fg,
            fontWeight: FontWeight.w500,
            decoration: variant == ButtonVariant.link && state.hovered
                ? TextDecoration.underline
                : null,
            decorationColor: fg,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: IconTheme.merge(
            data: IconThemeData(
              color: fg,
              size: size == ButtonSize.icon2xl ? 28 : (large ? 20 : 16),
            ),
            // The row sets the height and centres in it; the button hugs it unless [expand].
            // A height at least: larger text makes it taller rather than being cut off.
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: height,
                minWidth: _square ? height : 0,
                maxWidth: _square ? height : double.infinity,
              ),
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (leading != null) ...[leading!, SizedBox(width: gap)],
                  Flexible(child: child),
                  if (trailing != null) ...[SizedBox(width: gap), trailing!],
                ],
              ),
            ),
          ),
        );
        final button = Opacity(
          opacity: state.enabled ? 1 : .5,
          child: AnimatedContainer(
            duration: t.duration,
            // A link is text: no padding at its sides, so it lines up with the words around it.
            padding: EdgeInsets.symmetric(
              horizontal: variant == ButtonVariant.link ? 0 : padding,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: joinedRadius(
                context,
                round ? height : (large ? t.radiusLg : t.radiusMd),
              ),
              border: error
                  ? joinedBorder(context, c.destructive)
                  : border == null
                  ? null
                  : joinedBorder(context, state.focused ? c.ring : border),
              boxShadow: [
                if (state.focused)
                  error
                      ? BoxShadow(
                          color: c.destructive.withValues(alpha: .2),
                          spreadRadius: 3,
                        )
                      : t.focusRing.first,
                if (variant == ButtonVariant.outline ||
                    variant == ButtonVariant.primary ||
                    variant == ButtonVariant.secondary ||
                    variant == ButtonVariant.destructive)
                  ...t.shadowXs,
              ],
            ),
            child: label,
          ),
        );
        if (badge == null) return button;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            button,
            PositionedDirectional(top: 0, end: 0, child: badge!),
          ],
        );
      },
    );
  }
}
