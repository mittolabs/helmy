import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/problem.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/problem_card.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/result.dart';

import 'support/storage.dart';

/// Errors as connections and the system report them.
const _errors = [
  'Claude AI usage limit reached|1793750400',
  'Rate limit exceeded (429)',
  'API Error: 529 {"type":"overloaded_error"}',
  'Invalid API key · Please run /login',
  'OAuth token has expired',
  'prompt is too long: 210000 tokens',
  'getaddrinfo ENOTFOUND api.anthropic.com',
  'connect ECONNREFUSED 127.0.0.1:11434',
  'Ollama is not running.',
  'Codex exited (code 1)',
  'something nobody has seen before',
  null,
];

void main() {
  group('times', atTimes);
  testWidgets('no problem reaches the conversation without a way to act on it', (tester) async {
    late Directory root;
    late ChatViewModel vm;
    late ConversationRepositoryEngines repo;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('problems');
      final storage = storageAt(root);
      final sessions = SessionRepositoryLocal(storage);
      final meter = UsageMeter();
      repo = ConversationRepositoryEngines(
        engines: EngineRegistry([]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final s = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(s.id).loaded = true;
      vm = ChatViewModel(sessionId: s.id, sessions: sessions, conversations: repo);
    });
    for (final raw in _errors) {
      final p = diagnose(raw, engineId: 'claude', now: DateTime(2026, 11, 4, 9));
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 600,
              child: ProblemCard(problem: p, vm: vm),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(p.what), findsOneWidget, reason: '$raw');
      if (p.fix == Fix.wait) {
        // Fixes itself, and says when.
        expect(p.what, contains('frees up at'), reason: '$raw');
      } else {
        expect(find.text(p.fix.label), findsOneWidget, reason: 'no action for: $raw');
      }
    }
    vm.dispose();
    repo.dispose();
    await tester.runAsync(() => deleteFolder(root));
  });

  test('answer links name fixes, and anything else is not one', () {
    expect(Fix.fromLink('helmy://fix/allow-speech'), Fix.allowSpeech);
    expect(Fix.fromLink('helmy://fix/start-local'), Fix.startLocal);
    expect(Fix.fromLink('https://example.com'), isNull);
    expect(Fix.fromLink('helmy://fix/delete-everything'), isNull);
  });
}

void atTimes() {
  test('a time follows a verb as said: today, tomorrow, or another day', () {
    final now = DateTime(2026, 11, 4, 22, 0);
    expect(atTime(DateTime(2026, 11, 4, 23, 40), now), 'at 11:40 PM');
    expect(atTime(DateTime(2026, 11, 5, 0, 34), now), 'tomorrow at 12:34 AM');
    expect(atTime(DateTime(2026, 11, 6, 9, 0), now), 'on 11/6 at 9:00 AM');
  });
}
