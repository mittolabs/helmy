import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';
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
        ] else ...[
          p(classes: 'download-version reveal', [
            a(href: release.url, [Component.text('${release.tag} ↗')]),
          ]),
          for (final system in Release.systems)
            if (release.builds.any((f) => f.system == system))
              section(classes: 'download-system reveal', [
                h2([Component.text(system)]),
                div(classes: 'download-grid', [
                  for (final b in release.builds.where((b) => b.system == system))
                    a(classes: 'download-card', href: b.url, [
                      img(src: '/icon.png', alt: '', width: 32, height: 32),
                      div([
                        p(classes: 'download-name', [Component.text(b.name)]),
                        p(classes: 'download-meta', [
                          Component.text('${b.kind} · ${Release.size(b.bytes)}'),
                        ]),
                      ]),
                    ]),
                ]),
              ]),
          p(classes: 'muted small reveal', [
            Component.text('Helmy connects to Claude Code, Codex, OpenCode or Ollama on first run. '),
            a(href: '/docs/getting-started/', [Component.text('Getting started')]),
            Component.text(' walks through it.'),
          ]),
        ],
      ]),
      const Footer(),
    ]);
  }
}
