// helmy.ke as one folder: the site at its root and the docs under /docs/.
//
//   dart run tool/web.dart <site build> <docs build> <out>
//
// The docs are their own Jaspr app, built as if they were the root of a host:
// a <base href="/">, and links and pictures written from "/". Under /docs/
// each of those has to start with /docs/, so the docs' pages are rewritten as
// they are copied. Their scripts are written relative to the base, so the
// base moves with them. Jaspr's packages/ folders are left out of both.
import 'dart:convert';
import 'dart:io';

import 'package:helmy_site/analytics.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln('Usage: dart run tool/web.dart <site build> <docs build> <out>');
    exit(64);
  }
  final [site, docs, out] = args;
  final target = Directory(out);
  if (target.existsSync()) target.deleteSync(recursive: true);
  _copy(Directory(site), target, (_, bytes) => bytes);
  _copy(Directory(docs), Directory('$out/docs'), (path, bytes) {
    if (!path.endsWith('.html')) return bytes;
    // Read as Latin-1 so every byte survives untouched; only ASCII is matched.
    return latin1.encode(
      latin1
          .decode(bytes)
          .replaceAllMapped(
            // An attribute that starts at the root, but not one that starts with "//".
            RegExp(r'''\b(href|src|poster)="/(?!/)'''),
            (m) => '${m[1]}="/docs/',
          )
          // Counted as the site is (lib/analytics.dart): added after the rewrite, so the
          // tracker stays at the root, where the edge serves it.
          .replaceFirst('</head>', '$trackerTags$_shareTags</head>'),
    );
  });
}

void _copy(Directory from, Directory to, List<int> Function(String, List<int>) change) {
  if (!from.existsSync()) {
    stderr.writeln('Missing: ${from.path}');
    exit(66);
  }
  for (final entity in from.listSync(recursive: true)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(from.path.length + 1);
    if (relative == 'packages' || relative.startsWith('packages/')) continue;
    final file = File('${to.path}/$relative')..parent.createSync(recursive: true);
    file.writeAsBytesSync(change(relative, entity.readAsBytesSync()));
  }
}

/// A docs page's link preview on X and elsewhere: the site's card (web/og.png).
const _shareTags =
    '<meta property="og:image" content="https://helmy.ke/og.png">'
    '<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">'
    '<meta name="twitter:card" content="summary_large_image">'
    '<meta name="twitter:image" content="https://helmy.ke/og.png">';
