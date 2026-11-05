import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/stash_repository.dart';
import 'package:helmy/data/services/engines/attachments.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// The list's extras from the video: drafts at the top, several chats at
/// once, one chat dragged into another, drafts put aside; and pictures as
/// files, and colors.
void main() {
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late SidebarViewModel list;

  Future<Session> thread(String title, {String? chatId}) async =>
      (await sessions.create(cwd: '/w', title: title, chatId: chatId) as Ok).value as Session;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('extras');
    final storage = storageAt(root);
    sessions = SessionRepositoryLocal(storage);
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
    list = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: FakeSettingsRepository(),
      chats: chats,
    );
  });
  tearDown(() async {
    list.dispose();
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  test('a new chat with words written and nothing sent is a draft, at the top', () async {
    await thread('Budget');
    final d = await thread('New chat');
    await sessions.save(d.copyWith(draft: 'Plan the trip to'));
    expect(list.groups.first.label, 'Drafts');
    expect(list.groups.first.sessions.single.id, d.id);
  });

  test('a new chat with nothing written or sent is not listed until it has something', () async {
    final budget = await thread('Budget');
    final blank = await thread('New chat');
    expect(list.shown.map((s) => s.id), [budget.id]);
    // Words written: a draft. A message sent: a chat.
    await sessions.save(blank.copyWith(draft: 'Plan'));
    expect(list.shown.map((s) => s.id), contains(blank.id));
    await sessions.save(blank.copyWith(draft: '', lastEngineId: 'claude'));
    expect(list.shown.map((s) => s.id), contains(blank.id));
  });

  test(
    'several chats picked are marked done, archived or deleted together, and undone together',
    () async {
      final a = await thread('Budget'), b = await thread('Trip'), c = await thread('Taxes');
      list.pick(a);
      list.pick(c, range: true);
      expect(list.pickedCount, 3, reason: 'a run, in the order the list shows them');
      list.pick(b);
      expect(list.pickedCount, 2, reason: 'picked again, it is let go');
      await list.archivePicked();
      expect([a, b, c].map((t) => sessions.byId(t.id)!.archived), [true, false, true]);
      expect(list.picking, isFalse);
      await list.undo();
      expect([a, b, c].map((t) => sessions.byId(t.id)!.archived), [false, false, false]);

      list.pick(a);
      list.pick(b);
      await list.markPickedDone();
      expect(list.settled, hasLength(2));
    },
  );

  test('a chat dragged into another joins it, and undo puts it back on its own', () async {
    final a = await thread('Budget');
    final b = await thread('Groceries');
    final target = sessions.byId(a.id)!.chatId!;
    await list.mergeInto(list.chatOf(b), target);
    expect(sessions.byId(b.id)!.chatId, target);
    expect(list.entriesOf(list.shown), hasLength(1));
    await list.undo();
    expect(sessions.byId(b.id)!.chatId, isNot(target));
    expect(list.entriesOf(list.shown), hasLength(2));
  });

  test('a draft put aside comes back, latest first, after a restart too', () async {
    final stash = StashRepository(storageAt(root));
    await stash.load();
    await stash.stash('First thought', const [], from: 'Budget');
    await stash.stash('Second, with a picture', const ['/tmp/a.png'], from: 'Trip');
    final again = StashRepository(storageAt(root));
    await again.load();
    final latest = await again.takeLatest();
    expect((latest?.text, latest?.from), ('Second, with a picture', 'Trip'));
    expect(latest?.attachments, ['/tmp/a.png']);
    expect(again.items.single.text, 'First thought');
  });

  test('pictures sent as pictures are named as files too, for the agent to use', () {
    final text = withFiles(
      'Add this to the PR',
      const ['/w/notes.md'],
      pictures: const ['/w/shot.png'],
    );
    expect(text, contains('- /w/notes.md'));
    expect(text, contains('also on disk'));
    expect(text, contains('- /w/shot.png'));
    expect(withFiles('Hi', const []), 'Hi');
  });

  test('colors: Helmy\'s own unless chosen, still pure black when dark with an accent', () {
    expect(themeFor(Brightness.dark), same(appDarkTheme));
    expect(themeFor(Brightness.light), same(appTheme));
    final accented = themeFor(Brightness.dark, accent: AccentChoice.blue);
    expect(accented.colors.background, const Color(0xFF000000));
    expect(accented.colors.primary, isNot(appDarkTheme.colors.primary));
    final stone = themeFor(Brightness.light, palette: Palette.stone);
    expect(stone.colors.muted, isNot(appTheme.colors.muted));
    expect(
      const AppSettings(palette: Palette.mist, accent: AccentChoice.rose).toJson(),
      containsPair('palette', 'mist'),
    );
    expect(AppSettings.fromJson({'palette': 'mist', 'accent': 'rose'}).accent, AccentChoice.rose);
  });
}
