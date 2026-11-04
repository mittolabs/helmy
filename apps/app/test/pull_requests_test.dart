import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/pull_requests.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/pull_requests/pull_requests_view_model.dart';
import 'package:helmy/utils/result.dart';

import '../testing/fake_repositories.dart';

PullRequest pr(
  int n,
  String title, {
  String author = 'ana',
  String branch = 'feature',
  List<String> labels = const [],
  bool draft = false,
  int updatedDaysAgo = 0,
  int createdDaysAgo = 0,
  String folder = '/w/site',
}) => PullRequest(
  repo: 'acme/site',
  folder: folder,
  number: n,
  title: title,
  author: author,
  branch: branch,
  updatedAt: DateTime(2026, 11, 4).subtract(Duration(days: updatedDaysAgo)),
  createdAt: DateTime(2026, 11, 4).subtract(Duration(days: createdDaysAgo)),
  url: 'https://github.com/acme/site/pull/$n',
  draft: draft,
  review: null,
  labels: labels,
  checks: null,
);

/// Pull requests as given, and their checks once the test lets them come.
class _Prs extends PullRequests {
  _Prs(this.prs) : super(CliLocator());
  final List<PullRequest> prs;
  final ready = Completer<void>();

  @override
  Future<PullRequestList> list(Iterable<String> folders) async =>
      (prs: prs, problem: null, me: 'me');

  @override
  Future<Map<int, ChecksState>> checks(String folder) async {
    await ready.future;
    return {for (final p in prs) p.number: .passing};
  }
}

void main() {
  test('the search reads words, numbers, and label:, author:, repo:, is:draft', () {
    final p = pr(12, 'Fix the login page', author: 'ana', labels: ['bug'], draft: true);
    expect(matchesQuery(p, ''), isTrue);
    expect(matchesQuery(p, 'login'), isTrue);
    expect(matchesQuery(p, 'LOGIN fix'), isTrue);
    expect(matchesQuery(p, 'signup'), isFalse);
    expect(matchesQuery(p, 'label:bug'), isTrue);
    expect(matchesQuery(p, 'label:feature'), isFalse);
    expect(matchesQuery(p, 'author:ana is:draft'), isTrue);
    expect(matchesQuery(p, '-is:draft'), isFalse);
    expect(matchesQuery(p, '#12'), isTrue);
    expect(matchesQuery(p, '12'), isTrue);
    expect(matchesQuery(p, 'repo:site'), isTrue);
  });

  test("checks read as one state: a failure first, then what's running", () {
    expect(PullRequest.checksOf([]), ChecksState.none);
    expect(
      PullRequest.checksOf([
        {'conclusion': 'SUCCESS', 'status': 'COMPLETED'},
      ]),
      ChecksState.passing,
    );
    expect(
      PullRequest.checksOf([
        {'conclusion': 'SUCCESS', 'status': 'COMPLETED'},
        {'conclusion': '', 'status': 'IN_PROGRESS'},
      ]),
      ChecksState.running,
    );
    expect(
      PullRequest.checksOf([
        {'status': 'IN_PROGRESS'},
        {'conclusion': 'FAILURE', 'status': 'COMPLETED'},
      ]),
      ChecksState.failing,
    );
    // A commit status, as GitHub gives those.
    expect(
      PullRequest.checksOf([
        {'state': 'SUCCESS'},
      ]),
      ChecksState.passing,
    );
  });

  test(
    'listed, sorted and narrowed; checks unknown until read; a session found and started',
    () async {
      final root = await Directory.systemTemp.createTemp('prs');
      addTearDown(() => root.delete(recursive: true));
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
      final made = (await sessions.create(cwd: '/w/copy') as Ok).value as Session;
      await sessions.save(made.copyWith(repo: '/w/site', branch: 'helmy/footer-1a2b'));
      final prs = _Prs([
        pr(1, 'Old but busy', updatedDaysAgo: 0, createdDaysAgo: 30),
        pr(
          2,
          'New',
          updatedDaysAgo: 2,
          createdDaysAgo: 2,
          author: 'me',
          branch: 'helmy/footer-1a2b',
        ),
        pr(3, 'Middle', updatedDaysAgo: 1, createdDaysAgo: 10),
      ]);
      final vm = PullRequestsViewModel(
        prs: prs,
        sessions: sessions,
        conversations: repo,
        settings: FakeSettingsRepository(),
      );
      addTearDown(vm.dispose);
      expect(vm.folders, ['/w/site']);
      final loading = vm.load();
      // The list, once read (not a tick: a cold run is slower than a warm one).
      for (var i = 0; i < 100 && vm.all == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(vm.all, isNotNull);
      expect(vm.all!.every((p) => p.checks == null), isTrue, reason: 'unknown until read');
      prs.ready.complete();
      await loading;
      expect(vm.all!.every((p) => p.checks == ChecksState.passing), isTrue);

      expect([for (final p in vm.shown) p.number], [1, 3, 2]);
      vm.sortBy(.newest);
      expect([for (final p in vm.shown) p.number], [2, 3, 1]);
      vm.sortBy(.oldest);
      expect([for (final p in vm.shown) p.number], [1, 3, 2]);
      vm.showMine(true);
      expect([for (final p in vm.shown) p.number], [2]);
      vm.showMine(false);
      vm.search('mid');
      expect([for (final p in vm.shown) p.number], [3]);

      expect(vm.sessionOf(vm.all!.firstWhere((p) => p.number == 2))?.id, made.id);
      expect(vm.sessionOf(vm.all!.firstWhere((p) => p.number == 1)), isNull);

      final id = await vm.review(vm.all!.firstWhere((p) => p.number == 3));
      final review = sessions.byId(id!)!;
      expect((review.cwd, review.title), ('/w/site', 'Review #3: Middle'));
    },
  );
}
