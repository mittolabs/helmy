import 'package:flutter/widgets.dart';

import '../../domain/identity.dart';
import '../../domain/models/settings.dart';
import '../../domain/vscode_theme.dart';
import '../../utils/platform.dart';
import '../chat/widgets/step_input.dart' show CodeColors;
import 'ashlar/app.dart';
import 'ashlar/app_theme.dart';
import 'ashlar/markdown.dart';
import 'ashlar/theme.dart';
import 'code_highlight.dart';

/// How Helmy looks with [s]: its light and dark themes, which shows, and
/// what every window wraps its page in (text size, code's colors and wrap).
/// The same for the main window and a tab's own, so they always match.
typedef HelmyLook = ({
  AshlarThemeData light,
  AshlarThemeData dark,
  AshlarThemeMode mode,
  TransitionBuilder builder,
});

HelmyLook helmyLook(AppSettings s) {
  final imported = importedThemeFromJson(s.themeImport);
  AshlarThemeData theme(Brightness b) => themeFor(
    b,
    palette: s.palette,
    accent: s.accent,
    font: s.interfaceFont,
    contrast: s.contrast,
    imported: imported,
  );
  return (
    light: theme(.light),
    dark: theme(.dark),
    mode: switch (s.theme) {
      .system => AshlarThemeMode.system,
      .light => AshlarThemeMode.light,
      .dark => AshlarThemeMode.dark,
    },
    // Text size is a scale on every size the theme sets.
    builder: (context, child) {
      // Code's font, and how clocks read, for the helpers that draw them.
      chosenCodeFont = s.codeFont;
      writingStyle = writingStyleFor(s.commitStyle, s.commitNote);
      use24Hour = switch (s.clock) {
        .system => MediaQuery.of(context).alwaysUse24HourFormat,
        .twelve => false,
        .twentyFour => true,
      };
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(s.textSize.scale)),
        child: MarkdownCodeWrap(
          wrap: s.wrapCode,
          // Code in answers, plans and notes in syntax colors, in the theme's palette.
          child: Builder(
            builder: (context) {
              final colors = CodeColors.of(context);
              return MarkdownHighlight(
                highlight: (code, language, base) =>
                    CodeHighlighter.spans(code, language, base, colors),
                child: child!,
              );
            },
          ),
        ),
      );
    },
  );
}
