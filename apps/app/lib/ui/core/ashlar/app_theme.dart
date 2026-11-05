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
}) {
  final dark = brightness == Brightness.dark;
  final a = accent == .none ? null : AshlarAccent.values.byName(accent.name);
  if (palette == .helmy && a == null) return dark ? appDarkTheme : appTheme;
  final base = palette == .helmy ? AshlarBase.neutral : AshlarBase.values.byName(palette.name);
  final t = AshlarThemeData.from(brightness: brightness, base: base, accent: a);
  // Helmy's own stays pure black when dark, with an accent or without.
  return dark && palette == .helmy ? _black(t) : t;
}
