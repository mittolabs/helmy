import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/activity_summarizer.dart';
import 'package:helmy/data/services/engines/agent_engine.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';

class _Engine implements AgentEngine {
  String? answer;
  final questions = <String>[];
  @override
  final info = const EngineInfo(id: 'test', name: 'Test');
  @override
  Future<String?> ask(String instructions, String question) async {
    questions.add(question);
    return answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('describes different work using its results, not a count of tool calls', () async {
    final engine = _Engine()
      ..answer = jsonEncode({
        'summary': 'Added line numbers and tested editing',
        'steps': {'edit': 'Added the line-number gutter', 'test': 'Tested editing and saving'},
      });
    final meter = UsageMeter();
    final service = ActivitySummarizer(
      EngineRegistry([engine]),
      HeadroomRouter(meter),
      meter,
      (_) => true,
    );
    final calls = [
      ToolCall(
        id: 'edit',
        name: 'Write',
        input: {'file_path': 'gutter.dart', 'content': 'line numbers'},
      )..result = 'saved',
      ToolCall(id: 'test', name: 'Shell', input: {'command': 'flutter test test/editor_test.dart'})
        ..result = 'All tests passed',
    ];
    final result = await service.describe(calls);
    expect(result!.title, 'Added line numbers and tested editing');
    expect(result.steps['edit'], 'Added the line-number gutter');
    final records = jsonDecode(engine.questions.single)['actions'] as List;
    expect(records.last['result'], 'All tests passed');
    expect(records.last['failed'], isFalse);
  });

  test('does not summarize unfinished work or use a disabled connection', () async {
    final engine = _Engine();
    final meter = UsageMeter();
    final service = ActivitySummarizer(
      EngineRegistry([engine]),
      HeadroomRouter(meter),
      meter,
      (_) => false,
    );
    final call = ToolCall(id: 'a', name: 'Shell', input: {'command': 'build'});
    expect(await service.describe([call]), isNull);
    call.result = 'done';
    expect(await service.describe([call]), isNull);
    expect(engine.questions, isEmpty);
  });

  test('rejects an incomplete breakdown and keeps factual fallback labels', () async {
    final engine = _Engine()..answer = '{"summary":"Done","steps":{}}';
    final meter = UsageMeter();
    final service = ActivitySummarizer(
      EngineRegistry([engine]),
      HeadroomRouter(meter),
      meter,
      (_) => true,
    );
    expect(
      await service.describe([ToolCall(id: 'a', name: 'Read', input: {})..result = 'text']),
      isNull,
    );
  });

  test('activity descriptions survive saving and reopening a transcript', () {
    final call = ToolCall(id: 'a', name: 'Shell', input: {})
      ..result = 'done'
      ..activityLabel = 'Tested saving files'
      ..activitySummary = 'Added line numbers and tested saving'
      ..activityIds = ['a'];
    final restored = ToolCall.fromJson(call.toJson());
    expect(restored.activityLabel, call.activityLabel);
    expect(restored.activitySummary, call.activitySummary);
    expect(restored.activityIds, ['a']);
  });
}
