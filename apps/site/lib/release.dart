import 'dart:convert';
import 'dart:io';

/// One file of a release, for one system.
/// [main] builds show as cards; the rest as a link under them ("On an Intel Mac?"),
/// named by [name].
typedef Build = ({String system, String name, String kind, String url, int bytes, bool main});

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

  /// What build.yml names each file: `Helmy-<tag>-<this>`. The usual machine's build
  /// first, as a card; another architecture's as a link under it.
  static const _files = <String, ({String system, String name, String kind, bool main})>{
    '-macos-arm64.dmg': (system: 'macOS', name: 'Apple silicon', kind: '.dmg · macOS 12 or later', main: true),
    '-macos-x64.dmg': (system: 'macOS', name: 'Intel build', kind: '.dmg', main: false),
    '-windows-x64.exe': (system: 'Windows', name: 'Windows 10, 11', kind: '.exe installer', main: true),
    '-windows-arm64.exe': (system: 'Windows', name: 'Arm build', kind: '.exe', main: false),
    '-linux-x64.deb': (system: 'Linux', name: 'Debian, Ubuntu', kind: '.deb · x86_64', main: true),
    '-linux-x64.AppImage': (system: 'Linux', name: 'Any distribution', kind: 'AppImage · x86_64', main: true),
    '-linux-arm64.deb': (system: 'Linux', name: '.deb', kind: '.deb', main: false),
    '-linux-arm64.AppImage': (system: 'Linux', name: 'AppImage', kind: 'AppImage', main: false),
    '-android.apk': (system: 'Android', name: 'Phone app, pairs with Helmy', kind: '.apk', main: true),
  };

  /// What the link under a system's cards opens with, for another architecture.
  static const others = {
    'macOS': 'On an Intel Mac? Download the ',
    'Windows': 'On Windows on Arm? Download the ',
    'Linux': 'On ARM? Download the arm64 ',
  };

  static Build? _build(String file, String url, int bytes) {
    for (final MapEntry(key: end, value: f) in _files.entries) {
      if (file.endsWith(end)) {
        return (system: f.system, name: f.name, kind: f.kind, url: url, bytes: bytes, main: f.main);
      }
    }
    return null;
  }

  static String size(int bytes) =>
      bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB' : '${(bytes / 1024).ceil()} KB';
}
