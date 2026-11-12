import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';
import '../components/star.dart';

/// The terms for helmy.ke, its docs, the downloads and the app, written from what they
/// are: open source under BSD, working through services each with its own terms, acting
/// on the person's instructions. An accurate first draft, not reviewed by a lawyer; it
/// names no governing law or company address until Mittolabs chooses them.
class Terms extends StatelessComponent {
  const Terms({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    const PageTitle('Terms · Helmy'),
    const Nav(),
    const PageHead(
      eyebrow: 'Legal',
      title: 'Terms',
      lead: 'Last updated November 2026. These terms cover helmy.ke, its docs, the downloads and the Helmy app.',
    ),
    main_(classes: 'wrap prose', [
      h2([Component.text('The software')]),
      p([
        Component.text('Helmy is free and open source under the '),
        a(href: '$repoUrl/blob/main/LICENSE', [Component.text('BSD 3-Clause License')]),
        Component.text(
          '. You may use, change and share it under that license. The builds on this site and '
          'on GitHub are made from that code.',
        ),
      ]),
      h2([Component.text('Your connections')]),
      p([
        Component.text(
          'Helmy works through services you sign in to, such as Claude Code, Codex, Cursor, Grok, '
          'Antigravity, OpenCode and Ollama. Each message goes to the connection that answers it, '
          "under its maker's terms, and your use of each service is governed by those terms. Make "
          'sure you are allowed to use an account with Helmy, for example a work account.',
        ),
      ]),
      h2([Component.text('What Helmy does for you')]),
      p([
        Component.text(
          'Helmy acts on your computer and in your accounts on your instructions: it reads and '
          'changes files, runs commands and sends what you ask it to. You are responsible for what '
          'you ask it to do. Helmy asks you before anything it cannot undo; read those questions '
          'before you answer, and keep backups of what matters.',
        ),
      ]),
      h2([Component.text('This site')]),
      p([
        Component.text(
          "Don't misuse helmy.ke: no attacks, no attempts to break it, and no automated load that "
          'gets in the way of other people using it. What we count here is described in our ',
        ),
        a(href: '/privacy', [Component.text('privacy notice')]),
        Component.text('.'),
      ]),
      h2([Component.text('No warranty')]),
      p([
        Component.text(
          'Helmy and this site are provided as they are, without warranty of any kind. To the '
          'extent the law allows, Mittolabs is not liable for any loss that comes from using them, '
          'including lost data, or charges from the services you connect.',
        ),
      ]),
      h2([Component.text('Changes and contact')]),
      p([
        Component.text(
          'We will update this page when these terms change; the date at the top shows when. For '
          'questions, ',
        ),
        a(href: '$repoUrl/issues/new/choose', [Component.text('open an issue on GitHub')]),
        Component.text('. To report a security problem, follow '),
        a(href: '$repoUrl/blob/main/SECURITY.md', [Component.text('our security policy')]),
        Component.text('.'),
      ]),
    ]),
    const Footer(),
  ]);
}
