import 'dart:convert';
import 'dart:io';

import 'vault.dart';

/// Runs [executable] with [args], handing it [input] on standard input:
/// how a value reaches the store without showing in the list of processes.
typedef RunWithInput = Future<({int code, String out})?> Function(
  String executable,
  List<String> args,
  String input,
);

/// The vault's values in the system's own store, off a Mac: Windows
/// Credential Manager, or the login keyring on Linux (through libsecret's
/// `secret-tool`). On a Mac the Keychain is reached by Helmy's own Mac code.
///
/// A value never goes on a command line: it is passed on standard input,
/// and read back on standard output.
class SystemKeychain implements VaultKeychain {
  SystemKeychain({required this.os, RunWithInput? run}) : _run = run ?? _runProcess;

  /// 'windows' or 'linux'.
  final String os;
  final RunWithInput _run;

  /// Where Helmy's values are filed, in both stores.
  static const service = 'Helmy Vault';

  @override
  Future<bool> set(String account, String value) async {
    final r = switch (os) {
      'windows' => await _powershell(windowsSet(account), base64.encode(utf8.encode(value))),
      'linux' => await _run('secret-tool', [
        'store',
        '--label=$service: $account',
        'service',
        service,
        'account',
        account,
      ], value),
      _ => null,
    };
    return r?.code == 0;
  }

  @override
  Future<String?> get(String account) async {
    switch (os) {
      case 'windows':
        final r = await _powershell(windowsGet(account), '');
        if (r == null || r.code != 0) return null;
        try {
          return utf8.decode(base64.decode(r.out.trim()));
        } on FormatException {
          return null;
        }
      case 'linux':
        final r = await _run('secret-tool', ['lookup', 'service', service, 'account', account], '');
        if (r == null || r.code != 0) return null;
        return r.out;
    }
    return null;
  }

  @override
  Future<bool> delete(String account) async {
    final r = switch (os) {
      'windows' => await _powershell(windowsDelete(account), ''),
      'linux' => await _run('secret-tool', ['clear', 'service', service, 'account', account], ''),
      _ => null,
    };
    return r?.code == 0;
  }

  Future<({int code, String out})?> _powershell(String script, String input) => _run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-EncodedCommand',
    encodeForPowershell(script),
  ], input);

  // Windows: Credential Manager, through its WinRT PasswordVault (in the
  // Windows PowerShell every Windows 10 and 11 has). Names and values go
  // across as base64, so no quoting or code page can change them.

  static String _vault(String account) =>
      '''\$ErrorActionPreference = 'Stop'
\$null = [Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
\$vault = New-Object Windows.Security.Credentials.PasswordVault
\$account = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${base64.encode(utf8.encode(account))}'))
''';

  /// Replaces what is kept under [account] with the base64 on standard input.
  static String windowsSet(String account) =>
      '''${_vault(account)}\$value = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String([Console]::In.ReadToEnd().Trim()))
try { \$vault.Remove(\$vault.Retrieve('$service', \$account)) } catch {}
\$vault.Add((New-Object Windows.Security.Credentials.PasswordCredential('$service', \$account, \$value)))''';

  /// Writes what is kept under [account], as base64; fails when nothing is.
  static String windowsGet(String account) =>
      '''${_vault(account)}\$c = \$vault.Retrieve('$service', \$account)
\$c.RetrievePassword()
[Console]::Out.Write([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(\$c.Password)))''';

  /// Removes what is kept under [account]; fails when nothing was.
  static String windowsDelete(String account) =>
      '''${_vault(account)}\$vault.Remove(\$vault.Retrieve('$service', \$account))''';

  /// PowerShell's -EncodedCommand: UTF-16LE, base64.
  static String encodeForPowershell(String script) => base64.encode([
    for (final u in script.codeUnits) ...[u & 0xff, u >> 8],
  ]);

  static Future<({int code, String out})?> _runProcess(
    String executable,
    List<String> args,
    String input,
  ) async {
    try {
      final p = await Process.start(executable, args);
      p.stdin.add(utf8.encode(input));
      await p.stdin.close();
      final out = p.stdout.transform(utf8.decoder).join();
      await p.stderr.drain<void>();
      return (code: await p.exitCode, out: await out);
    } on ProcessException {
      return null;
    }
  }
}
