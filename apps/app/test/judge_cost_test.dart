import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/approvals.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';

/// A connection that judges with [reply], counting each time it is asked.
class _Judge implements AgentEngine {
  _Judge(String id, this.reply, {this.model, this.tokens, bool local = false})
    : info = EngineInfo(id: id, name: id, localOnly: local, capabilities: const {Capability.tools});

  @override
  final EngineInfo info;
  final String? reply;
  final String? model;
  final TurnTokens? tokens;
  var asked = 0;

  @override
  Future<Answer?> ask(String instructions, String question) async {
    asked++;
    final r = reply;
    return r == null ? null : Answer(text: r, model: model, tokens: tokens);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Codex's models as `model/list` gave them on an account, 2026-11-14.
const _codexModels = [
  ModelChoice(
    id: 'gpt-6.1-sol',
    name: 'GPT-6.1-Sol',
    description: 'Latest workhorse model for coding and everyday work.',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
  ),
  ModelChoice(
    id: 'gpt-6-astra',
    name: 'GPT-6-Astra',
    description: 'Frontier intelligence for the most demanding work.',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max', 'ultra'],
  ),
  ModelChoice(
    id: 'gpt-6-sol',
    name: 'GPT-6-Sol',
    description: 'Previous generation workhorse model.',
  ),
  ModelChoice(
    id: 'gpt-6-luna',
    name: 'GPT-6-Luna',
    description: 'Fast and affordable model for easier tasks.',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
  ),
  ModelChoice(
    id: 'gpt-5.6-luna',
    name: 'GPT-5.6-Luna',
    description: 'Older fast and efficient model.',
    efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
  ),
];

final _push = PermissionPrompt(
  requestId: 'r1',
  toolName: 'Bash',
  input: const {'command': 'npm install'},
  suggestions: const [],
);

const _allow = '{"verdict": "allow", "why": "Installs what the project declares."}';

void main() {
  group('the model a short question is asked of', () {
    test("is the account's newest small one, from what it lists", () {
      expect(smallestModel(_codexModels)?.id, 'gpt-6-luna');
    });

    test('is one named small, mini or the like', () {
      expect(
        smallestModel(const [
          ModelChoice(id: 'gpt-5.1-codex', name: 'GPT-5.1 Codex'),
          ModelChoice(id: 'gpt-5.1-codex-mini', name: 'GPT-5.1 Codex Mini'),
        ])?.id,
        'gpt-5.1-codex-mini',
      );
    });

    test('is one the connection does not call old, while there is one', () {
      expect(
        smallestModel(const [
          ModelChoice(id: 'a', name: 'A', description: 'Older fast and efficient model.'),
          ModelChoice(id: 'b', name: 'B', description: 'Cheap and quick.'),
        ])?.id,
        'b',
      );
    });

    test('is none (the default) when nothing says it is small', () {
      expect(smallestModel(_codexModels.take(3).toList()), isNull);
      expect(smallestModel(const []), isNull);
    });

    test('runs at the least effort it lists', () {
      expect(leastEffort(_codexModels[3]), 'low');
      expect(
        leastEffort(const ModelChoice(id: 'm', name: 'm', efforts: ['high', 'minimal', 'low'])),
        'minimal',
      );
      expect(leastEffort(const ModelChoice(id: 'm', name: 'm', efforts: ['fast', 'deep'])), 'fast');
      expect(leastEffort(const ModelChoice(id: 'm', name: 'm')), isNull);
      expect(leastEffort(null), isNull);
    });
  });

  group('Claude Code, asked one question', () {
    test('runs its small model, at the least effort, with only the instructions', () {
      final args = ClaudeEngine.askArgs('Judge this.', 'The action', effort: 'low');
      expect(args.sublist(0, 2), ['-p', 'The action']);
      expect(args[args.indexOf('--model') + 1], 'haiku');
      expect(args[args.indexOf('--effort') + 1], 'low');
      expect(args[args.indexOf('--system-prompt') + 1], 'Judge this.');
      expect(args[args.indexOf('--tools') + 1], '');
      expect(args, containsAll(['--strict-mcp-config', '--disable-slash-commands']));
      expect(ClaudeEngine.askArgs('i', 'q'), isNot(contains('--effort')));
    });

    test('reports the model it used and its tokens', () {
      final a = ClaudeEngine.answerOf(
        jsonEncode({
          'is_error': false,
          'result': ' {"verdict": "allow"} ',
          'usage': {
            'input_tokens': 690,
            'cache_read_input_tokens': 0,
            'cache_creation_input_tokens': 12,
            'output_tokens': 31,
          },
          'modelUsage': {'claude-haiku-5': <String, Object?>{}},
        }),
      )!;
      expect(a.text, '{"verdict": "allow"}');
      expect(a.model, 'claude-haiku-5');
      expect(a.tokens?.toJson(), {'fresh': 690, 'cacheRead': 0, 'cacheWrite': 12, 'output': 31});
    });

    test('reports no tokens it was not told, and no answer for an error', () {
      final a = ClaudeEngine.answerOf(jsonEncode({'result': 'yes'}))!;
      expect(a.model, 'haiku', reason: 'the model asked for, when it does not say');
      expect(a.tokens, isNull);
      expect(ClaudeEngine.answerOf(jsonEncode({'is_error': true, 'result': 'x'})), isNull);
      expect(ClaudeEngine.answerOf('not json'), isNull);
    });
  });

  group('Codex, asked one question', () {
    List<String> lean({String? model = 'gpt-6-luna', bool local = false}) => CodexEngine.askArgs(
      instructions: 'Judge this.',
      question: 'The action',
      out: '/tmp/a/answer.txt',
      instructionsFile: '/tmp/a/instructions.md',
      model: model,
      effort: local ? null : 'low',
      local: local,
    );

    test('runs the small model, at the least effort, on Helmy\'s instructions alone', () {
      final args = lean();
      expect(args.last, 'The action', reason: 'the instructions go in the file');
      expect(args, isNot(contains(contains('Judge this.'))));
      expect(args[args.indexOf('-m') + 1], 'gpt-6-luna');
      expect(args, containsAllInOrder(['-c', 'model_reasoning_effort="low"']));
      expect(args, contains('model_instructions_file="/tmp/a/instructions.md"'));
      expect(args, containsAll(['--ignore-user-config', '--ignore-rules', '--json']));
      expect(args, containsAll(['include_environment_context=false', 'web_search="disabled"']));
      expect(args, containsAll(['features.shell_tool=false', 'features.apps=false']));
    });

    test('leaves the model to Codex when the account lists no small one', () {
      expect(lean(model: null), isNot(contains('-m')));
    });

    test('on the local model, asks Ollama for it', () {
      final args = lean(model: 'gpt-oss:20b', local: true);
      expect(args, containsAllInOrder(['-c', 'model_provider="ollama"', '-m', 'gpt-oss:20b']));
      expect(args.where((a) => a == '-m'), hasLength(1));
    });

    test('asked plainly, is the call it always was', () {
      final args = CodexEngine.askArgs(
        instructions: 'Judge this.',
        question: 'The action',
        out: '/tmp/a/answer.txt',
        instructionsFile: '/tmp/a/instructions.md',
        lean: false,
      );
      expect(args, [
        'exec',
        '--ephemeral',
        '--skip-git-repo-check',
        '-s',
        'read-only',
        '-o',
        '/tmp/a/answer.txt',
        'Judge this.\n\nThe action',
      ]);
    });

    test('reports its tokens from the turn it completed', () {
      final out = [
        '{"type":"thread.started","thread_id":"t"}',
        '{"type":"turn.started"}',
        '{"type":"turn.completed","usage":{"input_tokens":2400,"cached_input_tokens":1800,'
            '"output_tokens":40}}',
      ].join('\n');
      expect(CodexEngine.tokensOf(out)?.toJson(), {
        'fresh': 600,
        'cacheRead': 1800,
        'cacheWrite': null,
        'output': 40,
      });
      expect(CodexEngine.tokensOf('{"type":"turn.started"}'), isNull);
    });

    test('is asked plainly only when the lean call was refused for how it asked', () {
      const limit =
          '{"type":"turn.started"}\n'
          '{"type":"turn.failed","error":{"message":"You\'ve hit your usage limit."}}';
      const model =
          '{"type":"turn.started"}\n'
          '{"type":"turn.failed","error":{"message":"The model gpt-6-luna is not supported."}}';
      expect(CodexEngine.leanRefused('', 2), isTrue, reason: 'a flag refused before any turn');
      expect(CodexEngine.leanRefused(model, 1), isTrue);
      expect(CodexEngine.leanRefused(limit, 1), isFalse);
      expect(CodexEngine.leanRefused('', 0), isFalse);
    });
  });

  group('the judge', () {
    late Directory root;
    late TurnLog log;
    late UsageMeter meter;

    setUp(() {
      root = Directory.systemTemp.createTempSync('helmy-judge');
      log = TurnLog(appData: () async => root, now: () => DateTime.utc(2026, 11, 14));
      meter = UsageMeter()
        // Codex has more room, so the router would send it work first.
        ..report('codex', const Usage(used: .1))
        ..report('claude', const Usage(used: .6));
    });
    tearDown(() => root.deleteSync(recursive: true));

    Approvals approvals(List<AgentEngine> engines, {Set<String>? enabled}) => Approvals(
      EngineRegistry(engines),
      HeadroomRouter(meter),
      (id) => enabled?.contains(id) ?? true,
      meter: meter,
      log: log,
    );

    test('asks Claude Code first, its cheapest, though another has more room', () async {
      final codex = _Judge('codex', _allow);
      final claude = _Judge('claude', _allow);
      final j = await approvals([codex, claude]).judge(_push, asked: ['Set it up'], folder: '/p');
      expect(j.verdict, Verdict.allow);
      expect((claude.asked, codex.asked), (1, 0));
    });

    test('asks another Claude Code account before Codex', () async {
      final a = approvals([_Judge('codex', _allow), _Judge('claude-work', _allow)]);
      expect([for (final e in a.judges()) e.info.id], ['claude-work', 'codex']);
    });

    test('asks the others first while Claude Code is at its limit, and it last', () async {
      meter.markDown('claude');
      final codex = _Judge('codex', _allow);
      final claude = _Judge('claude', _allow);
      final a = approvals([codex, claude]);
      expect([for (final e in a.judges()) e.info.id], ['codex', 'claude']);
      await a.judge(_push, asked: ['Set it up'], folder: '/p');
      expect((claude.asked, codex.asked), (0, 1));
    });

    test('leaves out what is turned off, and what runs on this Mac', () async {
      final a = Approvals(
        EngineRegistry([
          _Judge('claude', _allow),
          _Judge('codex', _allow),
          _Judge('ollama', _allow, local: true),
        ]),
        HeadroomRouter(meter),
        (id) => id != 'claude',
        meter: meter,
      );
      expect([for (final e in a.judges()) e.info.id], ['codex']);
    });

    test('goes on to the next when one cannot answer, and asks the person when none can', () async {
      final claude = _Judge('claude', null);
      final codex = _Judge('codex', 'not a verdict');
      final j = await approvals([claude, codex]).judge(_push, asked: ['Set it up'], folder: '/p');
      expect((claude.asked, codex.asked), (1, 1));
      expect(j.verdict, Verdict.ask);
      expect(j.why, 'Run this command?');
    });

    test('logs each judge asked: which, its model and tokens, unknown as null', () async {
      final claude = _Judge('claude', null);
      final codex = _Judge(
        'codex',
        _allow,
        model: 'gpt-6-luna',
        tokens: const TurnTokens(fresh: 600, cacheRead: 1800, output: 40),
      );
      await approvals([claude, codex])
          .judge(_push, asked: ['Set it up'], folder: '/p', thread: 's1', chat: 'c1');
      // The log is written without holding up the verdict.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final lines = [
        for (final l in await log.read('2026-11'))
          if (l['kind'] == 'upkeep') l,
      ];
      expect(lines, hasLength(2));
      expect(lines[0], containsPair('connection', 'claude'));
      expect(lines[0], containsPair('model', null));
      expect(lines[0], containsPair('tokens', null));
      expect(lines[0], containsPair('kept', false));
      expect(lines[1], containsPair('what', 'judge'));
      expect(lines[1], containsPair('thread', 's1'));
      expect(lines[1], containsPair('chat', 'c1'));
      expect(lines[1], containsPair('connection', 'codex'));
      expect(lines[1], containsPair('model', 'gpt-6-luna'));
      expect(lines[1], containsPair('local', false));
      expect(lines[1], containsPair('promptTokens', 2400));
      expect(lines[1], containsPair('outputTokens', 40));
      expect(lines[1]['tokens'], {
        'fresh': 600,
        'cacheRead': 1800,
        'cacheWrite': null,
        'output': 40,
      });
      expect(lines[1], containsPair('kept', true));
      expect(lines[1]['ms'], isA<int>());
    });
  });
}
