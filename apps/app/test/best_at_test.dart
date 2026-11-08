import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/needs.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/domain/models/work.dart';

/// Each kind of work goes first to the connection best at it, Mittolabs's
/// choice until the user makes their own; room still decides among them.
void main() {
  WorkKind? kind(String m) => kindOf(m, needsOf(m));

  test('messages are told apart by kind', () {
    expect(kind('Fix the failing unit tests in auth_service.dart'), WorkKind.code);
    expect(kind('Why does this throw an exception?\n```\nnull\n```'), WorkKind.code);
    expect(kind('Draft an email to the landlord about the leak'), WorkKind.writing);
    expect(kind('Research the best standing desks and compare them'), WorkKind.research);
    expect(kind('Draw a cat in manga style'), WorkKind.pictures);
    expect(kind("What's on my calendar tomorrow?"), WorkKind.accounts);
    expect(kind('How many ounces in a cup?'), WorkKind.quick);
    expect(kind('Plan the trip to the coast next month with the family'), isNull);
  });

  const claude = EngineInfo(id: 'claude', name: 'Claude Code', capabilities: {Capability.tools});
  const work = EngineInfo(
    id: 'claude-work',
    name: 'Claude Code (Work)',
    capabilities: {Capability.tools},
  );
  const codex = EngineInfo(
    id: 'codex',
    name: 'Codex',
    capabilities: {Capability.tools, Capability.imageGeneration},
  );
  const stranger = EngineInfo(id: 'opencode', name: 'OpenCode', assignedOnly: true);

  test('the best kind of connection first, the roomiest account of it', () {
    final meter = UsageMeter()
      ..report('claude', const Usage(used: .7))
      ..report('claude-work', const Usage(used: .2))
      ..report('codex', const Usage(used: .1));
    final router = HeadroomRouter(meter);
    final all = [claude, work, codex];
    expect(router.choose(candidates: all, current: null, kind: WorkKind.code), 'claude-work');
    // Any, by room.
    expect(router.choose(candidates: all, current: null, kind: WorkKind.quick), 'codex');
    // The user's own choice.
    final mine = HeadroomRouter(meter, bestAt: (k) => k == WorkKind.code ? 'codex' : null);
    expect(mine.choose(candidates: all, current: 'claude', kind: WorkKind.code), 'codex');
  });

  test('when the best kind is out of room, the others take it', () {
    final meter = UsageMeter()
      ..report('claude', const Usage(used: .99))
      ..report('codex', const Usage(used: .3));
    expect(
      HeadroomRouter(meter).choose(candidates: [claude, codex], current: null, kind: WorkKind.code),
      'codex',
    );
  });

  test('a connection that says nothing of itself answers only what it is set best at', () {
    final meter = UsageMeter()..report('claude', const Usage(used: .9));
    final router = HeadroomRouter(meter, bestAt: (k) => k == WorkKind.quick ? 'opencode' : null);
    expect(router.choose(candidates: [claude, stranger], current: null), 'claude');
    expect(
      router.choose(candidates: [claude, stranger], current: null, kind: WorkKind.code),
      'claude',
    );
    expect(
      router.choose(candidates: [claude, stranger], current: null, kind: WorkKind.quick),
      'opencode',
    );
    // Alone (the others turned off), it answers everything.
    expect(router.choose(candidates: [stranger], current: null), 'opencode');
    expect(router.choose(candidates: [stranger], current: null, kind: WorkKind.code), 'opencode');
  });

  test("the user's choices are kept; Mittolabs's stand for the rest", () {
    const s = AppSettings(bestAt: {'pictures': 'claude', 'code': 'any'});
    expect(s.bestFor(WorkKind.pictures), 'claude');
    expect(s.bestFor(WorkKind.code), isNull);
    expect(s.bestFor(WorkKind.writing), 'claude');
    expect(AppSettings.fromJson(s.toJson()).bestAt, s.bestAt);
    expect(changedSettings(s), contains('Best at'));
    expect(withDefaults(s).bestAt, isEmpty);
  });
}
