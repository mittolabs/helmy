import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/session.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart' show stepsSummary;
import 'package:helmy/utils/result.dart';
import 'package:helmy/data/services/engines/codex/codex_engine.dart';
import 'package:helmy/data/services/engines/claude/claude_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';

void main() {
  test(
    'a real connection describes the editor-check example specifically',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final locator = CliLocator();
      final meter = UsageMeter();
      final root = await Directory.systemTemp.createTemp('live-activity');
      final storage = StorageService(root: () async => root);
      final sessions = SessionRepositoryLocal(storage);
      final repo = ConversationRepositoryEngines(
        engines: EngineRegistry([CodexEngine(locator), ClaudeEngine(locator)]),
        router: HeadroomRouter(meter),
        meter: meter,
        storage: storage,
        sessions: sessions,
      );
      final session = (await sessions.create(cwd: root.path) as Ok).value as Session;
      repo.of(session.id).loaded = true;
      final calls = [
        ToolCall(
            id: 'inspect',
            name: 'Shell',
            input: {
              'command': 'rg -n "getLocalRectForCaret|hasUnsavedEdits" numbered_code_input.dart files_panel.dart',
            },
          )
          ..result =
              'Line numbers use editor caret positions. File switching checks hasUnsavedEdits.',
        ToolCall(
          id: 'saving',
          name: 'Shell',
          input: {'command': 'sed -n "69,145p" file_document.dart'},
        )..result = 'Save compares current disk text with the original; changed files are not overwritten.',
        ToolCall(
          id: 'tests',
          name: 'Shell',
          input: {
            'command': 'flutter test test/file_document_test.dart test/file_editor_test.dart',
          },
        )..result = 'Tested saving, external conflicts, deleted files, drafts, binary files, and editing beside the tree.\n+8: All tests passed!',
      ];
      repo.of(session.id).items.addAll([
        UserMessage('Do another task with steps so I can see'),
        AssistantText(
          'purpose',
          'I will check editor line-number alignment, unsaved-edit protection, and saving.',
        ),
        ...calls,
      ]);
      final vm = ChatViewModel(sessionId: session.id, sessions: sessions, conversations: repo);
      addTearDown(() async {
        vm.dispose();
        repo.dispose();
        await storage.flush();
        await root.delete(recursive: true);
      });
      await vm.ready;
      final result = await vm.describeActivities(calls);
      expect(result, isNotNull);
      expect(
        result!.steps.values,
        everyElement(isNot(anyOf('Searched the files', 'Ran tests', 'Read file contents'))),
      );
      // Fixed test data only: safe to inspect the generated descriptions.
      expect(stepsSummary(calls), result.title);
      final saved = await storage.read('transcripts/${session.id}.json') as List;
      expect(saved.last['activitySummary'], result.title);
      debugPrint('SUMMARY: ${result.title}');
      for (final label in result.steps.values) {
        debugPrint('ACTIVITY: $label');
      }
    },
    skip: Platform.environment['HELMY_ACTIVITY_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
