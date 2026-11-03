// Ashlar UI: the theme. Copied into your app by `ashlar init`; it is yours to change.
// Every colour, radius and text style the components use comes from here.

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'dart:math' as math;

import 'palette.dart';

/// The colours of a theme, by role. Each `...Foreground` is the colour for text and
/// icons drawn on the colour it is named after.
@immutable
class AshlarColors {
  const AshlarColors({
    required this.background,
    required this.foreground,
    required this.card,
    required this.cardForeground,
    required this.popover,
    required this.popoverForeground,
    required this.primary,
    required this.primaryForeground,
    required this.secondary,
    required this.secondaryForeground,
    required this.muted,
    required this.mutedForeground,
    required this.accent,
    required this.accentForeground,
    required this.destructive,
    required this.destructiveForeground,
    required this.border,
    required this.input,
    required this.ring,
    required this.chart1,
    required this.chart2,
    required this.chart3,
    required this.chart4,
    required this.chart5,
    required this.sidebar,
    required this.sidebarForeground,
    required this.sidebarPrimary,
    required this.sidebarPrimaryForeground,
    required this.sidebarAccent,
    required this.sidebarAccentForeground,
    required this.sidebarBorder,
    required this.sidebarRing,
  });

  /// The page.
  final Color background;

  /// Text and icons on the page.
  final Color foreground;

  /// Cards and panels on the page.
  final Color card;

  /// Text and icons on a card.
  final Color cardForeground;

  /// Menus, popovers and dialogs, which float above the page.
  final Color popover;

  /// Text and icons in a menu, popover or dialog.
  final Color popoverForeground;

  /// The main action: a primary button, a checked box.
  final Color primary;

  /// Text and icons on the primary colour.
  final Color primaryForeground;

  /// A quieter action.
  final Color secondary;

  /// Text and icons on the secondary colour.
  final Color secondaryForeground;

  /// Backgrounds and text that recede: hints, descriptions, placeholders.
  final Color muted;

  /// Text that recedes: hints, descriptions, placeholders.
  final Color mutedForeground;

  /// What is under the pointer or chosen in a list.
  final Color accent;

  /// Text and icons on the accent colour.
  final Color accentForeground;

  /// Actions that destroy or warn.
  final Color destructive;

  /// Text and icons on the destructive colour.
  final Color destructiveForeground;

  /// Lines between things.
  final Color border;

  /// The edge of a field.
  final Color input;

  /// The focus ring.
  final Color ring;

  /// The series of a chart, in order: the first five get these.
  final Color chart1, chart2, chart3, chart4, chart5;

  /// A Sidebar's own surface, text, chosen item, hovered item, lines and focus ring.
  final Color sidebar, sidebarForeground;

  /// The sidebar's chosen item and its mark.
  final Color sidebarPrimary;

  /// Text and icons on the sidebar's primary colour.
  final Color sidebarPrimaryForeground;

  /// A hovered or chosen sidebar item's fill.
  final Color sidebarAccent;

  /// Text and icons on the sidebar's accent colour.
  final Color sidebarAccentForeground;

  /// Lines in and around the sidebar.
  final Color sidebarBorder;

  /// The focus ring inside the sidebar.
  final Color sidebarRing;

  /// The chart colours as a list, for drawing series in turn.
  List<Color> get charts => [chart1, chart2, chart3, chart4, chart5];

  /// These colours with some changed: `AshlarColors.light.copyWith(primary: brand)`.
  AshlarColors copyWith({
    Color? background,
    Color? foreground,
    Color? card,
    Color? cardForeground,
    Color? popover,
    Color? popoverForeground,
    Color? primary,
    Color? primaryForeground,
    Color? secondary,
    Color? secondaryForeground,
    Color? muted,
    Color? mutedForeground,
    Color? accent,
    Color? accentForeground,
    Color? destructive,
    Color? destructiveForeground,
    Color? border,
    Color? input,
    Color? ring,
    Color? chart1,
    Color? chart2,
    Color? chart3,
    Color? chart4,
    Color? chart5,
    Color? sidebar,
    Color? sidebarForeground,
    Color? sidebarPrimary,
    Color? sidebarPrimaryForeground,
    Color? sidebarAccent,
    Color? sidebarAccentForeground,
    Color? sidebarBorder,
    Color? sidebarRing,
  }) => AshlarColors(
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    card: card ?? this.card,
    cardForeground: cardForeground ?? this.cardForeground,
    popover: popover ?? this.popover,
    popoverForeground: popoverForeground ?? this.popoverForeground,
    primary: primary ?? this.primary,
    primaryForeground: primaryForeground ?? this.primaryForeground,
    secondary: secondary ?? this.secondary,
    secondaryForeground: secondaryForeground ?? this.secondaryForeground,
    muted: muted ?? this.muted,
    mutedForeground: mutedForeground ?? this.mutedForeground,
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    destructive: destructive ?? this.destructive,
    destructiveForeground: destructiveForeground ?? this.destructiveForeground,
    border: border ?? this.border,
    input: input ?? this.input,
    ring: ring ?? this.ring,
    chart1: chart1 ?? this.chart1,
    chart2: chart2 ?? this.chart2,
    chart3: chart3 ?? this.chart3,
    chart4: chart4 ?? this.chart4,
    chart5: chart5 ?? this.chart5,
    sidebar: sidebar ?? this.sidebar,
    sidebarForeground: sidebarForeground ?? this.sidebarForeground,
    sidebarPrimary: sidebarPrimary ?? this.sidebarPrimary,
    sidebarPrimaryForeground:
        sidebarPrimaryForeground ?? this.sidebarPrimaryForeground,
    sidebarAccent: sidebarAccent ?? this.sidebarAccent,
    sidebarAccentForeground:
        sidebarAccentForeground ?? this.sidebarAccentForeground,
    sidebarBorder: sidebarBorder ?? this.sidebarBorder,
    sidebarRing: sidebarRing ?? this.sidebarRing,
  );

  /// Neutral, light.
  static const light = AshlarColors(
    background: Color(0xFFFFFFFF),
    foreground: Color(0xFF0A0A0A),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0A0A0A),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF0A0A0A),
    primary: Color(0xFF171717),
    primaryForeground: Color(0xFFFAFAFA),
    secondary: Color(0xFFF5F5F5),
    secondaryForeground: Color(0xFF171717),
    muted: Color(0xFFF5F5F5),
    mutedForeground: Color(0xFF707070),
    accent: Color(0xFFF5F5F5),
    accentForeground: Color(0xFF171717),
    destructive: Color(0xFFE7000B),
    destructiveForeground: Color(0xFFFFFFFF),
    border: Color(0xFFE5E5E5),
    input: Color(0xFFE5E5E5),
    ring: Color(0xFF737373),
    chart1: Color(0xFFF54A00),
    chart2: Color(0xFF009689),
    chart3: Color(0xFF104E64),
    chart4: Color(0xFFFFB900),
    chart5: Color(0xFFFE9A00),
    sidebar: Color(0xFFFAFAFA),
    sidebarForeground: Color(0xFF0A0A0A),
    sidebarPrimary: Color(0xFF171717),
    sidebarPrimaryForeground: Color(0xFFFAFAFA),
    sidebarAccent: Color(0xFFF5F5F5),
    sidebarAccentForeground: Color(0xFF171717),
    sidebarBorder: Color(0xFFE5E5E5),
    sidebarRing: Color(0xFF737373),
  );

  /// Neutral, dark.
  static const dark = AshlarColors(
    background: Color(0xFF0A0A0A),
    foreground: Color(0xFFFAFAFA),
    card: Color(0xFF171717),
    cardForeground: Color(0xFFFAFAFA),
    popover: Color(0xFF171717),
    popoverForeground: Color(0xFFFAFAFA),
    primary: Color(0xFFE5E5E5),
    primaryForeground: Color(0xFF171717),
    secondary: Color(0xFF262626),
    secondaryForeground: Color(0xFFFAFAFA),
    muted: Color(0xFF262626),
    mutedForeground: Color(0xFFA1A1A1),
    accent: Color(0xFF262626),
    accentForeground: Color(0xFFFAFAFA),
    destructive: Color(0xFFFF6467),
    // Red-950: white on this red would be 2.9:1, under the 4.5 text needs.
    destructiveForeground: Color(0xFF460809),
    border: Color(0x1AFFFFFF),
    input: Color(0x26FFFFFF),
    ring: Color(0xFF737373),
    chart1: Color(0xFF1447E6),
    chart2: Color(0xFF00BC7D),
    chart3: Color(0xFFFE9A00),
    chart4: Color(0xFFAD46FF),
    chart5: Color(0xFFFF2056),
    sidebar: Color(0xFF171717),
    sidebarForeground: Color(0xFFFAFAFA),
    sidebarPrimary: Color(0xFF1447E6),
    sidebarPrimaryForeground: Color(0xFFFAFAFA),
    sidebarAccent: Color(0xFF262626),
    sidebarAccentForeground: Color(0xFFFAFAFA),
    sidebarBorder: Color(0x1AFFFFFF),
    sidebarRing: Color(0xFF737373),
  );
}

/// Text styles by size. Colours come from where the text sits, so these carry none.
@immutable
class AshlarText {
  const AshlarText({this.fontFamily, this.fontFamilyFallback});

  /// Null uses the platform's font. Set it, and add the font to pubspec.yaml, to use your own.
  final String? fontFamily;

  /// Fonts to draw what [fontFamily] has no glyph for: symbols, emoji, other scripts.
  final List<String>? fontFamilyFallback;

  TextStyle _size(
    double size,
    double height, [
    FontWeight weight = FontWeight.w400,
  ]) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: 0,
  );

  /// 12/16: badges, captions.
  TextStyle get xs => _size(12, 16);

  /// 14/20: most controls and body text in an app.
  TextStyle get sm => _size(14, 20);

  /// 16/24: reading text.
  TextStyle get base => _size(16, 24);

  /// 18/28.
  TextStyle get lg => _size(18, 28);

  /// 20/28.
  TextStyle get xl => _size(20, 28);

  /// 24/32: page titles.
  TextStyle get xxl => _size(24, 32, FontWeight.w600);

  /// 30/36: a screen's headline, or a figure that stands alone.
  TextStyle get xxxl => _size(30, 36, FontWeight.w600);

  /// 36/40: the largest, for a welcome or a total.
  TextStyle get display => _size(36, 40, FontWeight.w600);
}

/// How a theme spaces and shapes its components: corners, the size of controls, the room
/// inside panels, and whether things cast shadows. Chosen at `ashlar init --style`.
enum AshlarStyle {
  /// Clean and familiar.
  standard(radius: 10, density: 0, spacing: 1, flat: false),

  /// Less room inside, smaller controls.
  compact(radius: 8, density: -1, spacing: .85, flat: false),

  /// Round, with room to breathe.
  rounded(radius: 16, density: 1, spacing: 1.15, flat: false),

  /// Square corners and no shadows: boxy, and at home with a mono font.
  sharp(radius: 2, density: 0, spacing: 1, flat: true),

  /// For screens full of data: the smallest controls and the least room.
  dense(radius: 6, density: -2, spacing: .75, flat: false),

  /// Round corners and soft light.
  soft(radius: 14, density: 0, spacing: 1.05, flat: false);

  const AshlarStyle({
    required this.radius,
    required this.density,
    required this.spacing,
    required this.flat,
  });

  final double radius, density, spacing;
  final bool flat;
}

/// [height], or taller when the text in it is enlarged, as on a phone set to large text:
/// a line of [line] at that size, with the same room around it as at its usual size. [line]
/// is the text's line height at its usual size: 20 for the small text controls use.
double grownHeight(BuildContext context, double height, {double line = 20}) =>
    math.max(
      height,
      MediaQuery.textScalerOf(context).scale(line) + math.max(0, height - line),
    );

/// A whole theme: colours, corners, text, motion.
@immutable
class AshlarThemeData {
  const AshlarThemeData({
    required this.brightness,
    required this.colors,
    this.radius = 10,
    this.text = const AshlarText(),
    this.duration = const Duration(milliseconds: 150),
    this.density = 0,
    this.spacing = 1,
    this.flat = false,
    this.tapTarget,
  });

  /// A theme from its parts: the greys it is built on, a colour for its main actions, and
  /// how it spaces and shapes things.
  ///
  /// ```dart
  /// AshlarApp(
  ///   theme: AshlarThemeData.from(base: AshlarBase.zinc, accent: AshlarAccent.blue),
  ///   darkTheme: AshlarThemeData.from(brightness: Brightness.dark, base: AshlarBase.zinc, accent: AshlarAccent.blue),
  /// )
  /// ```
  factory AshlarThemeData.from({
    Brightness brightness = Brightness.light,
    AshlarBase base = AshlarBase.neutral,
    AshlarAccent? accent,
    AshlarStyle style = AshlarStyle.standard,
    AshlarText text = const AshlarText(),
  }) => AshlarThemeData(
    brightness: brightness,
    colors: ashlarColors(base, brightness, accent),
    radius: style.radius,
    density: style.density,
    spacing: style.spacing,
    flat: style.flat,
    text: text,
  );

  /// Neutral, light.
  const AshlarThemeData.light()
    : this(brightness: Brightness.light, colors: AshlarColors.light);

  /// Neutral, dark.
  const AshlarThemeData.dark()
    : this(brightness: Brightness.dark, colors: AshlarColors.dark);

  /// Light or dark: what the colours were made for.
  final Brightness brightness;

  /// Every colour the components use, by role.
  final AshlarColors colors;

  /// The base corner radius. Controls use [radiusMd]; cards and dialogs [radiusXl].
  final double radius;

  /// The text styles, by size.
  final AshlarText text;

  /// How long a hover, press or open takes.
  final Duration duration;

  /// Controls are 4 taller for each step up, 4 shorter for each step down: 0 is a 36
  /// tall button, -1 a 32, 1 a 40.
  final double density;

  /// The room inside panels, cards and dialogs, as a share of the standard.
  final double spacing;

  /// No shadows: cards, menus and dialogs sit flat, set apart by their borders.
  final bool flat;

  /// The smallest a control's press area may be, in logical pixels; null follows the
  /// platform ([minTapTarget]).
  final double? tapTarget;

  /// The smallest a control's press area is: 44 on iOS and 48 on Android, as each asks
  /// for a finger, and none on the desktop, where a pointer is precise. The control looks
  /// the same; the room it takes and answers presses in grows.
  double get minTapTarget =>
      tapTarget ??
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 44,
        TargetPlatform.android || TargetPlatform.fuchsia => 48,
        _ => 0,
      };

  /// A control's height at this density, from its standard height.
  double control(double standard) => standard + density * 4;

  /// Room inside a panel at this spacing, from the standard room.
  double space(double standard) => (standard * spacing).roundToDouble();

  // Never below square, for a sharp style.
  double get radiusSm => radius > 4 ? radius - 4 : 0;
  double get radiusMd => radius > 2 ? radius - 2 : 0;
  double get radiusLg => radius;
  double get radiusXl => radius + 4;

  /// The ring drawn around a control that has keyboard focus.
  List<BoxShadow> get focusRing => [
    BoxShadow(color: colors.ring.withValues(alpha: .5), spreadRadius: 3),
  ];

  /// The faint shadow under a control.
  List<BoxShadow> get shadowXs => flat
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0D000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ];

  /// The shadow under a card.
  List<BoxShadow> get shadowSm => flat
      ? const []
      : const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 1),
            blurRadius: 3,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 1),
            blurRadius: 2,
            spreadRadius: -1,
          ),
        ];

  /// The shadow under a dialog or a menu.
  List<BoxShadow> get shadowLg => flat
      ? const []
      : const [
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 10),
            blurRadius: 15,
            spreadRadius: -3,
          ),
          BoxShadow(
            color: Color(0x1A000000),
            offset: Offset(0, 4),
            blurRadius: 6,
            spreadRadius: -4,
          ),
        ];

  AshlarThemeData copyWith({
    AshlarColors? colors,
    double? radius,
    AshlarText? text,
    Duration? duration,
    double? density,
    double? spacing,
    bool? flat,
    double? tapTarget,
  }) => AshlarThemeData(
    brightness: brightness,
    colors: colors ?? this.colors,
    radius: radius ?? this.radius,
    text: text ?? this.text,
    duration: duration ?? this.duration,
    density: density ?? this.density,
    spacing: spacing ?? this.spacing,
    flat: flat ?? this.flat,
    tapTarget: tapTarget ?? this.tapTarget,
  );

  /// This theme spaced and shaped as [style], its colours and text kept.
  AshlarThemeData withStyle(AshlarStyle style) => copyWith(
    radius: style.radius,
    density: style.density,
    spacing: style.spacing,
    flat: style.flat,
  );
}

/// Puts a theme in the tree. AshlarApp does this for you.
class AshlarTheme extends InheritedWidget {
  const AshlarTheme({super.key, required this.data, required super.child});

  /// The theme for everything below it.
  final AshlarThemeData data;

  /// The nearest theme, or the light one when there is none.
  static AshlarThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AshlarTheme>()?.data ??
      const AshlarThemeData.light();

  @override
  bool updateShouldNotify(AshlarTheme old) => old.data != data;
}

/// Whether the reading direction runs right to left: for keys and icons that point along
/// the line, which turn round with it.
bool isRtl(BuildContext context) =>
    Directionality.maybeOf(context) == TextDirection.rtl;

/// Keeps [child] above the on-screen keyboard, moving up as it opens: for dialogs, sheets
/// and drawers that hold fields, so what is typed into is never under the keys.
class AboveKeyboard extends StatelessWidget {
  const AboveKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
    // Below this, the keyboard has been made room for.
    child: MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: child,
    ),
  );
}
