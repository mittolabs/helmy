import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';

/// Releases, as release-please writes them in the repository's CHANGELOG.md,
/// read when the site is built.
class Changelog extends StatelessComponent {
  const Changelog({super.key});

  /// Each release: its heading line, and its entries.
  static List<({String title, List<String> lines})> _releases() {
    final f = File('../../CHANGELOG.md');
    if (!f.existsSync()) return const [];
    final out = <({String title, List<String> lines})>[];
    for (final line in f.readAsLinesSync()) {
      if (line.startsWith('## ')) {
        out.add((title: line.substring(3).replaceAllMapped(RegExp(r'\[([^\]]*)\]\([^)]*\)'), (m) => m[1]!), lines: []));
      } else if (out.isNotEmpty && line.trim().startsWith('* ')) {
        out.last.lines.add(line.trim().substring(2).replaceAll(RegExp(r'\s*\(\[[0-9a-f]{7}\]\([^)]*\)\)'), ''));
      }
    }
    return out;
  }

  @override
  Component build(BuildContext context) {
    final releases = _releases();
    return Component.fragment([
      const PageTitle('Changelog · Helmy'),
      const Nav(),
      main_([
        const PageHead(
          eyebrow: 'Changelog',
          title: 'What changed.',
          lead: 'Each release, as it ships.',
        ),
        section(classes: 'wrap releases', [
          if (releases.isEmpty)
            p(classes: 'muted reveal', [
              Component.text('No releases yet. The first comes with the first public build.'),
            ])
          else
            for (final r in releases)
              article(classes: 'release reveal', [
                h3([Component.text(r.title)]),
                ul([for (final l in r.lines) li([Component.text(l)])]),
              ]),
        ]),
      ]),
      const Footer(),
    ]);
  }
}
