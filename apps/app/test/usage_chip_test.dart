import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/settings_repository.dart';
import 'package:helmy/data/services/engines/engine_registry.dart';
import 'package:helmy/data/services/engines/usage_meter.dart';
import 'package:helmy/domain/models/engine.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/widgets/usage_chip.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:provider/provider.dart';

import 'support/echo_engine.dart';

class _Settings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
  @override
  Future<void> load() async {}
  @override
  Future<void> save(AppSettings settings) async {}
}

/// The usage chip in the top bar: the roomiest plan's number, and every
/// plan a hover away.
void main() {
  testWidgets('shows the roomiest plan, and the card lists every plan', (tester) async {
    final meter = UsageMeter();
    final soon = DateTime.now().add(const Duration(hours: 2));
    meter.report(
      'codex',
      Usage(
        used: .12,
        windows: [UsageWindow(name: 'Session (5 hours)', used: .12, resetsAt: soon)],
      ),
    );
    meter.report(
      'claude',
      Usage(
        used: .6,
        windows: [UsageWindow(name: 'Weekly', used: .6, resetsAt: soon)],
      ),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UsageMeter>.value(value: meter),
          ChangeNotifierProvider<SettingsRepository>.value(value: _Settings()),
          Provider<EngineRegistry>.value(
            value: EngineRegistry([
              EchoEngine(const [], id: 'claude'),
              EchoEngine(const [], id: 'codex'),
            ]),
          ),
        ],
        child: const AshlarApp(
          home: Align(alignment: Alignment.topRight, child: UsageChip()),
        ),
      ),
    );
    expect(find.text('12%'), findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Usage')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Both plans, by the names Settings gives them.
    expect(find.text('agent'), findsNWidgets(2));
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
  });
}
