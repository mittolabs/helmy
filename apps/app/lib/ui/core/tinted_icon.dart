import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import 'ashlar/theme.dart';

/// A duotone icon in a color of its own, on a faint tile of that color: how
/// Helmy marks things you find by sight (a chat's topic, a section of
/// Settings). Controls keep plain stroke icons, so these stand out.
class TintedIcon extends StatelessWidget {
  const TintedIcon(this.icon, {super.key, required this.hue, this.size = 18, this.muted = false});

  final IconData icon;

  /// Its color's hue, 0 to 360: see [hueOf] for one taken from a name.
  final double hue;

  /// The tile's side; the icon is two thirds of it.
  final double size;

  /// Grey rather than colored: nothing chosen yet.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final dark = t.brightness == Brightness.dark;
    final ink = muted ? c.mutedForeground : tintInk(hue, dark: dark);
    final fill = muted ? c.muted : tintFill(hue, dark: dark);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: .circular(size * .24)),
      child: AshlarIcon(icon, size: size * .66, color: ink),
    );
  }
}

/// The icon's own color for [hue]: light enough on dark, dark enough on light.
Color tintInk(double hue, {required bool dark}) =>
    HSLColor.fromAHSL(1, hue, .7, dark ? .72 : .38).toColor();

/// The tile's faint fill for [hue].
Color tintFill(double hue, {required bool dark}) =>
    HSLColor.fromAHSL(dark ? .18 : .12, hue, .7, .5).toColor();

/// The hues names are given, spread round the wheel.
const tintHues = [210.0, 280.0, 160.0, 25.0, 330.0, 45.0, 190.0, 250.0];

/// A hue for [name]: the same name always gets the same one.
double hueOf(String name) => tintHues[name.codeUnits.fold(0, (a, b) => a + b) % tintHues.length];
