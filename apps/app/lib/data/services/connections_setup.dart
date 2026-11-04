import 'dart:convert';
import 'dart:io';

import '../../utils/platform.dart';
import 'cli_locator.dart';
import 'desktop_service.dart';
import 'engines/ollama/ollama_doctor.dart';

/// Where a connection is in being set up.
enum SetupState {
  /// Not installed on this computer.
  missing,

  /// Installed, not signed in (or, for the model here, not running).
  signedOut,

  /// Ready to use.
  ready,
}

/// One connection, as setup sees it.
typedef ConnectionCheck = ({String id, String name, String does, SetupState state});

/// Gets Helmy's connections ready without a terminal: checks each, installs
/// it with its maker's own installer, and signs in through the browser.
/// Settings (and the first-run page) are the one place these are named.
class ConnectionsSetup {
  ConnectionsSetup(this._locator, this._desktop);
  final CliLocator _locator;
  final DesktopService _desktop;

  static const _names = {
    'claude': ('Claude Code', 'Works in your folders and connected accounts'),
    'codex': ('Codex', 'Works in your folders; makes and changes pictures'),
    'ollama': ('Ollama', 'A model on this computer: answers when nothing online can'),
  };

  Future<String?> _find(String name) async {
    _locator.forget(name);
    return _locator.find(name);
  }

  Future<ProcessResult?> _run(String cmd, List<String> args) async {
    try {
      return await Process.run(cmd, args, environment: await _locator.environment());
    } on Object {
      return null;
    }
  }

  /// Every connection and where it stands.
  Future<List<ConnectionCheck>> check() async => [
    for (final id in _names.keys)
      (id: id, name: _names[id]!.$1, does: _names[id]!.$2, state: await _state(id)),
  ];

  Future<SetupState> _state(String id) async {
    switch (id) {
      case 'claude':
        final bin = await _find('claude');
        if (bin == null) return .missing;
        final r = await _run(bin, ['auth', 'status']);
        try {
          return (jsonDecode('${r?.stdout}') as Map)['loggedIn'] == true ? .ready : .signedOut;
        } on Object {
          return .signedOut;
        }
      case 'codex':
        final bin = await _find('codex');
        if (bin == null) return .missing;
        final r = await _run(bin, ['login', 'status']);
        return r?.exitCode == 0 && '${r?.stdout}${r?.stderr}'.contains('Logged in')
            ? .ready
            : .signedOut;
      case 'ollama':
        if (await _find('ollama') == null && !Directory('/Applications/Ollama.app').existsSync()) {
          return .missing;
        }
        return await OllamaDoctor.answers() ? .ready : .signedOut;
    }
    return .missing;
  }

  /// Installs [id] with its maker's installer; where there is none to run
  /// here, opens its install page. True when it ran an installer that worked.
  Future<bool> install(String id) async {
    final windows = Desktop.current == .windows;
    switch (id) {
      case 'claude':
        final r = windows
            ? await _run('powershell', [
                '-NoProfile',
                '-Command',
                'irm https://claude.ai/install.ps1 | iex',
              ])
            : await _run('bash', ['-c', 'curl -fsSL https://claude.ai/install.sh | bash']);
        return r?.exitCode == 0;
      case 'codex':
        if (await _find('npm') case final npm?) {
          final r = await _run(npm, ['install', '-g', '@openai/codex']);
          if (r?.exitCode == 0) return true;
        }
        await _desktop.open('https://github.com/openai/codex#installation');
        return false;
      case 'ollama':
        if (await _find('brew') case final brew?) {
          final r = await _run(brew, ['install', 'ollama']);
          if (r?.exitCode == 0) {
            await _run(brew, ['services', 'start', 'ollama']);
            return true;
          }
        }
        await _desktop.open('https://ollama.com/download');
        return false;
    }
    return false;
  }

  /// Signs [id] in through the browser (or, for the model here, starts it).
  /// Done when the browser sign-in finishes; true when it worked.
  Future<bool> signIn(String id) async {
    switch (id) {
      case 'claude':
        final bin = await _find('claude');
        if (bin == null) return false;
        return (await _run(bin, ['auth', 'login', '--claudeai']))?.exitCode == 0;
      case 'codex':
        final bin = await _find('codex');
        if (bin == null) return false;
        return (await _run(bin, ['login']))?.exitCode == 0;
      case 'ollama':
        return OllamaDoctor.ensure(start: true);
    }
    return false;
  }
}
