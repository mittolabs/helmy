import 'dart:convert';

/// A VS Code color theme brought into Helmy: its name, whether it is dark,
/// and its colors by Helmy's names (background, foreground, ...), as ARGB.
typedef ImportedTheme = ({String name, bool dark, Map<String, int> colors});

/// Reads a VS Code theme file (`.json`, comments and trailing commas
/// allowed). Null when it is not one: no `colors` Helmy can use.
ImportedTheme? readVsCodeTheme(String text, {String fallbackName = 'Imported'}) {
  final Object? json;
  try {
    json = jsonDecode(_jsonc(text));
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final vs = (json['colors'] as Map?)?.cast<String, Object?>() ?? const {};
  int? c(List<String> keys) {
    for (final k in keys) {
      if (_hex(vs[k]) case final v?) return v;
    }
    return null;
  }

  final background = c(['editor.background']);
  final foreground = c(['editor.foreground', 'foreground']);
  if (background == null || foreground == null) return null;
  final type = '${json['type'] ?? ''}'.toLowerCase();
  final dark = type.isNotEmpty ? type != 'light' && type != 'hc-light' : _luma(background) < .5;
  final colors = <String, int>{
    'background': background,
    'foreground': foreground,
    'card': ?c(['editorWidget.background', 'sideBar.background']),
    'popover': ?c(['editorWidget.background', 'menu.background', 'dropdown.background']),
    'sidebar': ?c(['sideBar.background', 'activityBar.background']),
    'muted': ?c(['input.background', 'editorWidget.background']),
    'mutedForeground': ?c(['descriptionForeground', 'editorLineNumber.foreground']),
    'border': ?c(['panel.border', 'editorGroup.border', 'contrastBorder', 'widget.border']),
    'input': ?c(['input.border', 'panel.border', 'editorGroup.border']),
    'primary': ?c(['button.background', 'focusBorder']),
    'primaryForeground': ?c(['button.foreground']),
    'accent': ?c(['list.hoverBackground', 'list.activeSelectionBackground']),
    'ring': ?c(['focusBorder']),
    'destructive': ?c(['errorForeground', 'editorError.foreground']),
  };
  final name = '${json['name'] ?? ''}'.trim();
  return (name: name.isEmpty ? fallbackName : name, dark: dark, colors: colors);
}

/// [text] with `//` and `/* */` comments, and commas before a closing
/// bracket, taken out: VS Code's JSON as JSON. Strings are left alone.
String _jsonc(String text) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  while (i < text.length) {
    final ch = text[i];
    if (inString) {
      out.write(ch);
      if (ch == r'\' && i + 1 < text.length) {
        out.write(text[i + 1]);
        i += 2;
        continue;
      }
      if (ch == '"') inString = false;
      i++;
      continue;
    }
    if (ch == '"') {
      inString = true;
      out.write(ch);
      i++;
    } else if (text.startsWith('//', i)) {
      final end = text.indexOf('\n', i);
      i = end < 0 ? text.length : end;
    } else if (text.startsWith('/*', i)) {
      final end = text.indexOf('*/', i + 2);
      i = end < 0 ? text.length : end + 2;
    } else {
      out.write(ch);
      i++;
    }
  }
  return out.toString().replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1]!);
}

/// "#RRGGBB", "#RRGGBBAA", "#RGB" as ARGB; null for anything else.
int? _hex(Object? v) {
  if (v is! String || !v.startsWith('#')) return null;
  var h = v.substring(1);
  if (h.length == 3 || h.length == 4) h = h.split('').map((x) => '$x$x').join();
  if (h.length == 6) h = '${h}ff';
  if (h.length != 8) return null;
  final rgba = int.tryParse(h, radix: 16);
  if (rgba == null) return null;
  return ((rgba & 0xff) << 24) | (rgba >> 8);
}

double _luma(int argb) {
  final r = (argb >> 16) & 0xff, g = (argb >> 8) & 0xff, b = argb & 0xff;
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
}

/// [t] as settings keep it, and back.
Map<String, Object?> importedThemeToJson(ImportedTheme t) => {
  'name': t.name,
  'dark': t.dark,
  'colors': t.colors,
};

ImportedTheme? importedThemeFromJson(Object? json) {
  if (json is! Map) return null;
  final colors = (json['colors'] as Map?) ?? const {};
  return (
    name: '${json['name'] ?? 'Imported'}',
    dark: json['dark'] == true,
    colors: {
      for (final e in colors.entries)
        if (e.value is int) '${e.key}': e.value as int,
    },
  );
}
