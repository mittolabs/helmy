import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/config/dependencies.dart';
import 'package:helmy/data/repositories/attention_repository.dart';
import 'package:helmy/data/repositories/conversation_repository.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/project_repository.dart';
import 'package:helmy/data/repositories/schedule_repository.dart';
import 'package:helmy/data/repositories/session_repository.dart';
import 'package:helmy/data/repositories/session_repository_local.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/repositories/ship_repository.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/storage_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('the app provides every repository under the type screens ask for', (tester) async {
    late Directory root;
    await tester.runAsync(() async => root = await Directory.systemTemp.createTemp('providers'));
    final dir = root.path;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir,
    );
    final storage = StorageService(root: () async => root);
    final loaded = (
      storage: storage,
      sessions: SessionRepositoryLocal(storage) as SessionRepository,
      settings: SettingsRepositoryLocal(storage) as SettingsRepository,
      meter: UsageMeter(),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: providers(loaded),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // Each read throws if a repository is registered under another type.
    expect(context.read<SettingsRepository>(), isNotNull);
    expect(context.read<SessionRepository>(), isNotNull);
    expect(context.read<ConversationRepository>(), isNotNull);
    expect(context.read<MemoryRepository>(), isNotNull);
    expect(context.read<ScheduleRepository>(), isNotNull);
    expect(context.read<AttentionRepository>(), isNotNull);
    expect(context.read<ShipRepository>(), isNotNull);
    expect(context.read<ProjectRepository>(), isNotNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(hours: 1));
    root.deleteSync(recursive: true);
  });
}
