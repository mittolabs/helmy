import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/webhooks.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  test(
    'an event sent to a thread\'s address arrives as its message; others are turned away',
    () async {
      final root = await Directory.systemTemp.createTemp('hooks');
      final storage = storageAt(root);
      addTearDown(() => deleteFolder(root));
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final s =
          (await sessions.create(cwd: root.path, title: 'Watch the PRs') as Ok).value as Session;
      final secret = Webhooks.newSecret();
      expect(secret.length, greaterThanOrEqualTo(32));
      await sessions.save(sessions.byId(s.id)!.copyWith(webhook: secret));

      // A free port, so the test runs beside a Helmy that is open.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final hooks = Webhooks(sessions: sessions, conversations: repo, port: port);
      await hooks.start();
      addTearDown(hooks.stop);
      expect((hooks.listening, hooks.trouble), (true, null));
      expect(hooks.address(secret), 'http://localhost:$port/hooks/$secret');

      final client = HttpClient();
      addTearDown(client.close);
      Future<(int, String)> post(
        String path,
        String body, {
        Map<String, String> headers = const {},
      }) async {
        final r = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
        headers.forEach(r.headers.set);
        r.write(body);
        final res = await r.close();
        return (res.statusCode, await res.transform(utf8.decoder).join());
      }

      final (code, said) = await post(
        '/hooks/$secret',
        '{"action":"opened","number":42}',
        headers: {'content-type': 'application/json', 'x-github-event': 'pull_request'},
      );
      expect(code, 202, reason: said);
      final message = repo.of(s.id).items.whereType<UserMessage>().single;
      expect(message.from, 'a webhook');
      expect(message.text, startsWith('A webhook event arrived (pull_request).'));
      expect(message.text, contains('```json\n{\n  "action": "opened",\n  "number": 42\n}\n```'));

      expect((await post('/hooks/${Webhooks.newSecret()}', '{}')).$1, 404);
      final get = await (await client.getUrl(Uri.parse('http://127.0.0.1:$port/hooks/$secret')))
          .close();
      expect(get.statusCode, 405);
      await get.drain<void>();
      expect((await post('/hooks/$secret', 'x' * (Webhooks.maxBytes + 1))).$1, 413);

      // A sender in a loop is held to its hourly share.
      for (var i = 1; i < Webhooks.perHour; i++) {
        await post('/hooks/$secret', 'ping $i');
      }
      expect((await post('/hooks/$secret', 'one too many')).$1, 429);

      // Turned off, the address goes with it.
      await sessions.save(sessions.byId(s.id)!.copyWith(webhook: ''));
      expect((await post('/hooks/$secret', '{}')).$1, 404);
    },
  );

  test('a port taken says so, with what to do', () async {
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(taken.close);
    final root = await Directory.systemTemp.createTemp('hooks-taken');
    addTearDown(() => deleteFolder(root));
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final hooks = Webhooks(
      sessions: sessions,
      conversations: ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      ),
      port: taken.port,
    );
    await hooks.start();
    expect(hooks.listening, isFalse);
    expect(hooks.trouble, contains('is taken by another program'));
  });
}
