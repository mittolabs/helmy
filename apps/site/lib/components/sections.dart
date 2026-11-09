import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import 'scribble.dart';

/// The opening: what Helmy is, in its own words, with Helmy itself beside
/// the app it lives in.
class Hero extends StatelessComponent {
  const Hero({super.key});

  @override
  Component build(BuildContext context) => section(classes: 'hero', [
    div(classes: 'glow-field', attributes: {'aria-hidden': 'true'}, []),
    div(classes: 'wrap hero-grid', [
      div(classes: 'copy', [
        p(classes: 'eyebrow reveal', [Component.text('An assistant for your Mac')]),
        h1(classes: 'reveal', [
          Component.text('Dream it.'),
          br(),
          span(classes: 'accent', [Component.text('Do it.')]),
        ]),
        p(classes: 'lead reveal', [
          Component.text(
            'Tell Helmy what you want done. It works in your folders and your accounts, '
            'through the Claude Code, Codex and OpenCode you already have, and picks the right '
            'one for each message so your limits last.',
          ),
        ]),
        div(classes: 'cta reveal', [
          a(classes: 'btn btn-accent', href: '#get', [Component.text('Get Helmy')]),
          a(classes: 'btn btn-ghost', href: '#how', [Component.text('See how it works')]),
        ]),
        p(classes: 'note reveal', [
          Component.text('For macOS. Free while it grows. Your phone joins it in a scan.'),
        ]),
      ]),
      div(classes: 'hero-art reveal', [
        img(
          classes: 'mascot',
          src: '/helmy/hello.png',
          alt: 'Helmy, a small astronaut, waving',
          width: 320,
          height: 320,
        ),
        const Scribble(
          classes: 'tag-hello',
          direction: ScribbleDirection.downLeft,
          text: 'says hi,\nthen gets to work',
        ),
      ]),
    ]),
    div(classes: 'wrap shot-wrap reveal', [
      const MacWindow(
        src: '/shots/canvas.jpg',
        alt: 'Helmy on a Mac: a chat beside its Design tab, phone screens and a landing page laid out on a canvas',
      ),
    ]),
  ]);
}

/// A Mac window round a screenshot, with its three lights.
class MacWindow extends StatelessComponent {
  const MacWindow({super.key, required this.src, required this.alt});
  final String src, alt;

  @override
  Component build(BuildContext context) => figure(classes: 'mac', [
    img(src: src, alt: alt, loading: MediaLoading.lazy),
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
    (null, 'OpenCode'),
    ('/logos/ollama.svg', 'Ollama'),
  ];

  @override
  Component build(BuildContext context) => section(classes: 'works wrap', [
    p(classes: 'eyebrow reveal', [Component.text('Bring your own subscription')]),
    div(classes: 'works-row reveal', [
      for (final (logo, name) in _tools)
        div(classes: 'works-chip', [
          if (logo != null)
            img(src: logo, alt: '', width: 20, height: 20)
          else
            span(classes: 'works-dot', []),
          span([Component.text(name)]),
        ]),
    ]),
    p(classes: 'muted reveal center', [
      Component.text(
        'Helmy resells nothing. It signs into the tools you have, and when one runs low it '
        'moves to another, with the conversation intact. No model pickers: it chooses.',
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
  const Pose({super.key, required this.src, required this.alt, this.note});
  final String src, alt;
  final String? note;

  @override
  Component build(BuildContext context) => div(classes: 'pose', [
    div(classes: 'pose-glow', attributes: {'aria-hidden': 'true'}, []),
    img(src: src, alt: alt, width: 300, height: 300, loading: MediaLoading.lazy),
    if (note != null) p(classes: 'pose-note', [Component.text(note!)]),
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
        Component.text('of permission prompts are approved anyway, measured by '),
        a(
          href: 'https://www.anthropic.com/engineering/claude-code-auto-mode',
          [Component.text('Anthropic')],
        ),
        Component.text('. People stop reading them.'),
      ]),
    ]),
    div(classes: 'approvals-copy', [
      p(classes: 'eyebrow reveal', [Component.text('No more Allow, Allow, Allow')]),
      h2(classes: 'reveal', [Component.text('Asked only what matters.')]),
      p(classes: 'lead reveal', [
        Component.text(
          'Helmy decides what the agents may do, against what you actually asked for. What only '
          'reads, or changes this chat\'s folder, goes ahead: it can be undone. Anything that '
          'leaves your Mac or can\'t be undone comes to you as one plain question.',
        ),
      ]),
      div(classes: 'ask-card reveal', [
        p(classes: 'ask-q', [Component.text('Push the README fix to the main branch?')]),
        div(classes: 'ask-buttons', [
          span(classes: 'btn btn-light btn-sm', [Component.text('Go ahead')]),
          span(classes: 'btn btn-ghost btn-sm', [Component.text("Don't")]),
        ]),
      ]),
      p(classes: 'muted small reveal', [
        Component.text(
          'What the judge sees is what you asked and the action, never what a web page or a '
          'file says, so a planted instruction can\'t argue its way through. Passwords, keys, '
          'downloaded scripts and sudo always come to you.',
        ),
      ]),
    ]),
  ]);
}

/// The way to get it, honestly: not out yet.
class Get extends StatelessComponent {
  const Get({super.key});

  @override
  Component build(BuildContext context) => section(id: 'get', classes: 'get wrap', [
    img(
      classes: 'get-mascot reveal',
      src: '/helmy/onboarding-done.png',
      alt: 'Helmy jumping for joy',
      width: 200,
      height: 200,
      loading: MediaLoading.lazy,
    ),
    h2(classes: 'reveal', [Component.text('Coming to your Mac.')]),
    p(classes: 'lead reveal center', [
      Component.text(
        'Helmy is in early use now. The first public build comes signed and notarized, so '
        'it opens like any app. It needs macOS 12 or later, and Claude Code, Codex, OpenCode '
        'or Ollama to work through: Helmy sets them up for you on first run.',
      ),
    ]),
    div(classes: 'cta center reveal', [
      span(classes: 'btn btn-accent disabled', attributes: {'aria-disabled': 'true'}, [
        Component.text('Download for macOS, soon'),
      ]),
    ]),
  ]);
}
