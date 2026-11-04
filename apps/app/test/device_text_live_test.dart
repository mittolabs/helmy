@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/watch_service.dart';

void main() {
  test('read the simulator, tap Settings by its ref, read again (real simulator)', () async {
    final tools = HelmyTools(WatchService(CliLocator()), DeviceService(CliLocator()));
    Future<String> call(String name, [Map args = const {}]) async {
      final r = await tools.answer('tools/call', {'name': name, 'arguments': args});
      return (((r['result']! as Map)['content'] as List).first as Map)['text'] as String;
    }

    await call('device_act', {
      'steps': [
        {'do': 'press', 'key': 'Home'},
        {'do': 'wait', 'ms': 800},
      ],
    });
    final watch = Stopwatch()..start();
    final home = await call('device_read');
    final readMs = watch.elapsedMilliseconds;
    final ref = RegExp(r'\[(d\d+)\] Button "Settings"').firstMatch(home)?[1];
    expect(ref, isNotNull, reason: home);
    watch.reset();
    final after = await call('device_act', {
      'steps': [
        {'do': 'tap', 'ref': ref},
        {'do': 'wait', 'ms': 1500},
      ],
    });
    // ignore: avoid_print
    print('read: $readMs ms; act + read: ${watch.elapsedMilliseconds} ms\n${after.split('\n').take(6).join('\n')}');
    expect(after, isNot(contains('Button "Settings"')), reason: 'Settings opened, the home screen left');
    expect(after, contains('now:\n[d1]'), reason: 'and Settings was read: $after');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
