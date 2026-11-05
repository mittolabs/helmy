import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/remote/remote_crypto.dart';
import 'package:helmy/data/services/remote/remote_link.dart';
import 'package:helmy/data/services/remote/remote_server.dart';
import 'package:helmy/data/services/remote/screen_source.dart';

import 'support/storage.dart';

/// A screen that makes frames when told, and keeps what it was asked.
class FakeScreen implements ScreenSource {
  String? refuse;
  String? inputRefuse;
  bool sharing = false;
  int asked = 0;
  String? mark;
  final inputs = <Map<String, Object?>>[];

  @override
  void Function(Uint8List jpeg)? onFrame;
  @override
  void Function(String why)? onStopped;

  @override
  Future<String?> start({required String mark}) async {
    if (refuse != null) return refuse;
    sharing = true;
    this.mark = mark;
    return null;
  }

  @override
  void next() => asked++;

  @override
  Future<void> stop() async => sharing = false;

  @override
  Future<String?> input(Map<String, Object?> args) async {
    inputs.add(args);
    return inputRefuse;
  }

  void frame(List<int> bytes) => onFrame?.call(Uint8List.fromList(bytes));
}

/// The Mac's screen on a paired phone: frames sealed and paced by the
/// phone's receipts, input carried back, the mark, and every way it ends.
void main() {
  late Directory root;
  late ConversationRepositoryEngines repo;
  late ChatRepository chats;
  late RemoteServer server;
  late FakeScreen screen;
  late RemoteLink phone;
  final key = Pairing.newKey();
  const port = 47924;

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('screen');
    final storage = storageAt(root);
    final sessions = SessionRepositoryLocal(storage);
    chats = ChatRepository(storage, sessions);
    await chats.load();
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    screen = FakeScreen();
    server = RemoteServer(
      sessions: sessions,
      conversations: repo,
      chats: chats,
      port: port,
      screen: screen,
    );
    await server.start(key);
    phone = RemoteLink(Pairing(hosts: const ['127.0.0.1'], port: port, key: key, name: 'Studio'));
    await phone.connect();
    await until(() => phone.state == LinkState.connected);
  });
  tearDown(() async {
    phone.dispose();
    await server.stop();
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  test('the phone sees frames one at a time, each after it says it got the last', () async {
    await phone.showScreen();
    await until(() => phone.screenOn && screen.asked == 1);
    expect(screen.sharing, isTrue);
    expect(screen.mark, contains('is viewing this screen'));

    screen.frame([0xFF, 0xD8, 1, 2, 3]);
    await until(() => phone.frame.value != null);
    expect(phone.frame.value, [0xFF, 0xD8, 1, 2, 3]);
    // The phone's receipt is what asks for the next.
    await until(() => screen.asked == 2);
    expect(screen.asked, 2);

    // A frame before the receipt is not sent: the phone keeps the one it has.
    screen
      ..frame([9])
      ..frame([8]);
    await until(() => phone.frame.value?.first == 9);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(phone.frame.value, [9]);
  });

  test('taps and keys reach the Mac; a missing permission is said on the phone', () async {
    await phone.showScreen();
    await until(() => phone.screenOn);
    await phone.input('click', x: .25, y: .5);
    await until(() => screen.inputs.isNotEmpty);
    expect(screen.inputs.single, {'kind': 'click', 'x': .25, 'y': .5});

    screen.inputRefuse = 'accessibility';
    await phone.input('text', more: {'text': 'hi'});
    await until(() => phone.screenTrouble != null);
    expect(phone.screenTrouble, contains('Accessibility'));
    expect(phone.screenOn, isTrue, reason: 'it can still be seen');
  });

  test('input before watching goes nowhere', () async {
    await phone.input('click', x: .5, y: .5);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(screen.inputs, isEmpty);
  });

  test('without Screen Recording, the phone is told how to allow it', () async {
    screen.refuse = 'record';
    await phone.showScreen();
    await until(() => phone.screenTrouble != null);
    expect(phone.screenOn, isFalse);
    expect(phone.screenTrouble, contains('Screen Recording'));
  });

  test('turned off in Settings: refused, and ended for one watching', () async {
    await phone.showScreen();
    await until(() => phone.screenOn);
    server.screenAllowed = () => false;
    await server.endScreen();
    await until(() => !phone.screenOn);
    expect(screen.sharing, isFalse);
    expect(phone.screenTrouble, contains('turned off'));

    await phone.showScreen();
    await until(() => phone.screenTrouble != null);
    expect(phone.screenOn, isFalse);
  });

  test('Stop on the Mac ends it on the phone', () async {
    await phone.showScreen();
    await until(() => phone.screenOn);
    screen.onStopped?.call('mark');
    await until(() => !phone.screenOn);
    expect(phone.screenTrouble, 'Sharing was stopped on the Mac.');
    expect(phone.frame.value, isNull);
  });

  test('the phone leaving stops the sharing', () async {
    await phone.showScreen();
    await until(() => screen.sharing);
    await phone.hideScreen();
    await until(() => !screen.sharing);
    expect(screen.sharing, isFalse);
  });
}
