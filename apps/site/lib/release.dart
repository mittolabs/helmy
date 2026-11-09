import 'dart:convert';
import 'dart:io';

/// One file of a release, for one system.
typedef Build = ({String system, String name, String kind, String url, int bytes});

/// The latest stable release, as GitHub has it: `make site` fetches it into
/// `.release.json` before building. Null when there is none yet, or it
/// could not be fetched; the site then says so rather than offering a link.
class Release {
  Release._(this.tag, this.url, this.published, this.builds);

  final String tag, url;
  final DateTime? published;
  final List<Build> builds;

  /// The systems in the order a reader looks for them.
  static const systems = ['macOS', 'Windows', 'Linux'];

  static Release? load() {
    final f = File('.release.json');
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(f.readAsStringSync());
      if (j is! Map || j['tag_name'] is! String || j['draft'] == true || j['prerelease'] == true) {
        return null;
      }
      final builds = <Build>[
        for (final a in (j['assets'] as List? ?? const []).whereType<Map>())
          ?_build('${a['name']}', '${a['browser_download_url']}', (a['size'] as num?)?.toInt() ?? 0),
      ];
      if (builds.isEmpty) return null;
      return Release._(
        j['tag_name'] as String,
        '${j['html_url']}',
        DateTime.tryParse('${j['published_at']}'),
        builds,
      );
    } on FormatException {
      return null;
    }
  }

  /// What build.yml names each system's file.
  static Build? _build(String file, String url, int bytes) {
    if (file.endsWith('-macos.zip')) {
      return (system: 'macOS', name: 'macOS 12 or later', kind: '.zip', url: url, bytes: bytes);
    }
    if (file.endsWith('-windows.zip')) {
      return (system: 'Windows', name: 'Windows (x64)', kind: '.zip', url: url, bytes: bytes);
    }
    if (file.endsWith('-linux.tar.gz')) {
      return (system: 'Linux', name: 'Linux (x64)', kind: '.tar.gz', url: url, bytes: bytes);
    }
    return null;
  }

  static String size(int bytes) =>
      bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB' : '${(bytes / 1024).ceil()} KB';
}
