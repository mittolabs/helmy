import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/attention_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/notify_service.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

class _Notes extends NotifyService {
  @override
  Future<bool?> isActive() async => null;
  final sent = <String>[];
  int badgeCount = 0;
  @override
  Future<void> notify({
    required String sessionId,
    required String title,
    required String body,
    bool thumbsUp = false,
  }) async => sent.add('$title: $body');
  @override
  Future<void> badge(int count) async => badgeCount = count;
  String? dockFace;
  @override
  Future<void> face(String? face) async => dockFace = face;
}

Future<
  ({
    SessionRepositoryLocal sessions,
    ConversationRepositoryEngines repo,
    SettingsRepository settings,
    Directory root,
  })
>
_setup() async {
  final root = await Directory.systemTemp.createTemp('batch');
  final storage = StorageService(root: () async => root);
  final sessions = SessionRepositoryLocal(storage);
  final meter = UsageMeter();
  final repo = ConversationRepositoryEngines(
    engines: EngineRegistry([]),
    router: HeadroomRouter(meter),
    meter: meter,
    storage: storage,
    sessions: sessions,
  );
  return (sessions: sessions, repo: repo, settings: SettingsRepository(storage), root: root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a run of steps is summed up in words', () {
    ToolCall c(String name) => ToolCall(id: name, name: name, input: const {});
    expect(stepsSummary([c('Bash'), c('Bash'), c('Read')]), 'Ran 2 commands and read a file');
    expect(
      stepsSummary([c('Shell'), c('Edit'), c('Write'), c('WebSearch')]),
      'Ran a command, edited 2 files and searched once',
    );
  });

  test('the sidebar shows active sessions, pinned first, grouped by folder', () async {
    final s = await _setup();
    final a = (await s.sessions.create(cwd: '/w/one') as Ok).value as Session;
    final b = (await s.sessions.create(cwd: '/w/two') as Ok).value as Session;
    final c = (await s.sessions.create(cwd: '/w/one') as Ok).value as Session;
    final vm = SidebarViewModel(sessions: s.sessions, conversations: s.repo, settings: s.settings);
    await vm.setPinned(s.sessions.byId(a.id)!, true);
    await vm.setArchived(s.sessions.byId(b.id)!, true);
    expect(vm.shown.map((x) => x.id), [a.id, c.id]);
    await s.settings.save(s.settings.settings.copyWith(show: .archived));
    expect(vm.shown.map((x) => x.id), [b.id]);
    await s.settings.save(s.settings.settings.copyWith(show: .all, group: .folder));
    expect(vm.groups.map((g) => g.folder), ['/w/one', '/w/two']);
    vm.dispose();
    s.repo.dispose();
    await s.root.delete(recursive: true);
  });

  testWidgets('a session that finishes out of sight notifies once and counts on the dock', (
    tester,
  ) async {
    late ({
      SessionRepositoryLocal sessions,
      ConversationRepositoryEngines repo,
      SettingsRepository settings,
      Directory root,
    })
    s;
    late Session session;
    await tester.runAsync(() async {
      s = await _setup();
      session = (await s.sessions.create(cwd: '/w') as Ok).value as Session;
    });
    final notes = _Notes();
    final attention = AttentionRepository(
      conversations: s.repo,
      sessions: s.sessions,
      settings: s.settings,
      notify: notes,
    );
    final c = s.repo.of(session.id);
    // Decisions wait on a question to macOS; let them finish.
    Future<void> settle() =>
        tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    // Busy, then done, while another session is on screen.
    attention.viewing = 'another';
    // Just opened: waking up, then the app icon.
    expect(notes.dockFace, 'waking');
    await tester.pump(AttentionRepository.wakingFor);
    expect(notes.dockFace, isNull);
    c.busy = true;
    c.thinking = true;
    s.repo.notifyListeners();
    await settle();
    expect(notes.dockFace, 'thinking');
    c.thinking = false;
    s.repo.notifyListeners();
    expect(notes.dockFace, 'answering');
    c.busy = false;
    c.items.add(TurnSummary(ok: true));
    s.repo.notifyListeners();
    await settle();
    expect(notes.sent, ['${session.title}: Finished']);
    expect(notes.dockFace, 'done');
    expect(attention.isUnread(session.id), isTrue);
    expect(notes.badgeCount, 1);

    // Opening it clears it.
    attention.viewing = session.id;
    expect(attention.isUnread(session.id), isFalse);
    expect(notes.dockFace, isNull);

    // Waiting for an approval while on screen: no notification.
    c.items.add(
      PermissionPrompt(requestId: 'r', toolName: 'Bash', input: const {}, suggestions: const []),
    );
    s.repo.notifyListeners();
    await settle();
    expect(notes.sent, hasLength(1));
    expect(notes.dockFace, 'needs-you');

    // Turned off in settings: nothing, and no count.
    await tester.runAsync(() => s.settings.save(s.settings.settings.copyWith(notify: false)));
    attention.viewing = 'another';
    c.busy = true;
    s.repo.notifyListeners();
    await settle();
    c.busy = false;
    s.repo.notifyListeners();
    await settle();
    expect(notes.sent, hasLength(1));
    expect(notes.badgeCount, 0);
    attention.dispose();
    s.repo.dispose();
    await tester.runAsync(() => s.root.delete(recursive: true));
  });

  testWidgets('idle with only this Mac to answer, the Dock shows Helmy offline', (tester) async {
    late ({
      SessionRepositoryLocal sessions,
      ConversationRepositoryEngines repo,
      SettingsRepository settings,
      Directory root,
    })
    s;
    late Session session;
    await tester.runAsync(() async {
      s = await _setup();
      session = (await s.sessions.create(cwd: '/w') as Ok).value as Session;
    });
    final notes = _Notes();
    final attention = AttentionRepository(
      conversations: s.repo,
      sessions: s.sessions,
      settings: s.settings,
      notify: notes,
    );
    // Unknown until a message has been routed: the app icon.
    expect(s.repo.onlyThisMac, isNull);
    // Checked at launch: no connection is on, so only this Mac can answer.
    expect(await tester.runAsync(s.repo.checkReach), isTrue);
    await tester.runAsync(() async {
      await s.repo.send(session, 'hello');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    expect(s.repo.onlyThisMac, isTrue);
    attention.viewing = session.id;
    s.repo.notifyListeners();
    expect(notes.dockFace, 'waking');
    await tester.pump(AttentionRepository.wakingFor);
    expect(notes.dockFace, 'offline');
    attention.dispose();
    s.repo.dispose();
    await tester.runAsync(() => s.root.delete(recursive: true));
  });
}
