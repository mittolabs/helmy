import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../analytics.dart';
import 'star.dart';
import '../release.dart';

/// The opening: what Helmy is, in its own words, with Helmy itself beside
/// the app it lives in.
class Hero extends StatelessComponent {
  const Hero({super.key});

  @override
  Component build(BuildContext context) => section(classes: 'hero', [
    div(classes: 'glow-field', attributes: {'aria-hidden': 'true'}, []),
    div(classes: 'wrap hero-grid', [
      div(classes: 'copy', [
        // As the other Mittolabs sites have it: the mark, in white on the dark page.
        p(classes: 'powered reveal', [
          img(src: '/mittolabs-white.png', alt: '', width: 22, height: 20),
          Component.text('Powered by '),
          b([Component.text('Mittolabs')]),
        ]),
        h1(classes: 'reveal', [
          Component.text('Dream it.'),
          br(),
          span(classes: 'accent', [Component.text('Do it.')]),
        ]),
        p(classes: 'lead reveal', [
          Component.text(
            'Stop hopping between Claude, ChatGPT and the rest. Tell Helmy what you want done. '
            'It picks the right one for each message, moves on when one runs out, and keeps the '
            'whole conversation with you.',
          ),
        ]),
        div(classes: 'cta reveal', [
          a(
            classes: 'btn btn-accent',
            href: '/download',
            attributes: track('get-helmy', {'from': 'hero'}),
            [Component.text('Get Helmy')],
          ),
          a(classes: 'btn btn-ghost', href: '#how', [Component.text('See how it works')]),
        ]),
        p(classes: 'note reveal', [
          Component.text('Free and open source. Pairs with your phone in one scan.'),
        ]),
      ]),
      // Helmy waving: three frames made from the hello pose by the same image pipeline as
      // the poses, played by styles.css (.wave). The resting frame alone stands still.
      div(classes: 'hero-art reveal', [
        div(classes: 'mascot wave', [
          img(src: '/helmy/hello-in.webp', alt: 'Helmy, a small astronaut, waving', width: 320, height: 320),
          img(classes: 'wave-out', src: '/helmy/hello-out.webp', alt: '', width: 320, height: 320),
          img(classes: 'wave-blink', src: '/helmy/hello-blink.webp', alt: '', width: 320, height: 320),
        ]),
      ]),
    ]),
    div(classes: 'wrap shot-wrap reveal', [
      const MacWindow(
        src: '/shots/chat.jpg',
        alt:
            "Helmy on a Mac: asked where November's money went, it totals a spending file by "
            'category and suggests what to cut',
        lazy: false,
      ),
    ]),
  ]);
}

/// A Mac window round a screenshot, with its three lights. The screenshots are
/// real captures of Helmy's window, chats and all (made 2026-11-11 from real
/// runs in a sample folder).
class MacWindow extends StatelessComponent {
  const MacWindow({super.key, required this.src, required this.alt, this.lazy = true});
  final String src, alt;

  /// Off for the first screen, which should not wait for a scroll.
  final bool lazy;

  @override
  Component build(BuildContext context) => figure(classes: 'mac', [
    img(src: src, alt: alt, loading: lazy ? MediaLoading.lazy : null),
  ]);
}

/// A phone round a screenshot.
class Phone extends StatelessComponent {
  const Phone({super.key, required this.src, required this.alt});
  final String src, alt;

  @override
  Component build(BuildContext context) => figure(classes: 'phone', [
    img(src: src, alt: alt, loading: MediaLoading.lazy),
  ]);
}

/// The tools Helmy works through: the ones people already pay for.
class WorksWith extends StatelessComponent {
  const WorksWith({super.key});

  static const _tools = [
    ('/logos/claude.svg', 'Claude Code'),
    ('/logos/openai.svg', 'Codex'),
    ('/logos/cursor.svg', 'Cursor'),
    ('/logos/grok.svg', 'Grok'),
    ('/logos/antigravity.svg', 'Antigravity'),
    ('/logos/opencode.svg', 'OpenCode'),
    ('/logos/ollama.svg', 'Ollama'),
  ];

  @override
  Component build(BuildContext context) => section(classes: 'works wrap', [
    p(classes: 'eyebrow reveal', [Component.text('Works with what you already pay for')]),
    div(classes: 'works-row reveal', [
      for (final (logo, name) in _tools)
        div(classes: 'works-chip', [
          img(src: logo, alt: '', width: 20, height: 20),
          span([Component.text(name)]),
        ]),
    ]),
    p(classes: 'muted reveal center', [
      Component.text(
        "Helmy doesn't resell anything. Sign in with the accounts you already have, and Helmy "
        'uses them all, one conversation across every one of them.',
      ),
    ]),
  ]);
}

/// One thing Helmy does: words on one side, the app (or Helmy) on the other.
class Feature extends StatelessComponent {
  const Feature({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.lead,
    required this.points,
    required this.media,
    this.flip = false,
    this.id,
  });

  final String eyebrow, title, lead;
  final List<String> points;
  final Component media;
  final bool flip;
  final String? id;

  @override
  Component build(BuildContext context) => section(
    id: id,
    classes: 'feature wrap${flip ? ' flip' : ''}',
    [
      div(classes: 'feature-copy', [
        p(classes: 'eyebrow reveal', [Component.text(eyebrow)]),
        h2(classes: 'reveal', [Component.text(title)]),
        p(classes: 'lead reveal', [Component.text(lead)]),
        ul(classes: 'points reveal', [
          for (final point in points) li([Component.text(point)]),
        ]),
      ]),
      div(classes: 'feature-media reveal', [media]),
    ],
  );
}

/// Helmy holding something, big, for a feature with no screenshot of its own.
class Pose extends StatelessComponent {
  const Pose({super.key, required this.src, required this.alt});
  final String src, alt;

  @override
  Component build(BuildContext context) => div(classes: 'pose', [
    div(classes: 'pose-glow', attributes: {'aria-hidden': 'true'}, []),
    img(src: src, alt: alt, width: 300, height: 300, loading: MediaLoading.lazy),
  ]);
}

/// Approvals, argued: people approve what they don't read, so Helmy decides,
/// and asks only what cannot be undone. With the source of the number.
class Approvals extends StatelessComponent {
  const Approvals({super.key});

  @override
  Component build(BuildContext context) => section(classes: 'approvals wrap', [
    div(classes: 'stat reveal', [
      p(classes: 'stat-number', [Component.text('93%')]),
      p(classes: 'muted', [
        Component.text('of permission prompts get approved anyway, according to '),
        a(
          href: 'https://www.anthropic.com/engineering/claude-code-auto-mode',
          [Component.text('Anthropic')],
        ),
        Component.text('. People stop reading them.'),
      ]),
    ]),
    div(classes: 'approvals-copy', [
      p(classes: 'eyebrow reveal', [Component.text('No more Allow, Allow, Allow')]),
      h2(classes: 'reveal', [Component.text('It only asks when it matters.')]),
      p(classes: 'lead reveal', [
        Component.text(
          'Helmy checks every action against what you asked for. Reading files and editing in '
          "the chat's folder just happen, since they can be undone. Anything that leaves your "
          "Mac or can't be taken back comes to you as one plain question.",
        ),
      ]),
      figure(classes: 'ask-shot reveal', [
        img(
          src: '/shots/approval.jpg',
          alt:
              'Helmy asking: organize the downloads folder and move the three older duplicate '
              'or superseded files to Trash? Go ahead, or Don\'t.',
          loading: MediaLoading.lazy,
        ),
      ]),
      p(classes: 'muted small reveal', [
        Component.text(
          'The check sees your messages and the action, never the contents of a web page or a '
          "file. Instructions hidden in them can't talk their way past it. Passwords, keys, "
          'downloaded scripts and sudo always ask you first.',
        ),
      ]),
    ]),
  ]);
}

/// Open source: Helmy's code is the person's to read, change and run.
class OpenSource extends StatelessComponent {
  const OpenSource({super.key});

  @override
  Component build(BuildContext context) => section(id: 'open', classes: 'open wrap', [
    div(classes: 'open-copy', [
      p(classes: 'eyebrow reveal', [Component.text('Open source')]),
      h2(classes: 'reveal', [Component.text('Yours to read, change and run.')]),
      p(classes: 'lead reveal', [
        Component.text('Helmy is BSD licensed, and '),
        a(href: repoUrl, [Component.text('its code is on GitHub')]),
        Component.text(
          ". There is nothing to pay for. It runs on subscriptions you already have. Don't "
          'like something? Change it, or ship your own build.',
        ),
      ]),
      ul(classes: 'points reveal', [
        li([Component.text('Free. No Helmy account to make.')]),
        li([Component.text('Your chats, files and keys stay on your computer.')]),
        li([Component.text("Nothing you'd want for yourself is held back.")]),
      ]),
      div(classes: 'star-ask reveal', [
        p([Component.text('Like Helmy? A star on GitHub helps more people find it.')]),
        const Star(from: 'open source', large: true),
      ]),
    ]),
    div(classes: 'feature-media reveal', [
      const Pose(src: '/helmy/onboarding-folders.png', alt: 'Helmy holding an open folder'),
    ]),
  ]);
}

/// The way to get it, honestly: the download, or that the builds are on their way.
class Get extends StatelessComponent {
  const Get({super.key});

  @override
  Component build(BuildContext context) {
    final out = Release.load()?.builds.isNotEmpty ?? false;
    return section(id: 'get', classes: 'get wrap', [
      img(
        classes: 'get-mascot reveal',
        src: '/helmy/onboarding-done.png',
        alt: 'Helmy jumping for joy',
        width: 200,
        height: 200,
        loading: MediaLoading.lazy,
      ),
      h2(classes: 'reveal', [Component.text(out ? 'Get Helmy.' : 'Coming soon.')]),
      p(classes: 'lead reveal center', [
        Component.text(
          out
              ? 'Free and open source. On first run it connects to Claude Code, Codex, Cursor, '
                    "Grok, Antigravity, OpenCode or Ollama. Have none? It installs OpenCode for you."
              : "Helmy's builds for macOS, Windows and Linux are on their way. On first run it "
                    'connects to Claude Code, Codex, Cursor, Grok, Antigravity, OpenCode or Ollama. Have none? It installs '
                    'OpenCode for you.',
        ),
      ]),
      div(classes: 'cta center reveal', [
        if (out)
          a(
            classes: 'btn btn-accent',
            href: '/download',
            attributes: track('get-helmy', {'from': 'end of page'}),
            [Component.text('Download')],
          )
        else
          span(
            classes: 'btn btn-accent disabled',
            attributes: {'aria-disabled': 'true'},
            [
              Component.text('Download, soon'),
            ],
          ),
      ]),
    ]);
  }
}
