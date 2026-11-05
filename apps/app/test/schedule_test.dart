import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository_engines.dart';
import 'package:helmy/data/repositories/schedule_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/engine_router.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:helmy/domain/models/chat_item.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/scheduled_task.dart';

void main() {
  // Tuesday, Nov 3 2026, 10:15.
  final tue = DateTime(2026, 11, 3, 10, 15);

  test('each repeat finds its next time', () {
    expect(Schedule(.daily, DateTime(2026, 1, 1, 9)).nextAfter(tue), DateTime(2026, 11, 4, 9));
    expect(Schedule(.daily, DateTime(2026, 1, 1, 11)).nextAfter(tue), DateTime(2026, 11, 3, 11));
    expect(
      Schedule(.hourly, DateTime(2026, 1, 1, 0, 5)).nextAfter(tue),
      DateTime(2026, 11, 3, 11, 5),
    );
    expect(
      Schedule(.hourly, DateTime(2026, 1, 1, 0, 30)).nextAfter(tue),
      DateTime(2026, 11, 3, 10, 30),
    );
    // Friday evening: weekdays skip to Monday.
    final fri = DateTime(2026, 11, 6, 18);
    expect(Schedule(.weekdays, DateTime(2026, 1, 1, 9)).nextAfter(fri), DateTime(2026, 11, 9, 9));
    // Weekly on Mondays (Jan 5 2026 is a Monday).
    expect(
      Schedule(.weekly, DateTime(2026, 1, 5, 8, 30)).nextAfter(tue),
      DateTime(2026, 11, 9, 8, 30),
    );
    expect(Schedule(.once, DateTime(2026, 11, 4, 15)).nextAfter(tue), DateTime(2026, 11, 4, 15));
    expect(Schedule(.once, DateTime(2026, 11, 2, 15)).nextAfter(tue), isNull);
    // Mondays and Thursdays at 9: from Tuesday, Thursday.
    final monThu = Schedule(.days, DateTime(2026, 1, 1, 9), days: const {1, 4});
    expect(monThu.nextAfter(tue), DateTime(2026, 11, 5, 9));
    expect(monThu.label, 'Mon, Thu at 9:00 AM');
    expect(Schedule.fromJson(monThu.toJson()).days, {1, 4});
    expect(
      Schedule(.days, DateTime(2026, 1, 1, 9)).nextAfter(tue),
      isNull,
      reason: 'no day chosen',
    );
  });

  test('schedules read as people say them', () {
    expect(Schedule(.daily, DateTime(2026, 1, 1, 9)).label, 'Every day at 9:00 AM');
    expect(Schedule(.weekly, DateTime(2026, 1, 5, 14, 5)).label, 'Mondays at 2:05 PM');
    expect(Schedule(.hourly, DateTime(2026, 1, 1, 0, 5)).label, 'Every hour at :05');
    expect(Schedule(.once, DateTime(2026, 11, 4, 0, 30)).label, 'Once, Nov 4 at 12:30 AM');
  });

  test('a due task runs once in a new session, and a one-off then stops', () async {
    final root = await Directory.systemTemp.createTemp('schedule');
    final storage = StorageService(root: () async => root);
    final sessions = SessionRepositoryLocal(storage);
    final meter = UsageMeter();
    final conversations = ConversationRepositoryEngines(
      engines: EngineRegistry([]),
      router: HeadroomRouter(meter),
      meter: meter,
      storage: storage,
      sessions: sessions,
    );
    var now = DateTime(2026, 11, 3, 8, 59);
    final repo = ScheduleRepositoryLocal(
      storage: storage,
      sessions: sessions,
      conversations: conversations,
      now: () => now,
    );
    await repo.start();
    final daily = await repo.add(
      name: 'Morning summary',
      prompt: 'Summarize yesterday',
      cwd: root.path,
      level: .readOnly,
      schedule: Schedule(.daily, DateTime(2026, 1, 1, 9)),
    );
    final once = await repo.add(
      name: 'One-off',
      prompt: 'Just once',
      cwd: root.path,
      level: .ask,
      schedule: Schedule(.once, DateTime(2026, 11, 3, 9)),
    );

    await repo.tick();
    expect(repo.runsOf(daily.id), isEmpty, reason: 'not yet 9');

    // The app was closed over 9:00 on two days: the daily runs once, not twice.
    now = DateTime(2026, 11, 4, 10);
    await repo.tick();
    await repo.tick();
    final runs = repo.runsOf(daily.id);
    expect(runs, hasLength(1));
    expect(runs.single.title, 'Morning summary · Nov 4, 10:00 AM');
    expect(runs.single.level, PermissionLevel.readOnly);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      conversations.of(runs.single.id).items.whereType<UserMessage>().single.text,
      'Summarize yesterday',
    );
    expect(repo.runsOf(once.id), hasLength(1));
    expect(repo.tasks.firstWhere((t) => t.id == once.id).next, isNull);
    expect(repo.tasks.firstWhere((t) => t.id == daily.id).next, DateTime(2026, 11, 5, 9));

    // Off means off; and what was saved reads back.
    await repo.update(repo.tasks.first.copyWith(enabled: false));
    now = DateTime(2026, 11, 6, 10);
    await repo.tick();
    expect(repo.runsOf(daily.id), hasLength(1));
    await storage.flush();
    final again = ScheduleRepositoryLocal(
      storage: storage,
      sessions: sessions,
      conversations: conversations,
      now: () => now,
    );
    await again.start();
    expect(again.tasks.map((t) => t.name), ['Morning summary', 'One-off']);
    expect(again.tasks.first.enabled, isFalse);

    again.dispose();
    repo.dispose();
    conversations.dispose();
    await storage.flush();
    await root.delete(recursive: true);
  });
}
