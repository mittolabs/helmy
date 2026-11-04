import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:provider/provider.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/helmy_voice.dart';
import 'package:helmy/domain/identity.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/utils/result.dart';

final _names = RegExp(
  r'claude|anthropic|codex|openai|chatgpt|ollama|qwen|mcp__',
  caseSensitive: false,
);

void main() {
  test("a connection's errors reach the conversation in Helmy's words", () {
    expect(
      inHelmysWords('Claude AI usage limit reached|1793750400'),
      "I've reached a usage limit. Try again in a little while.",
    );
    expect(inHelmysWords('API Error: 529 {"type":"overloaded_error"}'), contains('overloaded'));
    expect(inHelmysWords('Invalid API key · Please run /login'), contains('signed in'));
    expect(inHelmysWords('prompt is too long: 210000 tokens'), contains('too long'));
    expect(
      inHelmysWords('Ollama answered 500'),
      'Something went wrong on my side. Send it again to try once more.',
    );
    expect(inHelmysWords(null), contains('Something went wrong'));
    for (final raw in ['Codex exited (code 1)', 'Claude Code exited', 'stream error from OpenAI']) {
      expect(_names.hasMatch(inHelmysWords(raw)), isFalse, reason: raw);
    }
  });

  test('tool names, stop and decline notes, and descriptions read as Helmy', () {
    expect(toolLabel('mcp__claude_ai_Gmail__search_threads'), 'Gmail: search threads');
    expect(toolLabel('mcp__claude_ai_Google_Drive__read_file'), 'Google Drive: read file');
    expect(toolLabel('notion.query_database'), 'Notion: query database');
    expect(toolLabel('Bash'), 'Bash');
    expect(stepResult('[Request interrupted by user for tool use]'), 'Stopped.');
    expect(
      stepResult("The user doesn't want to proceed with this tool use."),
      'You declined this.',
    );
    expect(stepResult('3 files changed'), '3 files changed');
    expect(
      withoutNames('Ask Claude Code to review a pull request'),
      'Ask Helmy to review a pull request',
    );
  });

  test('the identity names Helmy and its maker, and no product behind it as itself', () {
    expect(helmyIdentity, contains('You are Helmy'));
    expect(helmyIdentity, contains('Mittolabs'));
    expect(helmyIdentity, contains('never claim there is none'));
    expect(helmyIdentity, isNot(contains('keep the supplier private')));
  });

  testWidgets('a conversation full of what connections say shows none of their names', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('voice');
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
    late ChatViewModel vm;
    await tester.runAsync(() async {
      final created = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(created.id)
        ..loaded = true
        ..items.addAll([
          UserMessage('find the budget in my drive'),
          ToolCall(id: 't1', name: 'mcp__claude_ai_Google_Drive__search', input: {'q': 'budget'})
            ..result = '[Request interrupted by user for tool use]',
          ToolCall(id: 't2', name: 'Bash', input: {'command': 'ls'})
            ..result = "The user doesn't want to proceed with this tool use."
            ..isError = true,
          TurnSummary(ok: false, error: 'Claude AI usage limit reached|1793750400'),
          UserMessage('again'),
          TurnSummary(ok: false, error: 'Codex exited (code 1): stream error from OpenAI'),
        ]);
      vm = ChatViewModel(sessionId: created.id, sessions: sessions, conversations: repo);
    });
    // Steps open, so every tool name and result is on screen to check.
    final settings = SettingsRepository(storage);
    await tester.runAsync(() => settings.save(settings.settings.copyWith(stepsOpen: true)));
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: AshlarApp(
          home: ListenableBuilder(
            listenable: vm,
            builder: (context, _) => ListView(children: [for (final r in buildRows(vm)) r.child]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Groups of steps open too.
    for (final g in find.textContaining('Used a tool').evaluate().toList()) {
      await tester.tap(find.byWidget(g.widget));
      await tester.pumpAndSettle();
    }
    final shown = [
      for (final e in find.byType(RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
    ].join('\n');
    expect(shown, contains("I've reached a usage limit"));
    expect(shown, contains('Google Drive: search'));
    expect(shown, contains('Stopped.'));
    expect(_names.hasMatch(shown), isFalse, reason: shown);
    vm.dispose();
    repo.dispose();
    await tester.runAsync(() => root.delete(recursive: true));
  });
}
