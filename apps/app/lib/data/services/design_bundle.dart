import 'dart:convert';
import 'dart:io';

import 'design_server.dart';

/// A chat's design as one message for the phone: its index and each
/// screen's page, the design folder's own pictures and fonts packed into
/// the page, so the phone needs nothing else. Null when there is none.
/// Reads only inside [folder].
Future<Map<String, Object?>?> designBundle(String folder, {int limit = 24 << 20}) async {
  final index = File('$folder/canvas.json');
  if (!index.existsSync()) return null;
  final Object? canvas;
  try {
    canvas = jsonDecode(await index.readAsString());
  } on FormatException {
    return null;
  }
  if (canvas is! Map) return null;
  final boards = (canvas['boards'] as Map?) ?? const {};
  final order = [for (final f in (canvas['order'] as List?) ?? boards.keys) '$f']
      .where(boards.containsKey)
      .toList();
  final screens = <String, String>{};
  var size = 0;
  for (final file in order) {
    final f = DesignServer.fileIn(folder, file);
    if (f == null || !f.existsSync()) continue;
    final page = packAssets(await f.readAsString(), folder, file);
    size += page.length;
    if (size > limit) break;
    screens[file] = page;
  }
  return {'canvas': canvas, 'order': order, 'screens': screens};
}

/// [page] (the screen [file] in [folder]) with each picture, font or
/// stylesheet it names from the design folder put in as data, so it shows
/// where the folder is not. Web addresses, other screens and anything
/// outside the folder are left as they are.
String packAssets(String page, String folder, String file) {
  final dir = file.contains('/') ? file.substring(0, file.lastIndexOf('/') + 1) : '';
  String? data(String ref) {
    final r = ref.trim();
    if (r.isEmpty ||
        r.startsWith('data:') ||
        r.startsWith('#') ||
        r.startsWith('/') ||
        RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(r) ||
        r.endsWith('.html') ||
        r.endsWith('.htm')) {
      return null;
    }
    final path = Uri.decodeFull(r.split('#').first.split('?').first);
    final f = DesignServer.fileIn(folder, _normal('$dir$path'));
    if (f == null || !f.existsSync() || f.lengthSync() > 8 << 20) return null;
    final type = _typeOf(f.path);
    if (type == null) return null;
    return 'data:$type;base64,${base64.encode(f.readAsBytesSync())}';
  }

  return page
      .replaceAllMapped(
        RegExp(r'''(\b(?:src|href|poster)\s*=\s*)(["'])([^"']*)\2''', caseSensitive: false),
        (m) {
          final d = data(m[3]!);
          return d == null ? m[0]! : '${m[1]}${m[2]}$d${m[2]}';
        },
      )
      .replaceAllMapped(RegExp(r'''url\(\s*(["']?)([^"')]+)\1\s*\)''', caseSensitive: false), (m) {
        final d = data(m[2]!);
        return d == null ? m[0]! : 'url("$d")';
      });
}

/// [path] with `.` and `..` worked out; null parts dropped. One that would
/// leave the folder keeps its `..`, and is refused by fileIn.
String _normal(String path) {
  final out = <String>[];
  for (final p in path.split('/')) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
    } else {
      out.add(p);
    }
  }
  return out.join('/');
}

String? _typeOf(String path) => switch (path.split('.').last.toLowerCase()) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'svg' => 'image/svg+xml',
  'avif' => 'image/avif',
  'woff2' => 'font/woff2',
  'woff' => 'font/woff',
  'ttf' => 'font/ttf',
  'otf' => 'font/otf',
  'css' => 'text/css',
  'mp4' => 'video/mp4',
  'webm' => 'video/webm',
  _ => null,
};
