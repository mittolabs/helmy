import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/claude/claude_reducer.dart';
import 'package:helmy/data/services/engines/codex/codex_reducer.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chats/chat_page_view_model.dart';
import 'package:helmy/utils/result.dart';

Map<String, Object?> codexUsage({
  required Map<String, int> total,
  required Map<String, int> last,
}) => {
  'method': 'thread/tokenUsage/updated',
  'params': {
    'tokenUsage': {'total': total, 'last': last, 'modelContextWindow': 200000},
  },
};

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('log'));
  tearDown(() => root.delete(recursive: true));

  test('lines go into the month, one each, unknown figures as unknown', () async {
    final log = TurnLog(appData: () async => root, now: () => DateTime.utc(2026, 11, 4, 9));
    await log.turn(
      chat: 'c1',
      thread: 't1',
      connection: 'codex',
      moved: false,
      tokens: const TurnTokens(fresh: 900, cacheRead: 12000, output: 300),
      took: const Duration(seconds: 3),
      from: 4,
      to: 9,
    );
    await log.correction(what: 'move', thread: 't1', from: 'c1', to: 'c2');
    final lines = await log.read('2026-11');
    expect(lines.map((l) => l['kind']), ['turn', 'correction']);
    expect((lines.first['tokens'] as Map)['cacheWrite'], isNull, reason: 'not reported: unknown');
    expect(lines.first['items'], [4, 9]);
    expect(File('${root.path}/logs/turns-2026-11.jsonl').readAsLinesSync(), hasLength(2));
    expect(lines.first.toString(), isNot(contains('said')), reason: 'no words of the turn');
  });

  test("Claude Code's turn tokens come from its result, as it reports them", () {
    final r = ClaudeReducer(<ChatItem>[])
      ..apply({
        'type': 'result',
        'subtype': 'success',
        'usage': {
          'input_tokens': 40,
          'cache_read_input_tokens': 15000,
          'cache_creation_input_tokens': 800,
          'output_tokens': 220,
        },
      });
    expect(
      (r.tokens?.fresh, r.tokens?.cacheRead, r.tokens?.cacheWrite, r.tokens?.output),
      (40, 15000, 800, 220),
    );
  });

  test("a Codex turn's tokens are its total at the end less at the start, resumed or not", () {
    final r = CodexReducer(<ChatItem>[]);
    // A thread resumed: the first report carries the whole thread's total.
    r.apply({
      'method': 'turn/started',
      'params': {
        'turn': {'id': 't1'},
      },
    });
    r.apply(
      codexUsage(
        total: {
          'inputTokens': 50000,
          'cachedInputTokens': 40000,
          'cacheWriteInputTokens': 0,
          'outputTokens': 2000,
        },
        last: {
          'inputTokens': 5000,
          'cachedInputTokens': 4000,
          'cacheWriteInputTokens': 0,
          'outputTokens': 200,
        },
      ),
    );
    expect((r.tokens?.fresh, r.tokens?.cacheRead, r.tokens?.output), (1000, 4000, 200));
    // A second request in the same turn adds to it.
    r.apply(
      codexUsage(
        total: {
          'inputTokens': 56000,
          'cachedInputTokens': 45000,
          'cacheWriteInputTokens': 100,
          'outputTokens': 2300,
        },
        last: {
          'inputTokens': 6000,
          'cachedInputTokens': 5000,
          'cacheWriteInputTokens': 100,
          'outputTokens': 300,
        },
      ),
    );
    expect(
      (r.tokens?.fresh, r.tokens?.cacheRead, r.tokens?.cacheWrite, r.tokens?.output),
      (2000, 9000, 100, 500),
    );
    // The next turn counts from where this one ended.
    r.apply({
      'method': 'turn/started',
      'params': {
        'turn': {'id': 't2'},
      },
    });
    expect(r.tokens, isNull);
    r.apply(
      codexUsage(
        total: {
          'inputTokens': 60000,
          'cachedInputTokens': 48000,
          'cacheWriteInputTokens': 100,
          'outputTokens': 2400,
        },
        last: {
          'inputTokens': 4000,
          'cachedInputTokens': 3000,
          'cacheWriteInputTokens': 0,
          'outputTokens': 100,
        },
      ),
    );
    expect((r.tokens?.fresh, r.tokens?.cacheRead, r.tokens?.output), (1000, 3000, 100));
  });

  test("a chat's page: threads moved and briefs rewritten are logged as corrections", () async {
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final chats = ChatRepository(storage, sessions);
    addTearDown(chats.dispose);
    await chats.load();
    final a = (await sessions.create(cwd: '/w/money', title: 'Budget') as Ok).value as Session;
    final b = (await sessions.create(cwd: '/w/money', title: 'Taxes') as Ok).value as Session;
    final log = TurnLog(appData: () async => root, now: () => DateTime.utc(2026, 11, 4));
    final page = ChatPageViewModel(
      chatId: sessions.byId(a.id)!.chatId!,
      chats: chats,
      sessions: sessions,
      log: log,
    );
    addTearDown(page.dispose);
    await page.move(sessions.byId(b.id)!, page.chatId);
    expect(page.threads.length, 2);
    await page.setBrief('Decided: a monthly budget.');
    await page.setBrief('Decided: a monthly budget.');
    final id = await page.newThread();
    expect(sessions.byId(id!)!.chatId, page.chatId);
    expect(sessions.byId(id)!.cwd, '/w/money');
    final kinds = [for (final l in await log.read('2026-11')) l['what']];
    expect(kinds, ['move', 'brief'], reason: 'an unchanged brief is not a correction');
  });
}
