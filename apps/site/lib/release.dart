import 'dart:convert';
import 'dart:io';

/// One file of a release, for one system.
typedef Build = ({String system, String name, String kind, String url, int bytes});

/// The latest stable release, as GitHub has it: `make site` fetches it into
/// `.release.json` before building. Null when there is none yet, or it
/// could not be fetched; the site then says so rather than offering a link.
/// [builds] is empty while a release's files are still being made.
class Release {
  Release._(this.tag, this.url, this.published, this.builds);

  final String tag, url;
  final DateTime? published;
  final List<Build> builds;

  /// The systems in the order a reader looks for them.
  static const systems = ['macOS', 'Windows', 'Linux', 'Android'];

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

  /// What build.yml names each file: `Helmy-<tag>-<this>`.
  static const _files = <String, ({String system, String name, String kind})>{
    '-macos-universal.zip': (system: 'macOS', name: 'Apple silicon and Intel', kind: '.zip · macOS 12 or later'),
    '-windows-x64.zip': (system: 'Windows', name: 'Windows (x64)', kind: '.zip'),
    '-windows-arm64.zip': (system: 'Windows', name: 'Windows on Arm', kind: '.zip'),
    '-linux-x64.tar.gz': (system: 'Linux', name: 'Linux (x64)', kind: '.tar.gz'),
    '-linux-arm64.tar.gz': (system: 'Linux', name: 'Linux (arm64)', kind: '.tar.gz'),
    '-android.apk': (system: 'Android', name: 'Phone app, pairs with Helmy', kind: '.apk'),
  };

  static Build? _build(String file, String url, int bytes) {
    for (final MapEntry(key: end, value: f) in _files.entries) {
      if (file.endsWith(end)) return (system: f.system, name: f.name, kind: f.kind, url: url, bytes: bytes);
    }
    return null;
  }

  static String size(int bytes) =>
      bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB' : '${(bytes / 1024).ceil()} KB';
}
