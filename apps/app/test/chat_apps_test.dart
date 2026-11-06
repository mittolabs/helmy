import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/remote/remote_repositories.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/chat_app_tools.dart';
import 'package:helmy/data/services/chat_apps.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/widgets/chat_app_view.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

String text(Map<String, Object?> r) => ((r['content']! as List).first as Map)['text'] as String;

void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ConversationRepositoryEngines repo;
  late ChatAppsLocal apps;
  late Session s;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apps');
    final storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final support = Directory('${root.path}/com.mittolabs.helmy')..createSync();
    apps = ChatAppsLocal(appData: () async => support, sessions: sessions, conversations: repo);
    s = (await sessions.create(cwd: root.path, title: 'Game') as Ok).value as Session;
  });
  tearDown(() async {
    await apps.dispose();
    repo.dispose();
    await deleteFolder(root);
  });

  test('an app is made in its chat\'s folder, and keeps what it saves', () async {
    final path = await apps.make(s.id, 'Tic Tac Toe', '<html><body>x</body></html>');
    expect(path, endsWith('/$appsFolder/${s.id}/tic-tac-toe.html'));
    expect(isChatApp(path), isTrue);
    expect(await apps.state(s.id, path), isNull);
    final heard = <AppChange>[];
    apps.changes.listen(heard.add);
    await apps.save(s.id, path, {
      'board': ['X', '', ''],
      'turn': 'helmy',
    });
    expect(await apps.state(s.id, path), {
      'board': ['X', '', ''],
      'turn': 'helmy',
    });
    await pumpEventQueue();
    expect(heard.single.page, isFalse);
  });

  test('another chat, or a file outside the apps, is not reachable', () async {
    final path = await apps.make(s.id, 'Quiz', '<p>q</p>');
    expect(await apps.page('someone-else', path), isNull);
    final secret = File('${root.path}/secret.html')..writeAsStringSync('no');
    expect(await apps.page(s.id, secret.path), isNull);
    await apps.save(s.id, secret.path, {'x': 1});
    expect(File('${root.path}/secret.state.json').existsSync(), isFalse);
    expect(await apps.page(s.id, '${path.substring(0, path.lastIndexOf('/'))}/../x.html'), isNull);
  });

  test('the agent makes one, plays its move with app_state, and reads it back', () async {
    final tools = ChatAppTools(apps);
    final made = await tools.call('app_make', {
      'name': 'Tic Tac Toe',
      'html': '<p>board</p>',
      'state': {'turn': 'you'},
    }, s.id);
    expect(made['isError'], isFalse);
    final path = RegExp(r'!\[Tic Tac Toe\]\(([^)]+)\)').firstMatch(text(made))![1]!;
    expect(text(await tools.call('app_state', {'app': path}, s.id)), '{"turn":"you"}');
    final set = await tools.call('app_state', {
      'app': path,
      'state': {'turn': 'you', 'o': 4},
    }, s.id);
    expect(text(set), contains('Set'));
    expect(await apps.state(s.id, path), {'turn': 'you', 'o': 4});
    expect((await tools.call('app_state', {'app': '/etc/hosts'}, s.id))['isError'], isTrue);
  });

  test('the app tools are allowed without asking', () {
    expect(HelmyTools.claudeTools, contains('mcp__helmy__app_make'));
    expect(HelmyTools.claudeTools, contains('mcp__helmy__app_state'));
  });

  test('the bridge goes in before the page\'s own scripts', () {
    final withHead = withBridge('<html><head><script>go()</script></head></html>', '{"a":1}');
    expect(withHead.indexOf('window.helmy'), lessThan(withHead.indexOf('go()')));
    expect(withHead, contains('var state = {"a":1}'));
    final noHead = withBridge('<!doctype html><html lang="en"><script>go()</script>', 'null');
    expect(noHead.indexOf('window.helmy'), lessThan(noHead.indexOf('go()')));
    expect(noHead, startsWith('<!doctype html>'));
  });

  test('on the phone: the same state, saved there, and the agent\'s move arrives', () async {
    const port = 47931;
    final key = Pairing.newKey();
    final server = RemoteServer(sessions: sessions, conversations: repo, port: port, apps: apps);
    await server.start(key);
    addTearDown(server.stop);
    final path = await apps.make(s.id, 'Tic Tac Toe', '<p>board</p>', state: {'turn': 'you'});
    final link = RemoteLink(Pairing(hosts: const ['127.0.0.1'], port: port, key: key, name: 'S'));
    addTearDown(link.dispose);
    await link.connect();
    for (var i = 0; i < 100 && link.state != LinkState.connected; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    await link.open(s.id);
    final phone = RemoteChatApps(link);
    expect(await phone.page(s.id, path), '<p>board</p>');
    expect(await phone.state(s.id, path), {'turn': 'you'});

    await phone.save(s.id, path, {'turn': 'helmy', 'x': 4});
    for (var i = 0; i < 100 && (await apps.state(s.id, path) as Map?)?['x'] == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(await apps.state(s.id, path), {'turn': 'helmy', 'x': 4});

    final next = phone.changes.firstWhere((c) => (c.state as Map?)?['o'] == 0);
    await ChatAppTools(apps).call('app_state', {
      'app': path,
      'state': {'turn': 'you', 'x': 4, 'o': 0},
    }, s.id);
    expect((await next.timeout(const Duration(seconds: 3))).path, path);
  });
}
