import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/memory_repository.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/data/services/turn_log.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/settings/view_models/settings_view_model.dart';
import 'package:helmy/ui/settings/widgets/settings_screen.dart';
import 'package:provider/provider.dart';

import '../testing/fake_repositories.dart';

/// Settings > Usage: under the limits, this month's tokens per connection,
/// cached and uncached apart, as the turn log has them.
void main() {
  testWidgets("this month's tokens show under the limits", (tester) async {
    tester.view.physicalSize = const Size(2400, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('usage-month');
      final now = DateTime.now();
      final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      await Directory('${root.path}/logs').create(recursive: true);
      await File('${root.path}/logs/turns-$month.jsonl').writeAsString(
        [
          {
            'kind': 'turn',
            'connection': 'claude',
            'tokens': {
              'fresh': 210000,
              'cacheRead': 52000000,
              'cacheWrite': 8000,
              'output': 182000,
            },
          },
          {'kind': 'turn', 'connection': 'acp.opencode', 'tokens': null},
        ].map(jsonEncode).join('\n'),
      );
    });
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final settings = FakeSettingsRepository(const AppSettings());
    final engines = EngineRegistry([]);
    final vm = SettingsViewModel(
      settings: settings,
      engines: engines,
      meter: UsageMeter(),
      memory: MemoryRepositoryEngines(engines),
    )..show(SettingsSection.usage);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsRepository>.value(value: settings),
          Provider(create: (_) => DesktopService()),
          Provider(create: (_) => TurnLog(appData: () async => root)),
        ],
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: SettingsScreen(viewModel: vm),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('This month'), findsOneWidget);
    expect(find.textContaining('52M cached input (99% of input)'), findsOneWidget);
    expect(find.textContaining('182k output'), findsOneWidget);
    expect(find.textContaining('reports no token counts'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
