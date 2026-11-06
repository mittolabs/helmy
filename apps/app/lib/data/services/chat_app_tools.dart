import 'dart:convert';

import 'chat_apps.dart';

/// The agent's side of chat apps: making one, and reading and setting its
/// state (its own moves in a game). Tools of Helmy's own because the app
/// lives in Helmy's chat, on the Mac and the phone, which no agent reaches.
class ChatAppTools {
  ChatAppTools(this._apps);
  final ChatAppsLocal _apps;

  static const names = ['app_make', 'app_state'];

  static final list = [
    {
      'name': 'app_make',
      'description':
          'Makes a chat app: a small interactive page shown right in this chat, which the user '
          'uses there on the computer and on their phone, and which keeps its state. Use it for '
          'any game the user wants to play with you, and for anything to use rather than read: a '
          'quiz, flashcards, a checklist, a form for several answers, a calculator, a picker. '
          'Give the whole page as one self-contained HTML file: no outside files or network, '
          'readable in light and dark (prefers-color-scheme), sized by its content and never by '
          'the window (no 100vh), fitting a width of 340 to 900 pixels and compact: at most 460 pixels tall in all, so it is whole on screen with the chat (a taller one is shrunk to fit). Keep words on it few: a title line, whose turn it is, and your line. The same name again '
          'replaces the app. It answers with the line that shows it: put that in your reply.\n\n'
          'The page talks to the chat through window.helmy, there before its own scripts run:\n'
          '- helmy.state: what was last saved, null at first. Draw from it on load, so the app '
          'comes back as it was.\n'
          '- helmy.save(state): keeps any JSON value. Save after every change.\n'
          '- helmy.onState(fn): fn(state) runs when you set the state with app_state. Redraw '
          'from it.\n'
          '- helmy.say(text): tells you what the user did, for you to answer, such as "I played '
          'the center square." It is not shown in the chat, and neither is your answer: the '
          'game stays in the app and the chat stays for talking.\n\n'
          'In a game against you, you are the other player, never the page: no moves of yours '
          'in its code. On the user\'s move the page saves the new state, including whose turn '
          'it is, then says the move; it lets the user move only on their turn, shows when it is '
          'yours ("Helmy is thinking"), and has a way to start again (saved, and said). You '
          'answer by reading the state with app_state, then setting it with your move. What you '
          'say about a move goes in the state too, as "said" (a short line, as a friend across '
          'the table would say it), and the page shows state.said beside the board as yours.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'What it is called, such as "Tic Tac Toe".'},
          'html': {'type': 'string', 'description': 'The whole page.'},
          'state': {'description': 'What it starts from, as JSON; leave out for nothing.'},
        },
        'required': ['name', 'html'],
      },
      'annotations': {'readOnlyHint': false, 'title': 'Make a chat app'},
    },
    {
      'name': 'app_state',
      'description':
          "A chat app's state, by the path app_make gave: what the user has done in it. With "
          'state, sets it instead: the app redraws from it at once, on the computer and the '
          'phone. Read it when the user says something about the app, then set it with your '
          'move or change.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'app': {'type': 'string', 'description': 'The app\'s path, from app_make.'},
          'state': {'description': 'The new state, as JSON; leave out to read it.'},
        },
        'required': ['app'],
      },
      'annotations': {'readOnlyHint': false, 'title': "A chat app's state"},
    },
  ];

  Future<Map<String, Object?>> call(String name, Map args, String? session) async {
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    if (session == null) return says('Chat apps work only in a chat.', error: true);
    switch (name) {
      case 'app_make':
        final title = '${args['name'] ?? ''}'.trim();
        final html = '${args['html'] ?? ''}';
        if (title.isEmpty || html.trim().isEmpty) {
          return says('Give the app a name and its page.', error: true);
        }
        final path = await _apps.make(session, title, html, state: args['state']);
        return says(
          'Made. Show it with this line, on its own, in your reply:\n\n![$title]($path)\n\n'
          'Its path, for app_state: $path',
        );
      case 'app_state':
        final path = '${args['app'] ?? ''}'.trim();
        if (!await _apps.has(session, path)) {
          return says('No app of this chat is at $path. Use the path app_make gave.', error: true);
        }
        if (args.containsKey('state')) {
          await _apps.save(session, path, args['state']);
          return says('Set. The user sees it now.');
        }
        final state = await _apps.state(session, path);
        return says(state == null ? 'Nothing saved yet.' : jsonEncode(state));
    }
    return says('No such tool.', error: true);
  }
}
