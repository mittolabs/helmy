import 'dart:convert';
import 'dart:io';

import '../../domain/vscode_theme.dart';

/// A theme extension listed on Open VSX, the open registry of VS Code
/// extensions.
typedef ThemeListing = ({String id, String name, String description, String download});

/// Searching Open VSX (open-vsx.org) for color themes, and reading the
/// themes out of one: an extension is a zip with its themes listed in its
/// package.json.
class ThemeMarket {
  static const _api = 'https://open-vsx.org/api';

  Future<String?> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'Helmy');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Theme extensions matching [query], most downloaded first; null when
  /// Open VSX could not be reached.
  Future<List<ThemeListing>?> search(String query) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final body = await _get('$_api/-/search?query=$q&category=Themes&size=20&sortBy=downloadCount');
    if (body == null) return null;
    try {
      final j = jsonDecode(body) as Map;
      return [
        for (final e in (j['extensions'] as List? ?? const []).whereType<Map>())
          if ((e['files'] as Map?)?['download'] case final String download)
            (
              id: '${e['namespace']}.${e['name']}',
              name: '${e['displayName'] ?? e['name']}',
              description: '${e['description'] ?? ''}',
              download: download,
            ),
      ];
    } on Object {
      return null;
    }
  }

  /// The color themes in the extension at [download]; empty when it has
  /// none Helmy can read. Throws when it could not be fetched.
  Future<List<ImportedTheme>> themesIn(String download) async {
    final dir = await Directory.systemTemp.createTemp('helmy-theme');
    try {
      final vsix = File('${dir.path}/theme.vsix');
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(download));
        req.headers.set('User-Agent', 'Helmy');
        final res = await req.close();
        if (res.statusCode != 200) throw HttpException('download failed (${res.statusCode})');
        await res.pipe(vsix.openWrite());
      } finally {
        client.close(force: true);
      }
      Future<String?> read(String path) async {
        final r = await Process.run('/usr/bin/unzip', ['-p', vsix.path, 'extension/$path']);
        return r.exitCode == 0 ? '${r.stdout}' : null;
      }

      final package = jsonDecode(await read('package.json') ?? '{}') as Map;
      final listed = ((package['contributes'] as Map?)?['themes'] as List? ?? const [])
          .whereType<Map>();
      final out = <ImportedTheme>[];
      for (final t in listed) {
        final path = '${t['path'] ?? ''}'.replaceFirst(RegExp(r'^\./'), '');
        final text = await read(path);
        if (text == null) continue;
        final label = '${t['label'] ?? ''}';
        var theme = readVsCodeTheme(text, fallbackName: label.isEmpty ? 'Theme' : label);
        // A theme built on another ("include"): the one it includes first.
        final include = _include(text);
        if (include != null) {
          final dirOf = path.contains('/') ? path.substring(0, path.lastIndexOf('/') + 1) : '';
          final base = await read(_normal('$dirOf$include'));
          final under = base == null ? null : readVsCodeTheme(base);
          if (under != null) {
            theme = (
              name: theme?.name ?? label,
              dark: theme?.dark ?? under.dark,
              colors: {...under.colors, ...?theme?.colors},
            );
          }
        }
        if (theme == null) continue;
        out.add((
          name: label.isNotEmpty ? label : theme.name,
          dark: switch ('${t['uiTheme'] ?? ''}') {
            'vs-dark' || 'hc-black' => true,
            'vs' || 'hc-light' => false,
            _ => theme.dark,
          },
          colors: theme.colors,
        ));
      }
      return out;
    } finally {
      dir.delete(recursive: true).ignore();
    }
  }

  static String? _include(String text) =>
      RegExp(r'"include"\s*:\s*"([^"]+)"').firstMatch(text)?.group(1);

  /// a/b/../c.json as a/c.json.
  static String _normal(String path) {
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else if (part.isNotEmpty && part != '.') {
        out.add(part);
      }
    }
    return out.join('/');
  }
}
