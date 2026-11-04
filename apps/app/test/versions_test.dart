@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/connections_setup.dart';
import 'package:helmy/data/services/desktop_service.dart';

void main() {
  test('versions here and published, read for real (nothing is updated)', () async {
    final setup = ConnectionsSetup(CliLocator(), DesktopService());
    for (final kind in ['claude', 'codex', 'ollama']) {
      final (installed, latest) = await (
        setup.installedVersion(kind),
        setup.latestVersion(kind),
      ).wait;
      // ignore: avoid_print
      print('$kind: installed $installed, newest $latest');
      expect(installed, isNotNull, reason: '$kind is installed on this Mac');
      expect(latest, isNotNull, reason: "$kind's newest version could be read");
    }
  });
}
