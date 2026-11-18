@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connection_installer.dart';

/// Installs the real connections from their makers, into a home folder made
/// for it, never the person's own: run with HOME set to an empty folder and
/// HELMY_LIVE_INSTALL_HOME set to the same, so nothing already installed is
/// touched (`make live-install` does this).
void main() {
  final home = Platform.environment['HOME'] ?? '';
  final ok = home.isNotEmpty && Platform.environment['HELMY_LIVE_INSTALL_HOME'] == home;

  Future<List<InstallStep>> install(String id) async {
    final steps = <InstallStep>[];
    await ConnectionInstaller(CliLocator()).install(id, (s) {
      if (steps.isEmpty || steps.last.doing != s.doing) {
        steps.add(s);
        // ignore: avoid_print
        print('$id: ${s.doing}${s.done == null ? '' : ' (${(s.done! * 100).round()}%)'}');
      }
    });
    return steps;
  }

  test(
    'Claude Code installs from its maker, with how far along shown',
    () async {
      final steps = await install('claude');
      expect(steps.where((s) => s.done != null).length, greaterThan(10), reason: 'real progress');
      expect(steps.last.doing, 'Setting it up…');
      // Where its setup puts it: the login shell's PATH may name the
      // person's own first, so the folder is looked in.
      final bin = '$home/.local/bin/claude';
      expect(File(bin).existsSync(), isTrue);
      final v = await Process.run(bin, ['--version']);
      expect('${v.stdout}', matches(RegExp(r'\d+\.\d+\.\d+')));
    },
    skip: !ok,
    timeout: const Timeout(Duration(minutes: 120)),
  );

  test(
    "Codex installs with its maker's installer, its download watched",
    () async {
      final steps = await install('codex');
      expect(
        steps.any((s) => s.doing.startsWith('Downloading,')),
        isTrue,
        reason: 'the download seen',
      );
      final bin = '$home/.local/bin/codex';
      expect(File(bin).existsSync(), isTrue);
      final v = await Process.run(bin, ['--version']);
      expect('${v.stdout}', matches(RegExp(r'\d+\.\d+\.\d+')));
    },
    skip: !ok,
    timeout: const Timeout(Duration(minutes: 120)),
  );

  test(
    "Ollama's Mac app downloads, matches its checksum and unpacks",
    () async {
      final dir = await Directory.systemTemp.createTemp('ollama-live-');
      addTearDown(() => dir.delete(recursive: true));
      final sums = ConnectionInstaller.parseSums(
        await (await HttpClient().getUrl(
          Uri.parse('${ConnectionInstaller.ollamaLatest}/sha256sum.txt'),
        )).close().then((r) => r.transform(const SystemEncoding().decoder).join()),
      );
      final zip = File('${dir.path}/Ollama-darwin.zip');
      var heard = 0;
      await ConnectionInstaller.download(
        Uri.parse('${ConnectionInstaller.ollamaLatest}/Ollama-darwin.zip'),
        zip,
        name: 'Ollama',
        sha256: sums['Ollama-darwin.zip']!,
        progress: (got, total) => heard++,
      );
      expect(heard, greaterThan(100));
      final r = await Process.run('/usr/bin/ditto', ['-x', '-k', zip.path, '${dir.path}/app']);
      expect(r.exitCode, 0);
      expect(File('${dir.path}/app/Ollama.app/Contents/Resources/ollama').existsSync(), isTrue);
    },
    skip: !ok || !Platform.isMacOS,
    timeout: const Timeout(Duration(minutes: 120)),
  );
}
