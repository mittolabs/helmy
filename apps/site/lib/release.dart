import 'dart:convert';
import 'dart:io';

/// One file of a release, for one system.
/// [main] builds show as cards; the rest as a link under them ("On an Intel Mac?"),
/// named by [name].
typedef Build = ({String system, String name, String kind, String url, int bytes, bool main});

/// A stable release, as GitHub has it: `make site` fetches the recent ones
/// into `.release.json` before building, and [load] picks the one to offer.
/// Null when there is none yet, or it could not be fetched; the site then
/// says so rather than offering a link.
/// [builds] is empty while a release's files are still being made.
class Release {
  Release._(this.tag, this.url, this.published, this.builds);

  final String tag, url;
  final DateTime? published;
  final List<Build> builds;

  /// The systems in the order a reader looks for them.
  static const systems = ['macOS', 'Windows', 'Linux', 'Android', 'Chrome'];

  /// The desktop systems every release is built for: a release is ready to offer
  /// once it has a build for each. One just tagged has none until its builds are
  /// attached, a few minutes later; until then the one before is offered, so there
  /// is always something to download. (Android and Chrome come along when they are
  /// there, and a release from before them is no less ready.)
  static const _desktop = ['macOS', 'Windows', 'Linux'];

  bool get ready => _desktop.every((s) => builds.any((b) => b.system == s && b.main));

  /// The recent releases `make site` fetched into `.release.json`, newest first.
  static List<Release> loadAll() {
    final f = File('.release.json');
    if (!f.existsSync()) return const [];
    try {
      final j = jsonDecode(f.readAsStringSync());
      return [
        for (final r in j is List ? j : [j])
          if (r is Map) ?_parse(r),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// The release the download page offers: the newest that is [ready]; with
  /// none ready, the newest, its builds still being made.
  static Release? load() {
    final all = loadAll();
    return all.where((r) => r.ready).firstOrNull ?? all.firstOrNull;
  }

  /// A release newer than [shown] whose builds are still being made, to say so.
  static Release? coming(Release shown) {
    final all = loadAll();
    final newest = all.firstOrNull;
    return newest == null || newest.tag == shown.tag || newest.ready ? null : newest;
  }

  /// The releases before [shown], newest first: each still downloadable.
  static List<Release> earlier(Release shown) {
    final all = loadAll();
    final at = all.indexWhere((r) => r.tag == shown.tag);
    return at < 0 ? const [] : all.skip(at + 1).where((r) => r.builds.isNotEmpty).toList();
  }

  static Release? _parse(Map j) {
    if (j['tag_name'] is! String || j['draft'] == true || j['prerelease'] == true) return null;
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
    '-chrome.zip': (system: 'Chrome', name: 'Extension, pairs with Helmy', kind: '.zip · unzip, then Load unpacked in chrome://extensions', main: true),
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

  /// A release's date, as the page writes it: "Nov 15, 2026".
  static String date(DateTime at) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[at.month - 1]} ${at.day}, ${at.year}';
  }

  static String size(int bytes) =>
      bytes >= 1 << 20 ? '${(bytes / (1 << 20)).toStringAsFixed(0)} MB' : '${(bytes / 1024).ceil()} KB';
}
