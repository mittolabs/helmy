import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// A Mac that starts listening (null: nothing went wrong), or says why not.
class _Mac extends DesktopService {
  _Mac(this.why);
  final String? why;
  final calls = <bool>[];

  @override
  Future<String?> dictate({required bool on}) async {
    calls.add(on);
    return why;
  }
}

/// Dictation that started is listening, not "not available": the mic was
/// on while the chat showed it as missing.
void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ConversationRepositoryEngines repo;
  late Session s;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dictation');
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
    s = (await sessions.create(cwd: '/w', title: 'Talk') as Ok).value as Session;
  });
  tearDown(() async {
    repo.dispose();
    await deleteFolder(root);
  });

  ChatViewModel chat(DesktopService? desktop) {
    final vm = ChatViewModel(
      sessionId: s.id,
      sessions: sessions,
      conversations: repo,
      desktop: desktop,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test('started, it is listening, with nothing to say', () async {
    final mac = _Mac(null);
    expect(await chat(mac).dictate(on: true), isNull);
    expect(mac.calls, [true]);
  });

  test("refused, it says the Mac's reason", () async {
    final why = 'Helmy may not use the microphone.';
    expect(await chat(_Mac(why)).dictate(on: true), why);
  });

  test('with no desktop at all, it says dictation is not here', () async {
    expect(await chat(null).dictate(on: true), 'Dictation is not available here.');
  });
}
