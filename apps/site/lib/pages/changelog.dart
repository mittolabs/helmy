import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';

/// One line of a release: what changed, the area it belongs to, and whether it
/// was a fix.
typedef Entry = ({String area, String text, bool fix});

/// A release as release-please writes it in CHANGELOG.md.
typedef Release = ({String version, DateTime? date, List<Entry> entries});

/// Releases, read from the repository's CHANGELOG.md when the site is built,
/// grouped into the areas a reader knows Helmy by. Every line comes from the
/// file; only its presentation changes here.
class Changelog extends StatelessComponent {
  const Changelog({super.key});

  /// The areas, in the order a reader meets them, and the commit scopes in each.
  /// A scope missing here lands in "Everything else", so nothing is dropped.
  static const _areas = <String, List<String>>{
    'Chats': [
      'chats',
      'chat',
      'sessions',
      'composer',
      'answers',
      'steps',
      'attachments',
      'sidebar',
      'header',
      'navigation',
      'dialogs',
      'problems',
      'import',
      'chat-apps',
      'schedule',
    ],
    'Design and preview': ['design', 'preview', 'browser', 'panels', 'changes', 'files', 'terminal'],
    'Phone': ['phone', 'remote'],
    'Devices': ['device', 'computer-use', 'mac'],
    'Connections': ['connections', 'routing', 'identity', 'memory'],
    'Approvals and the vault': ['approvals', 'vault'],
    'Projects': ['projects', 'worktrees', 'pulls', 'pull-requests', 'snapshots'],
    'Look and feel': ['appearance', 'palette', 'icon', 'mascot', 'splash', 'window', 'keyboard'],
    'The app': ['settings', 'general', 'about', 'onboarding', 'launch', 'app', 'maintenance', 'build', 'parity'],
    'Windows and Linux': ['windows'],
    'helmy.ke': ['site'],
  };

  static const _other = 'Everything else';

  static String _areaOf(String scope) {
    for (final MapEntry(key: area, value: scopes) in _areas.entries) {
      if (scopes.contains(scope)) return area;
    }
    return _other;
  }

  /// Names as their owners write them, and a capital to start.
  static const _names = <String, String>{
    'helmy': 'Helmy',
    'vs code': 'VS Code',
    'open vsx': 'Open VSX',
    'macos': 'macOS',
    'ios': 'iOS',
    'android': 'Android',
    'linux': 'Linux',
    'claude code': 'Claude Code',
    'codex': 'Codex',
    'ollama': 'Ollama',
    'opencode': 'OpenCode',
    'github': 'GitHub',
    'tailscale': 'Tailscale',
    'safari': 'Safari',
    'xcode': 'Xcode',
    'mcp': 'MCP',
    'qr': 'QR',
    'pdf': 'PDF',
    'url': 'URL',
    'mac': 'Mac',
  };

  static String _polish(String text) {
    var t = text.trim();
    for (final MapEntry(key: from, value: to) in _names.entries) {
      t = t.replaceAllMapped(RegExp('\\b$from\\b', caseSensitive: false), (_) => to);
    }
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  static final _heading = RegExp(r'^## \[?([0-9][^\]\s]*)\]?(?:\([^)]*\))?\s*\((\d{4}-\d{2}-\d{2})\)');
  static final _line = RegExp(r'^\* (?:\*\*([\w-]+):\*\* )?(.*?)(?: \(\[[0-9a-f]{7,}\]\([^)]*\)\))?$');

  static List<Release> _releases() {
    final f = File('../../CHANGELOG.md');
    if (!f.existsSync()) return const [];
    final out = <Release>[];
    var fix = false;
    for (final raw in f.readAsLinesSync()) {
      final line = raw.trim();
      if (line.startsWith('## ')) {
        final m = _heading.firstMatch(line);
        // A heading with no version (the file's own note at the end) closes the releases.
        if (m == null) break;
        out.add((version: m[1]!, date: DateTime.tryParse(m[2]!), entries: []));
        fix = false;
      } else if (line.startsWith('### ')) {
        fix = line.toLowerCase().contains('fix');
      } else if (out.isNotEmpty && line.startsWith('* ')) {
        final m = _line.firstMatch(line);
        if (m == null) continue;
        out.last.entries.add((area: _areaOf(m[1] ?? ''), text: _polish(m[2]!), fix: fix));
      }
    }
    return [
      for (final r in out)
        if (r.entries.isNotEmpty) r,
    ];
  }

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// How many lines an area shows before the rest fold away.
  static const _shown = 5;

  @override
  Component build(BuildContext context) {
    final releases = _releases();
    return Component.fragment([
      const PageTitle('Changelog · Helmy'),
      const Nav(),
      main_([
        const PageHead(
          eyebrow: 'Releases',
          title: 'Changelog',
          lead: 'New features, improvements and fixes in each Helmy release, newest first.',
        ),
        section(classes: 'wrap releases', [
          if (releases.isEmpty)
            p(classes: 'muted reveal', [
              Component.text('No releases yet. The first comes with the first public build.'),
            ])
          else
            for (final r in releases) _release(r),
        ]),
      ]),
      const Footer(),
    ]);
  }

  Component _release(Release r) {
    final added = r.entries.where((e) => !e.fix).length;
    final fixed = r.entries.length - added;
    final areas = [..._areas.keys, _other]
        .map(
          (name) => (
            name: name,
            entries: [
              ...r.entries.where((e) => e.area == name && !e.fix),
              ...r.entries.where((e) => e.area == name && e.fix),
            ],
          ),
        )
        .where((area) => area.entries.isNotEmpty);
    return article(classes: 'release reveal', [
      header(classes: 'release-head', [
        h2([Component.text(r.version)]),
        p(classes: 'release-meta', [
          if (r.date != null) Component.text('${_date(r.date!)} · '),
          Component.text('$added new, $fixed fixed · '),
          a(href: 'https://github.com/mittolabs/helmy/releases/tag/v${r.version}', [
            Component.text('On GitHub ↗'),
          ]),
        ]),
      ]),
      div(classes: 'areas', [
        for (final area in areas)
          section(classes: 'area', [
            h3([
              Component.text(area.name),
              span(classes: 'area-count', [Component.text('${area.entries.length}')]),
            ]),
            ul([for (final e in area.entries.take(_shown)) _entry(e)]),
            if (area.entries.length > _shown)
              details([
                summary([Component.text('${area.entries.length - _shown} more')]),
                ul([for (final e in area.entries.skip(_shown)) _entry(e)]),
              ]),
          ]),
      ]),
    ]);
  }

  Component _entry(Entry e) => li([
    if (e.fix) span(classes: 'tag-fix', [Component.text('Fixed')]),
    Component.text(e.text),
  ]);
}
