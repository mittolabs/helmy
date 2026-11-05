import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/ship_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/notify_service.dart';
import 'package:helmy/data/services/shipping.dart';
import 'package:helmy/domain/models/chat.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/shell/view_models/sidebar_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';
import 'support/storage.dart';

/// A branch whose pull request is in whatever state the test puts it.
class _Shipping extends Shipping {
  _Shipping() : super(CliLocator());
  String prState = 'OPEN';

  @override
  Future<BranchState?> state(String cwd) async => BranchState(
    branch: 'helmy/budget',
    uncommitted: 0,
    unpushed: 0,
    pushed: true,
    head: 'abc',
    pr: (
      number: 3,
      url: 'https://github.com/x/y/pull/3',
      title: 'Budget',
      state: prState,
      checks: const [],
    ),
  );
}

/// The list as an inbox: a chat settles, out of the way, until something new.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SessionRepositoryLocal sessions;
  late ChatRepository chats;
  late ConversationRepositoryEngines repo;
  late FakeSettingsRepository settings;
  late SidebarViewModel list;

  Future<Session> thread(String title, {String? chatId, Duration ago = Duration.zero}) async {
    final s =
        (await sessions.create(cwd: '/w', title: title, chatId: chatId) as Ok).value as Session;
    final at = DateTime.now().subtract(ago).toIso8601String();
    await sessions.save(Session.fromJson({...s.toJson(), 'updatedAt': at, 'createdAt': at}));
    return sessions.byId(s.id)!;
  }

  Chat chatOf(Session s) => chats.byId(sessions.byId(s.id)!.chatId!)!;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('settle');
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
    settings = FakeSettingsRepository();
    list = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: settings,
      chats: chats,
    );
  });
  tearDown(() async {
    list.dispose();
    repo.dispose();
    chats.dispose();
    await deleteFolder(root);
  });

  test('a settled chat leaves the list for Settled, and ⌘Z brings it back', () async {
    final a = await thread('Food budget');
    await thread('Launch email');
    await list.settleChat(list.chatOf(a));
    expect(chatOf(a).settled, isTrue);
    expect([for (final e in list.settled) e.threads.first.id], [a.id]);
    expect(list.inOrder.map((s) => s.title), ['Launch email'], reason: 'only what is active');
    await list.undo();
    expect(chatOf(a).settled, isFalse);
    expect(list.settled, isEmpty);
  });

  test('settled is kept: read again, it is still settled', () async {
    final a = await thread('Food budget');
    await list.settleChat(list.chatOf(a));
    final again = ChatRepository(storageAt(root), sessions);
    await again.load();
    expect(again.byId(sessions.byId(a.id)!.chatId!)!.settled, isTrue);
    again.dispose();
  });

  test('a thread filed into a settled chat brings it back', () async {
    final a = await thread('Food budget');
    await list.settleChat(list.chatOf(a));
    final b = await thread('Groceries');
    await chats.move(b, chatOf(a).id);
    expect(chatOf(a).settled, isFalse);
  });

  test('a chat untouched for three days settles by itself, unless pinned or told not to', () async {
    final old = await thread('Old trip', ago: const Duration(days: 4));
    final pinned = await thread('Taxes', ago: const Duration(days: 5));
    await sessions.save(pinned.copyWith(pinned: true));
    final recent = await thread('This week', ago: const Duration(days: 1));

    settings = FakeSettingsRepository(const AppSettings(settleOnItsOwn: false));
    final off = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: settings,
      chats: chats,
    );
    await off.settleIdle();
    expect(chatOf(old).settled, isFalse, reason: 'the setting is off');
    off.dispose();

    await list.settleIdle();
    expect(chatOf(old).settled, isTrue);
    expect(chatOf(pinned).settled, isFalse, reason: 'pinned stays in view');
    expect(chatOf(recent).settled, isFalse);

    // Brought back by hand, it counts as touched: not settled again at once.
    await list.unsettleChat(list.chatOf(old));
    await list.settleIdle();
    expect(chatOf(old).settled, isFalse);
    await list.settleIdle(now: DateTime.now().add(const Duration(days: 4)));
    expect(chatOf(old).settled, isTrue, reason: 'three days after that, it settles again');
  });

  test('a pull request seen open and then merged settles its chat', () async {
    final shipping = _Shipping();
    final ship = ShipRepositoryGit(
      shipping: shipping,
      sessions: sessions,
      conversations: repo,
      notify: NotifyService(),
    );
    final merging = SidebarViewModel(
      sessions: sessions,
      conversations: repo,
      settings: FakeSettingsRepository(),
      chats: chats,
      ship: ship,
    );
    final a = await thread('Budget page');
    final merged = <String>[];
    final sub = ship.merged.listen(merged.add);
    await ship.refresh(a);
    expect(merged, isEmpty, reason: 'open, not merged');
    shipping.prState = 'MERGED';
    await ship.refresh(a);
    await Future<void>.delayed(Duration.zero);
    expect(merged, [a.id]);
    expect(chatOf(a).settled, isTrue);

    // Merged when first seen (merged long ago): nothing to tell.
    final b = await thread('Old page');
    await ship.refresh(b);
    await Future<void>.delayed(Duration.zero);
    expect(merged, [a.id]);
    await sub.cancel();
    merging.dispose();
    ship.dispose();
  });
}
