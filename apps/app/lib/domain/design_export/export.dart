import 'dart:convert';
import 'dart:io';

import 'design_model.dart';
import 'flutter_writer.dart';
import 'image_size.dart' as image;
import 'planner.dart';
import 'reader.dart';
import 'react_writer.dart';

/// What a design can be exported as.
enum ExportTarget {
  web('Web', 'The pages as they are'),
  react('React', 'A Vite project, TypeScript, React Router'),
  flutter('Flutter', 'On Ashlar UI, the house standard'),
  flutterPlain('Flutter, plain', 'Widgets only, for any app');

  const ExportTarget(this.label, this.description);
  final String label;
  final String description;
}

/// Writes the design in [design] into [to] as [target]: the files written,
/// relative to [to]. [measure] keys every element of a Flutter export by
/// where it is in the page, for `make design-check`.
Future<List<String>> exportDesign(
  String design,
  String to,
  ExportTarget target, {
  bool measure = false,
  Future<List<int>?> Function(Uri url)? fetch,
}) async {
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
        await put(e.key, utf8.encode(e.value));
      }
      for (final a in out.assets.toList()..sort()) {
        final f = File('$design/$a');
        if (f.existsSync()) await put('public/$a', await f.readAsBytes());
      }
    case ExportTarget.flutter || ExportTarget.flutterPlain:
      final plan = planDesign(title: read.title, screens: read.screens);
      // The design's typefaces, as files an app bundles.
      final faces = await googleFonts(read.screens, fetch: fetch ?? _get);
      final out = writeFlutter(
        plan,
        flavor: target == ExportTarget.flutter ? FlutterFlavor.ashlar : FlutterFlavor.plain,
        measure: measure,
        fonts: [
          for (final f in faces)
            (family: f.family, weight: f.weight, italic: f.italic, asset: f.asset),
        ],
        imageSize: (a) {
          final f = File('$design/$a');
          return f.existsSync() ? image.imageSize(f.readAsBytesSync()) : null;
        },
      );
      for (final e in out.files.entries) {
        await put(e.key, utf8.encode(e.value));
      }
      for (final f in faces) {
        await put(f.asset, f.bytes);
      }
      for (final a in out.assets.toList()..sort()) {
        final f = File('$design/$a');
        if (f.existsSync()) await put('assets/$a', await f.readAsBytes());
      }
      if (target == ExportTarget.flutter) {
        written.addAll(await _ashlar(to));
      }
  }
  written.sort();
  return written;
}

/// Ashlar UI set up in the app as the house does it: its theme and app in
/// `lib/ui/core/ashlar`, and Pressable for links. Says why when the
/// `ashlar` command is not there to run.
Future<List<String>> _ashlar(String to) async {
  try {
    final init = await Process.run(
      'ashlar',
      ['init', '--path', 'lib/ui/core/ashlar', '--no-agents'],
      workingDirectory: to,
      runInShell: true,
    );
    if (init.exitCode != 0) throw ProcessException('ashlar', const ['init'], '${init.stderr}');
    await Process.run('ashlar', ['add', 'pressable'], workingDirectory: to, runInShell: true);
    return const [];
  } on Object {
    const note = 'ASHLAR.md';
    await File('$to/$note').writeAsString(
      '# Ashlar UI\n\nThis app is built on Ashlar UI. Its components were not copied in, as the '
      '`ashlar` command was not found. Install it and run, in this folder:\n\n'
      '```\ndart pub global activate ashlar\nashlar init --path lib/ui/core/ashlar\nashlar add pressable\n```\n',
    );
    return const [note];
  }
}

/// One weight of a typeface, downloaded.
typedef FontFace = ({String family, int weight, bool italic, String asset, List<int> bytes});

/// The Google Fonts the screens link to, as TTF files (one per weight), at
/// `assets/fonts/<Family_Name>-<weight>.ttf`.
Future<List<FontFace>> googleFonts(
  List<DScreen> screens, {
  required Future<List<int>?> Function(Uri url) fetch,
}) async {
  final hrefs = <String>{
    for (final s in screens)
      for (final l in s.links)
        if (RegExp(r'href="([^"]+)"').firstMatch(l)?[1] case final h?
            when h.contains('fonts.googleapis.com'))
          h.replaceAll('&amp;', '&'),
  };
  final out = <FontFace>[];
  final seen = <String>{};
  for (final href in hrefs) {
    final css = await fetch(Uri.parse(href));
    if (css == null) continue;
    for (final face in RegExp(r'@font-face\s*\{([^}]*)\}').allMatches(utf8.decode(css))) {
      final body = face[1]!;
      final family = RegExp(r"font-family:\s*'?([^';]+)'?").firstMatch(body)?[1];
      final weight =
          int.tryParse(RegExp(r'font-weight:\s*(\d+)').firstMatch(body)?[1] ?? '400') ?? 400;
      final italic = body.contains('font-style: italic');
      final url = RegExp(r'url\(([^)]+\.ttf)\)').firstMatch(body)?[1];
      if (family == null || url == null) continue;
      final asset = 'assets/fonts/${family.replaceAll(' ', '_')}-$weight${italic ? 'i' : ''}.ttf';
      if (!seen.add(asset)) continue;
      final bytes = await fetch(Uri.parse(url));
      if (bytes != null)
        out.add((family: family, weight: weight, italic: italic, asset: asset, bytes: bytes));
    }
  }
  return out;
}

/// A GET without a browser's name: Google Fonts then serves TTF, which
/// Flutter takes.
Future<List<int>?> _get(Uri url) async {
  final client = HttpClient()..userAgent = null;
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    if (res.statusCode != 200) return null;
    return [for (final chunk in await res.toList()) ...chunk];
  } on Object {
    return null;
  } finally {
    client.close();
  }
}
