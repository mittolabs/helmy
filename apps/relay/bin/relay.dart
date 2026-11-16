import 'dart:io';

import 'package:helmy_relay/relay.dart';

/// Runs the relay on PORT (8080 by default). `relay --check` asks a running
/// one whether it is up, for the container's health check.
Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  if (args.contains('--check')) {
    try {
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final res = await (await c.get('127.0.0.1', port, '/healthz')).close();
      exit(res.statusCode == 200 ? 0 : 1);
    } on Object {
      exit(1);
    }
  }
  // The phone page, where the image puts it (PAGE, /page by default).
  final page = Directory(Platform.environment['PAGE'] ?? '/page');
  final relay = Relay(page: await page.exists() ? page : null);
  await relay.start(port: port);
  stdout.writeln('Helmy Connect relay on :$port');
  ProcessSignal.sigterm.watch().listen((_) async {
    await relay.stop();
    exit(0);
  });
}
