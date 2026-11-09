import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../app.dart';
import '../components/chrome.dart';
import '../components/divider.dart';
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
      const Divider(DividerShape.coil),
      const Feature(
        id: 'how',
        eyebrow: 'Helmy chooses',
        title: 'You say what. Helmy decides how.',
        lead:
            'Every message goes to the connection that can do it, then to the one with the most '
            'of its limit left. Quick questions can go to free models. A thread moves when another '
            'has clearly more room, and carries the conversation with it.',
        points: [
          'No model pickers, no effort dials.',
          'Several Claude Code or Codex accounts, used in turn.',
          'A model on this Mac answers when nothing online can.',
        ],
        media: Pose(
          src: '/helmy/onboarding-connect.png',
          alt: 'Helmy holding a plug',
          note: 'plugs into what you have',
        ),
      ),
      const Divider(DividerShape.wander),
      const Feature(
        flip: true,
        eyebrow: 'Design',
        title: 'Screens on a canvas, made while you talk.',
        lead:
            'Ask for an app\'s screens or a landing page and Helmy lays them out beside the chat: '
            'live pages you can pan, zoom, retype and drag, in each device\'s frame. Point at a '
            'part and say what to change.',
        points: [
          'Phones, tablets and web pages that reflow at every width.',
          'Your edits go back into the files; the agent picks them up.',
          'Comments on any element go to the agent with your message.',
        ],
        media: MacWindow(
          src: '/shots/comment.jpg',
          alt: 'A comment on a design screen\'s heading, waiting in the message box',
        ),
      ),
      const Divider(DividerShape.loop),
      const Feature(
        eyebrow: 'In your hand',
        title: 'Your Mac, and its designs, on your phone.',
        lead:
            'Pair your phone with one scan. Your chats come with you, live: send, approve, stop. '
            'Open a design and hold it in your hand, links between screens and all, redrawn as '
            'the Mac changes it.',
        points: [
          'Sealed with a key only your pairing code carries.',
          'Same Wi-Fi, or anywhere over Tailscale.',
          'See and use the Mac\'s screen when you need to.',
        ],
        media: Phone(
          src: '/shots/phone-design.jpg',
          alt: 'A design\'s welcome screen open on an iPhone',
        ),
      ),
      const Divider(DividerShape.wave),
      const Approvals(),
      const Divider(DividerShape.coil),
      const Feature(
        flip: true,
        eyebrow: 'The vault',
        title: 'Secrets the agent uses, and never sees.',
        lead:
            'API keys live in your Mac\'s Keychain, or in HashiCorp Vault. The agent gets their '
            'names and runs what needs them through Helmy, which blanks every value in what '
            'comes back. It can\'t read .env files at all.',
        points: [
          'Asked for a key, you type it in a private field, never the chat.',
          'A key pasted by mistake is caught before it\'s sent.',
          'helmy run gives your own terminal the same secrets.',
        ],
        media: Pose(
          src: '/helmy/shield.png',
          alt: 'Helmy holding a shield',
          note: 'keeps them',
        ),
      ),
      const Divider(DividerShape.loop),
      const OpenSource(),
      const Divider(DividerShape.wander),
      const Get(),
    ]),
    const Footer(),
  ]);
}
