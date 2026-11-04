import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

void main() {
  test(
    'what is written and not sent stays with its thread, shows in the list, and goes when sent',
    () async {
      final root = await Directory.systemTemp.createTemp('drafts');
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
      final s = (await sessions.create(cwd: root.path, title: 'Budget') as Ok).value as Session;
      repo.of(s.id).loaded = true;
      final vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
      final sidebar = SidebarViewModel(
        sessions: sessions,
        conversations: repo,
        settings: FakeSettingsRepository(),
      );
      addTearDown(sidebar.dispose);

      vm.keepDraft('Split the salaries line\nby team');
      await vm.saveDraft();
      expect(sessions.byId(s.id)!.draft, 'Split the salaries line\nby team');
      expect(sidebar.lineOf(sessions.byId(s.id)!).text, 'Draft: Split the salaries line');

      // Kept on disk: Helmy opened again finds it.
      await storage.flush();
      final again = SessionRepositoryLocal(storage);
      await again.load();
      expect(again.byId(s.id)!.draft, 'Split the salaries line\nby team');

      await vm.send.execute('Split the salaries line by team');
      expect(sessions.byId(s.id)!.hasDraft, isFalse);
      expect(sidebar.lineOf(sessions.byId(s.id)!).text, isNot(startsWith('Draft')));
    },
  );
}
