// Run on macOS with an iPhone simulator booted and AXe installed:
// fvm flutter test integration_test/sim_input_test.dart -d macos \
//   --dart-define=SHOT=/path/to/simulator.png
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/sim_input.dart';
import 'package:integration_test/integration_test.dart';

const shot = String.fromEnvironment('SHOT');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('taps on the simulator take milliseconds, through the bundled helper', () async {
    final data = await Directory.systemTemp.createTemp('sim_input');
    final locator = CliLocator();
    final input = SimInput(
      helper: () async =>
          (await rootBundle.load('assets/helmy/bin/sim_input')).buffer.asUint8List(),
      appData: () async => data,
      axe: () => locator.find('axe'),
    );
    addTearDown(input.dispose);
    final devices = DeviceService(locator, input: input);
    final phone = (await devices.list()).firstWhere((d) => d.ios && d.booted);

    // The first starts the helper; the rest are what each tap costs.
    expect(await input.home(phone.id), isTrue, reason: 'the helper runs here');
    final times = <int>[];
    for (var i = 0; i < 5; i++) {
      // Apart, as a person presses: two close together open the app switcher.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final watch = Stopwatch()..start();
      expect(await devices.home(phone), isTrue);
      times.add(watch.elapsedMilliseconds);
    }
    // ignore: avoid_print
    print('home presses took $times ms');
    expect(times.every((t) => t < 150), isTrue, reason: '$times');

    await Future<void>.delayed(const Duration(seconds: 1));
    // Settings is on the home screen's last row of apps, on the right.
    await devices.tap(phone, 339, 415);
    await Future<void>.delayed(const Duration(seconds: 2));
    await devices.tap(phone, 175, 820); // its search field
    await Future<void>.delayed(const Duration(seconds: 1));
    final watch = Stopwatch()..start();
    expect(await devices.type(phone, 'Wi-Fi'), isTrue);
    // ignore: avoid_print
    print('typing took ${watch.elapsedMilliseconds} ms');
    await Future<void>.delayed(const Duration(seconds: 1));
    if (shot.isNotEmpty) {
      await Process.run('/usr/bin/xcrun', ['simctl', 'io', phone.id, 'screenshot', shot]);
    }
    await devices.home(phone);
  });
}
