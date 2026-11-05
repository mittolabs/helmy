import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/ship_repository.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/notify_service.dart';
import 'package:helmy/data/services/shipping.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/utils/result.dart';

/// A branch whose pull request's checks are what the test says.
class _Shipping extends Shipping {
  _Shipping() : super(CliLocator());
  String head = 'abc';
  List<Check> checks = const [];

  @override
  Future<BranchState?> state(String cwd) async => BranchState(
    branch: 'helmy/dark-mode',
    uncommitted: 0,
    unpushed: 0,
    pushed: true,
    head: head,
    pr: (
      number: 7,
      url: 'https://github.com/x/y/pull/7',
      title: 'Dark mode',
      state: 'OPEN',
      checks: checks,
    ),
  );

  @override
  Future<String?> failureLog(String cwd, String branch, {int lines = 120}) async =>
      'test/widget_test.dart: Expected: 2 Actual: 3';
}

/// What a session was sent, rather than sending it.
class _Conversations extends ConversationRepositoryEngines {
  _Conversations(StorageService storage, SessionRepositoryLocal sessions)
    : super(
        engines: EngineRegistry([]),
        router: HeadroomRouter(UsageMeter()),
        meter: UsageMeter(),
        storage: storage,
        sessions: sessions,
      );
  final sent = <String>[];

  @override
  Future<Result<void>> send(
    Session session,
    String text, {
    List<String> attachments = const [],
    Set<Capability> needs = const {},
    String? from,
  }) async {
    sent.add(text);
    return const .ok(null);
  }
}

class _Notes extends NotifyService {
  final said = <String>[];
  @override
  Future<void> notify({
    required String sessionId,
    required String title,
    required String body,
    bool thumbsUp = false,
    bool banner = true,
    bool sound = true,
  }) async => said.add(body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test("GitHub's check states read as passed, failed, pending or skipped", () {
    expect(
      Shipping.checkState({'status': 'COMPLETED', 'conclusion': 'SUCCESS'}),
      CheckState.passed,
    );
    expect(
      Shipping.checkState({'status': 'COMPLETED', 'conclusion': 'FAILURE'}),
      CheckState.failed,
    );
    expect(
      Shipping.checkState({'status': 'COMPLETED', 'conclusion': 'TIMED_OUT'}),
      CheckState.failed,
    );
    expect(
      Shipping.checkState({'status': 'COMPLETED', 'conclusion': 'SKIPPED'}),
      CheckState.skipped,
    );
    expect(Shipping.checkState({'status': 'IN_PROGRESS'}), CheckState.pending);
    expect(Shipping.checkState({'state': 'PENDING'}), CheckState.pending);
    expect(Shipping.checkState({'state': 'ERROR'}), CheckState.failed);
  });

  test('a branch never pushed: what is not committed, and not pushed yet', () async {
    final root = await Directory.systemTemp.createTemp('ship');
    Future<void> git(List<String> a) => Process.run('git', a, workingDirectory: root.path);
    await git(['init', '-q', '-b', 'main']);
    await File('${root.path}/a.txt').writeAsString('a');
    await git(['add', '.']);
    await git(['-c', 'user.name=T', '-c', 'user.email=t@helmy.test', 'commit', '-qm', 'one']);
    await File('${root.path}/b.txt').writeAsString('b');
    final s = (await Shipping(CliLocator()).state(root.path))!;
    expect(s.branch, 'main');
    expect(s.uncommitted, 1);
    expect(s.pushed, isFalse);
    expect(s.unpushed, 1, reason: 'its one commit is on no remote');
    expect(s.pr, isNull);
    await root.delete(recursive: true);
  });

  test('watched checks: a failure goes to the agent once per commit, a pass to the user', () async {
    final root = await Directory.systemTemp.createTemp('watch');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final conversations = _Conversations(storage, sessions);
    final shipping = _Shipping();
    final notes = _Notes();
    final ship = ShipRepositoryGit(
      shipping: shipping,
      sessions: sessions,
      conversations: conversations,
      notify: notes,
    );
    final s = (await sessions.create(cwd: root.path) as Ok).value as Session;

    // Still running: nothing told.
    shipping.checks = [(name: 'test', state: CheckState.pending)];
    await ship.check(s);
    expect(conversations.sent, isEmpty);

    // Failed: the agent hears what failed, and what it printed.
    shipping.checks = [
      (name: 'test', state: CheckState.failed),
      (name: 'lint', state: CheckState.passed),
    ];
    await ship.check(s);
    expect(conversations.sent.single, contains('#7 failed: test'));
    expect(conversations.sent.single, contains('Expected: 2 Actual: 3'));

    // Looked at again, the same commit: not told twice.
    await ship.check(s);
    expect(conversations.sent, hasLength(1));

    // The fix pushed, and passing: the user hears.
    shipping
      ..head = 'def'
      ..checks = [(name: 'test', state: CheckState.passed)];
    await ship.check(s);
    expect(notes.said, ['Checks passed on #7']);
    expect(conversations.sent, hasLength(1));
    ship.dispose();
    conversations.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
