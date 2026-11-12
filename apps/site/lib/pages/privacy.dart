import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';

/// What helmy.ke counts, written from what the site does (static pages, no accounts,
/// no cookies, visits and a few clicks counted by our own Umami). An accurate first
/// draft, not reviewed by a lawyer. Change it whenever what is counted changes.
class Privacy extends StatelessComponent {
  const Privacy({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    const PageTitle('Privacy · Helmy'),
    const Nav(),
    const PageHead(
      eyebrow: 'Privacy',
      title: 'What this site counts',
      lead: 'Last updated November 2026. This page covers helmy.ke and its docs, not the Helmy app.',
    ),
    main_(classes: 'wrap prose', [
      h2([Component.text('What we count')]),
      p([
        Component.text(
          'Visits, anonymously: the pages you open, the site that sent you, your browser, device type '
          'and country. And a few clicks: which build you download, the Get Helmy buttons, copying an '
          'install command, and playing a tutorial video. We never collect your name, email address or '
          'anything that identifies you. If your browser sends Do Not Track, nothing is counted.',
        ),
      ]),
      h2([Component.text('Who counts it')]),
      p([
        Component.text(
          'We do, with Umami on our own server. Nothing goes to an advertising or analytics company. We '
          'use it to see which builds people need and what to improve.',
        ),
      ]),
      h2([Component.text('Cookies')]),
      p([Component.text('None.')]),
      h2([Component.text('Sharing')]),
      p([
        Component.text(
          'We do not sell or share what we count. The site loads its typefaces from Google Fonts, which '
          'receives your IP address when your browser asks for them, and downloads come from GitHub, '
          'which counts them too.',
        ),
      ]),
      h2([Component.text('The Helmy app')]),
      p([
        Component.text(
          'Your chats and files stay on your computer, and each message goes to the connection that '
          "answers it, under its maker's terms. The app sends us one thing: error reports, so we can fix "
          'what breaks. They are on at first; turn them off in Settings > General.',
        ),
      ]),
    ]),
    const Footer(),
  ]);
}
