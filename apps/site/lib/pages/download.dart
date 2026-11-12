import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';
import '../analytics.dart';
import '../release.dart';

/// The builds of the latest release, one card per file, grouped by system.
/// Only what the release actually holds: no release, no buttons.
class Download extends StatelessComponent {
  const Download({super.key});

  @override
  Component build(BuildContext context) {
    final release = Release.load();
    return Component.fragment([
      const PageTitle('Download · Helmy'),
      const Nav(),
      main_(classes: 'download wrap', [
        div(classes: 'download-head reveal', [
          img(src: '/icon.png', alt: '', width: 64, height: 64),
          h1([Component.text('Download Helmy')]),
        ]),
        if (release == null) ...[
          p(classes: 'lead center reveal', [
            Component.text(
              "The first release isn't out yet. When it is, its builds show up here. "
              'Until then, the changelog is the place to watch.',
            ),
          ]),
          div(classes: 'cta center reveal', [
            a(classes: 'btn btn-ghost', href: '/changelog', [Component.text('Read the changelog')]),
          ]),
        ] else if (release.builds.isEmpty) ...[
          p(classes: 'lead center reveal', [
            Component.text('${release.tag} is out, and its builds are still being made. '),
            a(href: release.url, [Component.text('The release on GitHub')]),
            Component.text(' gets them first.'),
          ]),
        ] else ...[
          p(classes: 'download-version reveal', [
            a(href: release.url, [Component.text('${release.tag} ↗')]),
          ]),
          for (final system in Release.systems)
            if (release.builds.any((f) => f.system == system))
              section(classes: 'download-system reveal', [
                h2([Component.text(system)]),
                div(classes: 'download-grid', [
                  for (final b in release.builds.where((b) => b.system == system && b.main))
                    a(
                      classes: 'download-card',
                      href: b.url,
                      attributes: track('download', {'system': b.system, 'build': b.name}),
                      [
                        img(src: '/icon.png', alt: '', width: 32, height: 32),
                        div([
                          p(classes: 'download-name', [Component.text(b.name)]),
                          p(classes: 'download-meta', [
                            Component.text('${b.kind} · ${Release.size(b.bytes)}'),
                          ]),
                        ]),
                      ],
                    ),
                ]),
                if (release.builds.where((f) => f.system == system && !f.main).toList() case final rest
                    when rest.isNotEmpty)
                  p(classes: 'download-other', [
                    Component.text(Release.others[system] ?? 'Also: '),
                    for (final (i, b) in rest.indexed) ...[
                      if (i > 0) Component.text(i == rest.length - 1 ? ' or ' : ', '),
                      a(
                        href: b.url,
                        attributes: track('download', {'system': b.system, 'build': b.name}),
                        [Component.text(b.name)],
                      ),
                    ],
                    Component.text('.'),
                  ]),
              ]),
          // As T3 Code has it: one line in a terminal, which also skips the browser's
          // download warnings. The scripts are web/install.sh and web/install.ps1.
          section(classes: 'download-system reveal', [
            h2([Component.text('Terminal')]),
            p(classes: 'download-other', [Component.text('macOS and Linux:')]),
            pre(
              classes: 'download-cmd',
              attributes: {'data-system': 'macOS and Linux'},
              [
                code([Component.text('curl -fsSL https://helmy.ke/install.sh | sh')]),
              ],
            ),
            p(classes: 'download-other', [Component.text('Windows, in PowerShell:')]),
            pre(
              classes: 'download-cmd',
              attributes: {'data-system': 'Windows'},
              [
                code([Component.text('irm https://helmy.ke/install.ps1 | iex')]),
              ],
            ),
          ]),
          p(classes: 'download-other center reveal', [
            Component.text('All builds are on the '),
            a(href: release.url, [Component.text('GitHub release page ↗')]),
            Component.text('.'),
          ]),
          p(classes: 'muted small reveal', [
            Component.text(
              'Helmy connects to Claude Code, Codex, Cursor, Grok, Antigravity, OpenCode or Ollama on first run. ',
            ),
            a(href: '/docs/getting-started/', [Component.text('Getting started')]),
            Component.text(' walks through it.'),
          ]),
        ],
      ]),
      const Footer(),
    ]);
  }
}
