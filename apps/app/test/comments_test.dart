import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

void main() {
  test('comments go ahead of the message, each part quoted with what was said', () {
    final text = ChatViewModel.commentsText([
      (id: 0, quote: 'Salaries rose 12.5%', note: 'Split this by team'),
      (id: 1, quote: 'Travel was flat.\nSoftware fell.', note: ''),
    ]);
    expect(
      text,
      'About these parts of the conversation:\n'
      '\n'
      '> Salaries rose 12.5%\n'
      'Split this by team\n'
      '\n'
      '> Travel was flat.\n'
      '> Software fell.\n'
      '(no comment written: look at this part)',
    );
    final long = ChatViewModel.commentsText([(id: 0, quote: 'a' * 700, note: 'Shorter')]);
    expect(long, contains('${'a' * 600}…'));
  });

  test('a comment waits with the message, keeps its words, and can be taken back', () async {
    final root = await Directory.systemTemp.createTemp('comments');
    final storage = storageAt(root);
    addTearDown(() async {
      await storage.flush();
      await root.delete(recursive: true);
    });
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
    final vm = ChatViewModel(sessionId: created.id, sessions: sessions, conversations: repo);
    expect(vm.hasExtras, isFalse);
    vm.comment('   ');
    expect(vm.comments, isEmpty, reason: 'nothing chosen, nothing to comment on');
    vm.comment(' Salaries rose ');
    vm.comment('Travel was flat.');
    vm.noteComment(0, 'Split this by team');
    expect(vm.hasExtras, isTrue);
    vm.dropComment(1);
    expect(vm.comments.single.quote, 'Salaries rose');
    expect(vm.comments.single.note, 'Split this by team');
  });
}
