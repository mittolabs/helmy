import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/domain/vscode_theme.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';

/// A VS Code color theme brought in: read with its comments and trailing
/// commas, its colors Helmy's, for the brightness it is.
void main() {
  test('a theme file, comments and all', () {
    final t = readVsCodeTheme('''
{
  // A comment.
  "name": "Night Owl-ish",
  "type": "dark",
  "colors": {
    "editor.background": "#011627",
    "editor.foreground": "#d6deeb", /* inline */
    "button.background": "#7e57c2cc",
    "focusBorder": "#122d42",
    "descriptionForeground": "#abc",
  },
}
''');
    expect(t, isNotNull);
    expect((t!.name, t.dark), ('Night Owl-ish', true));
    expect(t.colors['background'], 0xFF011627);
    expect(t.colors['primary'], 0xCC7E57C2);
    expect(t.colors['mutedForeground'], 0xFFAABBCC);
    expect(readVsCodeTheme('{"name": "no colors"}'), isNull);
    expect(readVsCodeTheme('not json'), isNull);

    final dark = themeFor(Brightness.dark, palette: .imported, imported: t);
    expect(dark.colors.background, const Color(0xFF011627));
    expect(dark.colors.foreground, const Color(0xFFD6DEEB));
    // For dark only: light stays Helmy's.
    final light = themeFor(Brightness.light, palette: .imported, imported: t);
    expect(light.colors.background, themeFor(Brightness.light).colors.background);
    expect(importedThemeFromJson(importedThemeToJson(t))?.colors, t.colors);
    const s = AppSettings(
      palette: .imported,
      themeImport: {'name': 'X', 'dark': true, 'colors': {}},
    );
    expect(AppSettings.fromJson(s.toJson()).themeImport?['name'], 'X');
  });

  test('the themes VS Code ships read too', () {
    final f = File(
      '/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/theme-monokai/themes/monokai-color-theme.json',
    );
    if (!f.existsSync()) return;
    // Shipped themes name themselves in their extension, not the file.
    final t = readVsCodeTheme(f.readAsStringSync(), fallbackName: 'Monokai');
    expect(t?.name, 'Monokai');
    expect(t?.dark, isTrue);
    expect(t?.colors['background'], isNotNull);
  });
}
