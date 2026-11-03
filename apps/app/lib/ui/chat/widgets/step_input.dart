import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../../domain/models/permission_rule.dart';
import '../../core/ashlar/theme.dart';

/// The colors code is drawn in, for the theme's brightness.
class CodeColors {
  const new({
    required this.plain,
    required this.quiet,
    required this.string,
    required this.flag,
    required this.number,
  });

  final Color plain, quiet, string, flag, number;

  static CodeColors of(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    final dark = c.background.computeLuminance() < .3;
    return CodeColors(
      plain: c.foreground,
      quiet: c.mutedForeground,
      string: dark ? const Color(0xFF8FD3A6) : const Color(0xFF1F7A45),
      flag: dark ? const Color(0xFF8DB8F2) : const Color(0xFF2357B5),
      number: dark ? const Color(0xFFE8B66F) : const Color(0xFFA35A00),
    );
  }
}

/// What a piece of a shell command is, for coloring it.
enum ShellPart { program, flag, string, operator, number, word, space }

/// [command] cut into the pieces a reader tells apart: the program each
/// command runs, its flags, quoted strings, and the operators between.
List<(ShellPart, String)> shellParts(String command) {
  final out = <(ShellPart, String)>[];
  var i = 0;
  var commandStart = true;
  const operators = ['&&', '||', '2>&1', '>>', ';', '|', '>', '<', '&'];
  while (i < command.length) {
    final ch = command[i];
    if (ch == ' ' || ch == '\t' || ch == '\n') {
      final start = i;
      while (i < command.length && ' \t\n'.contains(command[i])) {
        i++;
      }
      out.add((.space, command.substring(start, i)));
      if (command.substring(start, i).contains('\n')) commandStart = true;
      continue;
    }
    if (ch == '"' || ch == "'") {
      final start = i++;
      while (i < command.length && command[i] != ch) {
        if (command[i] == r'\' && ch == '"') i++;
        i++;
      }
      i = (i + 1).clamp(0, command.length);
      out.add((.string, command.substring(start, i)));
      commandStart = false;
      continue;
    }
    final op = operators.where((o) => command.startsWith(o, i)).firstOrNull;
    if (op != null) {
      out.add((.operator, op));
      i += op.length;
      commandStart = op != '>' && op != '>>' && op != '<' && op != '2>&1';
      continue;
    }
    final start = i;
    while (i < command.length && !' \t\n"\';|&<>'.contains(command[i])) {
      i++;
    }
    final word = command.substring(start, i);
    final part = commandStart && !word.contains('=')
        ? ShellPart.program
        : word.startsWith('-')
        ? ShellPart.flag
        : RegExp(r'^\d+$').hasMatch(word)
        ? ShellPart.number
        : ShellPart.word;
    out.add((part, word));
    if (part == .program) commandStart = false;
  }
  return out;
}

/// A shell command, colored.
TextSpan shellSpan(String command, CodeColors c, TextStyle base) => TextSpan(
  style: base,
  children: [
    for (final (part, text) in shellParts(command))
      TextSpan(
        text: text,
        style: switch (part) {
          .program => TextStyle(color: c.plain, fontWeight: FontWeight.w700),
          .flag => TextStyle(color: c.flag),
          .string => TextStyle(color: c.string),
          .number => TextStyle(color: c.number),
          .operator => TextStyle(color: c.quiet),
          _ => TextStyle(color: c.plain),
        },
      ),
  ],
);

/// What went into a step, as fields to read rather than JSON: the command
/// colored, paths and text as they are, anything else as compact values.
class StepInput extends StatelessWidget {
  const new(this.input, {super.key});
  final Map<String, Object?> input;

  static const _maxChars = 4000;

  /// Fields the step's title already says.
  static const _shownElsewhere = {'description'};

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = CodeColors.of(context);
    final mono = t.text.xs.copyWith(fontFamily: 'Menlo', height: 1.5, color: c.plain);
    final fields = [
      for (final e in input.entries)
        if (!_shownElsewhere.contains(e.key) && e.value != null && e.value != '') e,
    ];
    Widget value(String key, Object? v) {
      if (key == 'command' && v is String) {
        return Text.rich(shellSpan(PermissionRule.plainCommand(v), c, mono));
      }
      final text = switch (v) {
        String s => s,
        num() || bool() => '$v',
        _ => const JsonEncoder.withIndent('  ').convert(v),
      };
      final cut = text.length > _maxChars ? '${text.substring(0, _maxChars)}\n...' : text;
      return Text(
        cut,
        style: mono.copyWith(
          color: switch (v) {
            num() || bool() => c.number,
            String() => c.plain,
            _ => c.quiet,
          },
        ),
      );
    }

    return Container(
      padding: const .symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.colors.muted.withValues(alpha: .5),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          for (final e in fields)
            // A lone command needs no label: it reads as one.
            if (fields.length == 1 && e.key == 'command')
              value(e.key, e.value)
            else
              Row(
                crossAxisAlignment: .start,
                spacing: 12,
                children: [
                  SizedBox(
                    width: 84,
                    child: Text(
                      _label(e.key),
                      style: t.text.xs.copyWith(color: c.quiet, height: 1.5),
                    ),
                  ),
                  Expanded(child: value(e.key, e.value)),
                ],
              ),
        ],
      ),
    );
  }

  /// "file_path" reads as "file path", "old_string" as "old string".
  static String _label(String key) => key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp('([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}');
}
