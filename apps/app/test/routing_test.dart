import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/handoff.dart';
import 'package:helmy/data/services/engines/needs.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';

List<EngineInfo> e(List<String> ids, {Map<String, Set<Capability>> can = const {}}) => [
  for (final id in ids) EngineInfo(id: id, name: id, capabilities: can[id] ?? const {}),
];

void main() {
  usageFreshness();
  group('capabilities', () {
    final meter = UsageMeter();
    final router = HeadroomRouter(meter);
    const image = {Capability.imageGeneration};

    test('a message that needs something goes to an engine that has it', () {
      meter
        ..report('claude', const Usage(used: .1))
        ..report('codex', const Usage(used: .9));
      final engines = e(['claude', 'codex'], can: {'codex': image});
      expect(router.choose(candidates: engines, current: 'claude', needs: image), 'codex');
      expect(router.choose(candidates: engines, current: 'claude'), 'claude');
    });

    test('when nobody has it, any engine still answers', () {
      expect(router.choose(candidates: e(['claude']), current: 'claude', needs: image), 'claude');
    });
  });

  group('connected services', () {
    test('asked for the way people ask for theirs', () {
      expect(needsOf('find the budget sheet in my Drive'), {Capability.googleDrive});
      expect(needsOf('what is on my calendar tomorrow?'), {Capability.googleCalendar});
      expect(needsOf('summarise my unread emails'), {Capability.gmail});
      expect(needsOf('add an email validator to the signup form'), isEmpty);
      expect(needsOf('build a calendar widget'), isEmpty);
      expect(needsOf('fix the drive train simulation'), isEmpty);
    });

    test('a message that needs Drive goes to the account connected to it', () {
      final router = HeadroomRouter(UsageMeter());
      final engines = e(
        ['claude', 'claude-work'],
        can: {
          'claude-work': {Capability.googleDrive},
        },
      );
      expect(
        router.choose(candidates: engines, current: 'claude', needs: {Capability.googleDrive}),
        'claude-work',
      );
    });
  });

  group('needsOf', () {
    for (final yes in [
      'generate an image of a japanese manga cat calling out to "Mitto" comic style',
      'Can you make me a logo for the app?',
      'draw a cat',
      'create a poster for the launch',
      'Please create a simple illustration of a lighthouse',
    ]) {
      test('needs a picture: $yes', () => expect(needsOf(yes), {Capability.imageGeneration}));
    }
    for (final no in [
      'why does this image not load on the home screen?',
      'resize the images in assets to 512px',
      'add an Image widget to the profile page',
      'list the files here',
      'make the logo bigger in the header',
    ]) {
      test('needs nothing: $no', () => expect(needsOf(no), isEmpty));
    }
  });

  group('HeadroomRouter', () {
    late UsageMeter meter;
    late HeadroomRouter router;
    setUp(() {
      meter = UsageMeter();
      router = HeadroomRouter(meter);
    });

    test('a new session goes where there is most room', () {
      meter
        ..report('a', const Usage(used: .6))
        ..report('b', const Usage(used: .2));
      expect(router.choose(candidates: e(['a', 'b']), current: null), 'b');
    });

    test('stays put unless another has clearly more room', () {
      meter
        ..report('a', const Usage(used: .30))
        ..report('b', const Usage(used: .20));
      expect(router.choose(candidates: e(['a', 'b']), current: 'a'), 'a');
      meter.report('b', const Usage(used: .10));
      expect(router.choose(candidates: e(['a', 'b']), current: 'a'), 'b');
    });

    test('leaves an engine that is nearly out', () {
      meter
        ..report('a', const Usage(used: .96))
        ..report('b', const Usage(used: .90));
      expect(router.choose(candidates: e(['a', 'b']), current: 'a'), 'b');
    });

    test('unknown usage is not taken as empty', () {
      meter.report('a', const Usage(used: .3));
      expect(router.choose(candidates: e(['a', 'b']), current: null), 'a');
      expect(router.choose(candidates: e(['b', 'a']), current: 'b'), 'b');
    });

    test('nothing to choose from is null', () {
      expect(router.choose(candidates: e([]), current: 'a'), isNull);
    });
  });

  test('a failed engine stays out until its limit resets', () {
    final meter = UsageMeter();
    final now = DateTime(2026, 11, 3, 12);
    meter.markDown('a', until: now.add(const Duration(hours: 1)), now: now);
    expect(meter.isDown('a', now: now), isTrue);
    expect(meter.isDown('a', now: now.add(const Duration(hours: 2))), isFalse);
    meter.markDown('b', now: now);
    expect(meter.isDown('b', now: now.add(const Duration(minutes: 10))), isTrue);
  });

  test('handoff is what was asked, the reply and the files changed', () {
    expect(handoff([]), isEmpty);
    final text = handoff([
      UserMessage('Make hello.txt'),
      AssistantText('a', 'Making it.'),
      ToolCall(id: 't', name: 'Write', input: {'file_path': '/w/hello.txt'})..result = 'ok',
      ToolCall(id: 's', name: 'Bash', input: {'command': 'ls'})..result = 'a\nb\nc',
      AssistantText('b', 'Done.'),
      TurnSummary(ok: true),
    ]);
    expect(text, contains('User: Make hello.txt'));
    expect(text, contains('Assistant: Done.'));
    expect(text, isNot(contains('Making it.')));
    expect(text, contains('Changed: /w/hello.txt'));
    expect(text, contains('Ran 1 command'));
    // Tool output stays out.
    expect(text, isNot(contains('a\nb')));
  });

  test('a long handoff keeps the newest turns and says how many it left out', () {
    final items = [
      for (var i = 0; i < 30; i++) ...[
        UserMessage('question $i ${'x' * 200}'),
        AssistantText('$i', 'answer $i'),
      ],
    ];
    final text = handoff(items, maxChars: 1000);
    expect(text, contains('question 29'));
    expect(text, isNot(contains('question 0 ')));
    expect(text, contains('earlier turns left out'));
    expect(text.length, lessThan(1400));
  });

  test('Claude Code accounts are found from ~/.claude-* folders', () {
    final home = Directory.systemTemp.createTempSync('helmy-home');
    Directory('${home.path}/.claude').createSync();
    Directory('${home.path}/.claude-work').createSync();
    File('${home.path}/.claude-notes.json').createSync();
    Directory('${home.path}/.claude-bad name').createSync();
    final ids = ClaudeEngine.discover(CliLocator(), home.path).map((e) => e.info.id);
    expect(ids, ['claude', 'claude-work']);
    expect(
      ClaudeEngine.discover(CliLocator(), home.path).last.configDir,
      '${home.path}/.claude-work',
    );
    home.deleteSync(recursive: true);
  });
}

void usageFreshness() {
  test('a reading with the same number still counts as fresh', () {
    final meter = UsageMeter();
    final t0 = DateTime(2026, 11, 3, 17);
    meter.report('a', const Usage(used: .06), now: t0);
    meter.report('a', const Usage(used: .06), now: t0.add(const Duration(minutes: 50)));
    expect(meter.usageOf('a')!.reportedAt, t0.add(const Duration(minutes: 50)));
  });

  group('threads rarely move (decision 0014)', () {
    late UsageMeter meter;
    late HeadroomRouter router;
    final now = DateTime(2026, 11, 4, 12);
    List<EngineInfo> e(List<String> ids) => [for (final id in ids) EngineInfo(id: id, name: id)];
    setUp(() {
      meter = UsageMeter();
      router = HeadroomRouter(meter, now: () => now);
    });

    test('a warm thread stays, though another has much more room', () {
      meter
        ..report('claude', const Usage(used: .60))
        ..report('codex', const Usage(used: .05));
      expect(
        router.choose(candidates: e(['claude', 'codex']), current: 'claude', warm: true),
        'claude',
      );
      expect(
        router.choose(candidates: e(['claude', 'codex']), current: 'claude'),
        'codex',
        reason: 'cold: it may',
      );
    });

    test('a forced move keeps the same kind of engine where one has room', () {
      meter
        ..report('claude', const Usage(used: .97))
        ..report('claude-work', const Usage(used: .50))
        ..report('codex', const Usage(used: .10));
      expect(
        router.choose(
          candidates: e(['claude', 'claude-work', 'codex']),
          current: 'claude',
          warm: true,
        ),
        'claude-work',
      );
    });

    test('a new thread does not start where it would soon have to move from', () {
      meter
        ..report('a', Usage(used: .85, resetsAt: now.add(const Duration(hours: 4))))
        ..report('b', const Usage(used: .86));
      // Both are close to their limit; only b's is unknown and a's far off: neither is
      // open, so the roomiest of all is taken rather than nothing.
      expect(router.choose(candidates: e(['a', 'b']), current: null), 'a');
      meter.report('c', Usage(used: .90, resetsAt: now.add(const Duration(minutes: 20))));
      expect(
        router.choose(candidates: e(['a', 'b', 'c']), current: null),
        'c',
        reason: 'fullest, but its reset is minutes off: it will have room',
      );
    });
  });

  test("a hand-off starts with the thread's summary, then its latest turns", () {
    final h = handoff([
      UserMessage('Set the budget'),
      AssistantText('a:0', 'Set at 2,000.'),
    ], summary: 'November budget, set');
    expect(h, contains('In short, so far: November budget, set'));
    expect(h.indexOf('In short'), lessThan(h.indexOf('Set the budget')));
    expect(handoff([UserMessage('x')]), isNot(contains('In short')));
  });
}
