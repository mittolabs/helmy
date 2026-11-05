// Your app's theme, written by `ashlar init`: change it here, or choose again with
// `ashlar apply`. Give it to [AshlarApp]: theme: appTheme, darkTheme: appDarkTheme.

import 'package:flutter/widgets.dart';

import '../../../domain/models/settings.dart';
import 'palette.dart';
import 'theme.dart';

final appTheme = AshlarThemeData.from(
  brightness: Brightness.light,
  base: AshlarBase.neutral,
  style: AshlarStyle.standard,
);

/// Helmy's dark look: true black, the page and the sidebar one surface,
/// raised things only just lighter, and hairline borders.
final appDarkTheme = _black(
  AshlarThemeData.from(
    brightness: Brightness.dark,
    base: AshlarBase.neutral,
    style: AshlarStyle.standard,
  ),
);

AshlarThemeData _black(AshlarThemeData t) => t.copyWith(
  colors: t.colors.copyWith(
    background: const Color(0xFF000000),
    card: const Color(0xFF0A0A0A),
    popover: const Color(0xFF0E0E0E),
    secondary: const Color(0xFF1A1A1A),
    muted: const Color(0xFF141414),
    accent: const Color(0xFF1A1A1A),
    border: const Color(0x17FFFFFF),
    input: const Color(0x21FFFFFF),
    sidebar: const Color(0xFF000000),
    sidebarAccent: const Color(0xFF141414),
    sidebarBorder: const Color(0x17FFFFFF),
  ),
);

/// Helmy drawn in [palette] with [accent], for [brightness]; its own colors
/// are [appTheme] and [appDarkTheme].
AshlarThemeData themeFor(
  Brightness brightness, {
  Palette palette = .helmy,
  AccentChoice accent = .none,
  String? font,
  double contrast = 0,
}) {
  final dark = brightness == Brightness.dark;
  final a = accent == .none ? null : AshlarAccent.values.byName(accent.name);
  final AshlarThemeData chosen;
  if (palette == .helmy && a == null) {
    chosen = dark ? appDarkTheme : appTheme;
  } else {
    final base = palette == .helmy ? AshlarBase.neutral : AshlarBase.values.byName(palette.name);
    final t = AshlarThemeData.from(brightness: brightness, base: base, accent: a);
    // Helmy's own stays pure black when dark, with an accent or without.
    chosen = dark && palette == .helmy ? _black(t) : t;
  }
  // Firmer, as asked: borders and quiet text toward the text's own color.
  final c = chosen.colors;
  final k = contrast.clamp(0.0, 1.0);
  final colors = k == 0
      ? c
      : c.copyWith(
          mutedForeground: Color.lerp(c.mutedForeground, c.foreground, k * .6),
          border: Color.lerp(c.border, c.foreground, k * .35),
          input: Color.lerp(c.input, c.foreground, k * .35),
          sidebarBorder: Color.lerp(c.sidebarBorder, c.foreground, k * .35),
        );
  // Compact, as a desktop tool is: every control and menu row a size down.
  return chosen.copyWith(
    density: -1,
    colors: colors,
    text: font == null
        ? null
        : AshlarText(fontFamily: font, fontFamilyFallback: chosen.text.fontFamilyFallback),
  );
}
