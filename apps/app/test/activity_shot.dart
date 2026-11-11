import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';

import '../testing/fake_repositories.dart';

/// A pending approval, including its raw script, for layout and disclosure tests.
class ActivityShot extends StatefulWidget {
  const ActivityShot({super.key, this.work = false});
  final bool work;
  @override
  State<ActivityShot> createState() => _ActivityShotState();
}

class _ActivityShotState extends State<ActivityShot> {
  late final ConversationRepositoryEngines repo;
  late final ChatViewModel vm;
  final settings = FakeSettingsRepository();

  @override
  void initState() {
    super.initState();
    final root = Directory.systemTemp.createTempSync('activity-shot');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    repo = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    const input = {'command': 'python3 helmy-relaunch.py # subprocess.Popen', 'cwd': '/project'};
    repo.of('preview')
      ..loaded = true
      ..items.addAll([
        ToolCall(id: 'restart', name: 'Bash', input: input),
        PermissionPrompt(
          requestId: 'permission',
          toolUseId: 'restart',
          toolName: 'Bash',
          input: input,
          suggestions: const [],
        )..why = 'Create a relaunch script to reopen Helmy automatically?',
      ]);
    if (widget.work) {
      final edit = ToolCall(
        id: 'gutter',
        name: 'Write',
        input: {'file_path': 'line_numbers.dart', 'content': 'class LineNumberGutter {}'},
      )..result = 'File saved';
      final check = ToolCall(
        id: 'check',
        name: 'Shell',
        input: {'command': 'flutter test test/editor_test.dart'},
      )..result = 'All tests passed';
      edit
        ..activityLabel = 'Added the line-number gutter'
        ..activityResultHash = edit.result.hashCode;
      check
        ..activityLabel = 'Tested editing and saving'
        ..activityResultHash = check.result.hashCode
        ..activitySummary = 'Added line numbers and tested editing'
        ..activityIds = ['gutter', 'check'];
      repo.of('preview').items
        ..clear()
        ..addAll([edit, check]);
    }
    vm = ChatViewModel(sessionId: 'preview', sessions: sessions, conversations: repo);
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<SettingsRepository>.value(
    value: settings,
    child: ListenableBuilder(
      listenable: vm,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsetsDirectional.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final row in buildRows(vm)) row.child],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    vm.dispose();
    repo.dispose();
    settings.dispose();
    super.dispose();
  }
}

class WorkSummaryShot extends StatelessWidget {
  const WorkSummaryShot({super.key});
  @override
  Widget build(BuildContext context) => const ActivityShot(work: true);
}
