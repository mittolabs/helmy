// Drives a real ACP agent: OpenCode on a free model.
// OPENCODE=/path/to/opencode fvm flutter test test/acp_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/engines/acp/acp_engine.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/domain/models/chat_item.dart';

void main() {
  final bin = Platform.environment['OPENCODE'];
  test(
    'OpenCode over ACP makes a file and says so, on a private free model',
    () async {
      final dir = await Directory.systemTemp.createTemp('acp-live');
      addTearDown(() => dir.delete(recursive: true));
      final engine = AcpEngine(
        CliLocator(),
        id: 'acp.opencode',
        name: 'OpenCode',
        command: bin!,
        args: const ['acp'],
        profile: opencodeProfile,
      );
      final items = <ChatItem>[];
      final run = await engine.start(EngineLaunch(cwd: dir.path, level: .full), items);
      final ended = run.changes.firstWhere((e) => e);
      run.send('Create a file hello.txt containing the word hi. Then say done.');
      await ended.timeout(const Duration(minutes: 2));
      await run.close();
      expect(File('${dir.path}/hello.txt').readAsStringSync().trim(), 'hi');
      expect(items.whereType<ToolCall>(), isNotEmpty);
      expect(items.whereType<AssistantText>(), isNotEmpty);
      expect(items.whereType<TurnSummary>().last.ok, isTrue);
      expect(run.status.resumeId, isNotNull);
    },
    skip: bin == null ? 'set OPENCODE to an opencode binary' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'asked first, it waits for the answer and goes on once allowed',
    () async {
      final dir = await Directory.systemTemp.createTemp('acp-live');
      addTearDown(() => dir.delete(recursive: true));
      final engine = AcpEngine(
        CliLocator(),
        id: 'acp.opencode',
        name: 'OpenCode',
        command: bin!,
        args: const ['acp'],
        profile: opencodeProfile,
      );
      final items = <ChatItem>[];
      final run = await engine.start(EngineLaunch(cwd: dir.path, level: .ask), items);
      final asked = run.changes.firstWhere((_) => items.whereType<PermissionPrompt>().isNotEmpty);
      final ended = run.changes.firstWhere((e) => e);
      run.send('Create a file note.txt containing the word ok.');
      await asked.timeout(const Duration(minutes: 2));
      expect(File('${dir.path}/note.txt').existsSync(), isFalse);
      run.answer(items.whereType<PermissionPrompt>().first, .allow);
      await ended.timeout(const Duration(minutes: 2));
      await run.close();
      expect(File('${dir.path}/note.txt').readAsStringSync().trim(), 'ok');
    },
    skip: bin == null ? 'set OPENCODE to an opencode binary' : null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
