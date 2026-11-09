import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'vault.dart';

/// A secret an agent asked the person for, waiting in their chat.
class VaultRequest {
  VaultRequest({
    required this.session,
    required this.name,
    required this.why,
    this.shared = false,
    this.question,
  });
  final String session;
  final String name;
  final String why;

  /// Not a secret but a go-ahead: Helmy's question about a command to run
  /// with secrets, answered Go ahead or Don't.
  final String? question;

  /// For every project, not only this chat's.
  final bool shared;
  final _done = Completer<bool>();

  Future<bool> get done => _done.future;
}

/// Secrets asked for and not yet given, for the chat to show a field for.
class VaultRequests extends ChangeNotifier {
  final _open = <VaultRequest>[];

  List<VaultRequest> of(String session) => [..._open.where((r) => r.session == session)];

  /// Asks the person, in [r]'s chat; true once the secret is kept.
  Future<bool> ask(VaultRequest r) {
    _open.add(r);
    notifyListeners();
    return r.done.timeout(
      const Duration(minutes: 15),
      onTimeout: () {
        settle(r, kept: false);
        return false;
      },
    );
  }

  void settle(VaultRequest r, {required bool kept}) {
    if (!_open.remove(r)) return;
    if (!r._done.isCompleted) r._done.complete(kept);
    notifyListeners();
  }
}

/// The agent's side of the vault: the names it can use, a command run with
/// their values (which it never sees: they are blanked from what it prints),
/// and a secret asked of the person through a field of Helmy's own, never in
/// the conversation. Helmy's own tools because the values are Helmy's.
class VaultTools {
  VaultTools(
    this._vault,
    this._requests, {
    required this.projectOf,
    required this.cwdOf,
    required this.check,
  });
  final Vault _vault;
  final VaultRequests _requests;

  /// A chat's project (its repository or folder), and the folder it works in.
  final String? Function(String session) projectOf;
  final String? Function(String session) cwdOf;

  /// Helmy's approvals for a command to run with secrets: null to run it,
  /// else why not, for the agent; or, with ask, the question for the person.
  final Future<({String? stop, String? ask})> Function(String session, String command) check;

  static const names = ['vault_list', 'vault_run', 'vault_ask'];

  static final list = [
    {
      'name': 'vault_list',
      'description':
          "The names of the secrets in the user's vault this chat can use (API keys, passwords, "
          'tokens), never their values. Code reads them as environment variables of these names; '
          'run what needs them with vault_run.',
      'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
      'annotations': {'readOnlyHint': true, 'title': 'Secrets this chat can use'},
    },
    {
      'name': 'vault_run',
      'description':
          "Runs a shell command in this chat's folder with the vault's secrets as environment "
          'variables (by their names), for anything that needs one: a dev server, a script, a '
          'deploy, a test against a real service. Use it instead of reading .env files or asking '
          'for a secret. What it prints comes back with every secret blanked as [NAME]; you never '
          'see a value. It waits up to timeoutSeconds (300 at most) and returns what was printed.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': 'The shell command.'},
          'timeoutSeconds': {'type': 'integer', 'description': 'At most 300; 120 if left out.'},
        },
        'required': ['command'],
      },
      'annotations': {'readOnlyHint': false, 'title': 'Run with secrets'},
    },
    {
      'name': 'vault_ask',
      'description':
          'Asks the user for a secret (an API key, a password, a token) through a private field '
          'of Helmy\'s, which keeps it in their vault. Never ask for a secret in the conversation '
          'and never have it pasted there: use this. It waits for them and answers whether it was '
          'kept; you get its name, never its value. Name it as an environment variable '
          '(STRIPE_SECRET_KEY); say in a few words what it is for.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Its name, such as STRIPE_SECRET_KEY.'},
          'why': {'type': 'string', 'description': 'What it is for, as the user will read it.'},
          'shared': {
            'type': 'boolean',
            'description': 'For every project (a personal token), not only this one.',
          },
        },
        'required': ['name', 'why'],
      },
      'annotations': {'readOnlyHint': false, 'title': 'Ask for a secret'},
    },
  ];

  Future<Map<String, Object?>> call(String name, Map args, String? session) async {
    Map<String, Object?> says(String text, {bool error = false}) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
      'isError': error,
    };
    final project = session == null ? null : projectOf(session);
    if (session == null || project == null) {
      return says('The vault works only in a chat.', error: true);
    }
    switch (name) {
      case 'vault_list':
        final have = _vault.namesFor(project);
        return says(
          have.isEmpty
              ? 'No secrets yet. Ask for one with vault_ask.'
              : 'Secrets this chat can use, by name: ${have.join(', ')}. '
                    'Run what needs them with vault_run.',
        );
      case 'vault_run':
        final command = '${args['command'] ?? ''}'.trim();
        if (command.isEmpty) return says('Give the command to run.', error: true);
        // As any command: judged, and put to the person when it cannot be undone.
        final verdict = await check(session, command);
        if (verdict.stop case final why?) return says("Helmy didn't run it: $why", error: true);
        if (verdict.ask case final question?) {
          final yes = await _requests.ask(
            VaultRequest(session: session, name: '', why: command, question: question),
          );
          if (!yes) return says("The person said not to run it.", error: true);
        }
        final seconds = ((args['timeoutSeconds'] as num?)?.toInt() ?? 120).clamp(1, 300);
        final env = await _vault.envFor(project);
        final ran = await _run(command, cwdOf(session) ?? project, env, Duration(seconds: seconds));
        return says(Vault.redact(ran, env));
      case 'vault_ask':
        final wanted = '${args['name'] ?? ''}'.trim();
        final key = Vault.validName(wanted) ? wanted : Vault.nameFrom(wanted);
        final why = '${args['why'] ?? ''}'.trim();
        final shared = args['shared'] == true;
        final kept = await _requests.ask(
          VaultRequest(session: session, name: key, why: why, shared: shared),
        );
        return kept
            ? says(
                'Kept in the vault as $key${shared ? ' (for every project)' : ''}. Code reads it '
                'as the environment variable $key; run what needs it with vault_run.',
              )
            : says("The user didn't give it. Go on without it, or ask them what they'd like.");
    }
    return says('No such tool.', error: true);
  }

  static Future<String> _run(
    String command,
    String cwd,
    Map<String, String> env,
    Duration limit,
  ) async {
    try {
      final p = await Process.start(
        '/bin/zsh',
        ['-lc', command],
        workingDirectory: cwd,
        environment: env,
      );
      final out = StringBuffer();
      final done = Future.wait([
        p.stdout.transform(utf8.decoder).forEach(out.write),
        p.stderr.transform(utf8.decoder).forEach(out.write),
      ]);
      final code = await p.exitCode.timeout(
        limit,
        onTimeout: () {
          p.kill();
          return -1;
        },
      );
      await done.timeout(const Duration(seconds: 2), onTimeout: () => const []);
      var text = out.toString();
      if (text.length > 30000) text = '…${text.substring(text.length - 30000)}';
      return code == -1
          ? '$text\n(Stopped after ${limit.inSeconds} seconds.)'
          : '$text\n(Exit code $code.)';
    } on Object catch (e) {
      return 'It did not run: $e';
    }
  }
}
