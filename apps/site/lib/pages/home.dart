import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../app.dart';
import '../components/chrome.dart';
import '../components/page_title.dart';
import '../components/sections.dart';

class Home extends StatelessComponent {
  const Home({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    const PageTitle(App.title),
    const Nav(),
    main_([
      const Hero(),
      const WorksWith(),
      const Feature(
        id: 'how',
        eyebrow: 'Helmy chooses',
        title: 'You say what. Helmy figures out how.',
        lead:
            'Each message goes to whichever tool can handle it and has the most room left. '
            'Quick questions can go to free models. If another account has a lot more room, '
            'the chat moves there, history and all.',
        points: [
          'No model picker. No effort dial.',
          'Two Claude accounts? Helmy takes turns.',
          'With Ollama, a model on your Mac answers when you are offline.',
        ],
        media: Pose(
          src: '/helmy/onboarding-connect.png',
          alt: 'Helmy holding a plug',
        ),
      ),
      const Feature(
        flip: true,
        eyebrow: 'Design',
        title: 'Design screens by asking for them.',
        lead:
            "Ask for an app's screens or a landing page. They show up next to the chat as real "
            'pages you can zoom, drag and retype. Point at something and say what to change.',
        points: [
          'Phone, tablet and web sizes. Drag a page to any width.',
          'Your edits save to the files, so Helmy sees them.',
          'Leave a comment on any element and send it with your message.',
        ],
        media: MacWindow(
          src: '/shots/design.jpg',
          alt: 'A chat asking for a bakery\'s landing page, and the page Helmy made, open beside it',
        ),
      ),
      const Feature(
        eyebrow: 'In your hand',
        title: 'Take it with you.',
        lead:
            'Scan a code to pair your phone, and your chats follow you, live. Send a message, '
            'approve something or stop a task from wherever you are. Designs open there too, '
            'and you can tap from screen to screen.',
        points: [
          'Encrypted with a key only your pairing code has.',
          'Works on the same Wi-Fi, or anywhere with Tailscale.',
          "Need the Mac itself? Its screen is a tap away.",
        ],
        media: Phone(
          src: '/shots/phone-chats.jpg',
          alt: 'Helmy on an iPhone, paired with a Mac: its chats, live, with one waiting for approval',
        ),
      ),
      const Approvals(),
      const Feature(
        flip: true,
        eyebrow: 'The vault',
        title: 'Your keys stay out of the chat.',
        lead:
            "API keys live in your Mac's Keychain or in HashiCorp Vault. Helmy can run things "
            'that need them, but only ever sees their names. If a key turns up in the output, '
            "it's blanked out. And .env files are off limits.",
        points: [
          'When a key is needed, you type it in a private field, not the chat.',
          'Paste a key by accident and Helmy stops it before it goes out.',
          'Use the same keys in your own terminal with helmy run.',
        ],
        media: Pose(
          src: '/helmy/shield.png',
          alt: 'Helmy holding a shield',
        ),
      ),
      const OpenSource(),
      const Get(),
    ]),
    const Footer(),
  ]);
}
