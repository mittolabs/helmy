import 'dart:convert';
import 'dart:io';

import 'planner.dart';
import 'reader.dart';
import 'react_writer.dart';

/// What a design can be exported as.
enum ExportTarget {
  web('Web', 'The pages as they are'),
  react('React', 'A Vite project, TypeScript, React Router');

  const ExportTarget(this.label, this.description);
  final String label;
  final String description;
}

/// Writes the design in [design] into [to] as [target]: the files written,
/// relative to [to].
Future<List<String>> exportDesign(String design, String to, ExportTarget target) async {
  final read = await readDesign(design);
  final written = <String>[];
  Future<void> put(String path, List<int> bytes) async {
    final f = File('$to/$path');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
    written.add(path);
  }

  switch (target) {
    case ExportTarget.web:
      await for (final e in Directory(design).list(recursive: true)) {
        if (e is! File) continue;
        final rel = e.path.substring(design.length + 1);
        // The canvas's own index and saves are not the site.
        if (rel == 'canvas.json' || rel.endsWith('.helmy-saving')) continue;
        await put(rel, await e.readAsBytes());
      }
    case ExportTarget.react:
      final plan = planDesign(title: read.title, screens: read.screens);
      final out = writeReact(plan);
      for (final e in out.files.entries) {
        await put(e.key, e.value.codeUnits.any((u) => u > 127) ? _utf8(e.value) : e.value.codeUnits);
      }
      for (final a in out.assets.toList()..sort()) {
        final f = File('$design/$a');
        if (f.existsSync()) await put('public/$a', await f.readAsBytes());
      }
  }
  written.sort();
  return written;
}

List<int> _utf8(String s) => utf8.encode(s);
