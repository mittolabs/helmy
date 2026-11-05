import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/mac/mac_actions.dart';
import 'package:helmy/data/services/mac/mac_tools.dart';

/// Answers each program from [said], recording what ran.
({MacActions mac, List<String> ran, List<Map<String, Object?>> asked}) fake({
  Map<String, String> said = const {},
  Object? Function(Map<String, Object?>)? native,
}) {
  final ran = <String>[];
  final asked = <Map<String, Object?>>[];
  final mac = MacActions(
    run: (p, args) async {
      final line = '${p.split('/').last} ${args.join(' ')}';
      ran.add(line);
      final out = said.entries.where((e) => line.startsWith(e.key)).firstOrNull?.value ?? '';
      return ProcessResult(0, 0, out, '');
    },
    native: (args) async {
      asked.add(args);
      return native?.call(args);
    },
  );
  return (mac: mac, ran: ran, asked: asked);
}

String text(Map<String, Object?> r) => ((r['content']! as List).first as Map)['text'] as String;

void main() {
  test('battery reads its level, source, health and cycles', () async {
    final f = fake(
      said: {
        'pmset -g batt': "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t64%; discharging; 3:12 remaining present: true",
        'system_profiler': '          Cycle Count: 235\n          Condition: Normal\n          Maximum Capacity: 95%',
      },
    );
    final s = await f.mac.battery();
    expect(s, contains('Battery at 64%, discharging.'));
    expect(s, contains('Running on battery.'));
    expect(s, contains('About 3:12 left'));
    expect(s, contains('holds 95%'));
    expect(s, contains('235 charge cycles'));
  });

  test('a Mac with no battery says so', () async {
    final f = fake(said: {'pmset -g batt': "Now drawing from 'AC Power'"});
    expect(await f.mac.battery(), 'This Mac has no battery.');
  });

  test('volume is clamped, and the microphone comes back to its level', () async {
    final f = fake(
      said: {
        'osascript -e get volume settings':
            'output volume:19, input volume:27, alert volume:100, output muted:false',
      },
    );
    expect(await f.mac.setVolume(140), 'Volume is 100 of 100.');
    expect(f.ran.last, contains('set volume output volume 100'));
    await f.mac.muteMic(true);
    expect(f.ran.last, contains('input volume 0'));
  });

  test('lock without Accessibility says why, with the fix link', () async {
    final f = fake(native: (a) => a['do'] == 'lock' ? 'accessibility' : null);
    final r = await MacTools(f.mac).call('mac_screen', {'do': 'lock'});
    expect(r['isError'], isTrue);
    expect(text(r), contains('Accessibility'));
    expect(text(r), contains('helmy://fix/allow-accessibility'));
  });

  test('lock with Accessibility asks the Mac side to press it', () async {
    final f = fake();
    final r = await MacTools(f.mac).call('mac_screen', {'do': 'lock'});
    expect(r['isError'], isFalse);
    expect(f.asked.single['do'], 'lock');
  });

  test('an output is found by part of its name', () async {
    final f = fake(
      native: (a) => switch (a['do']) {
        'outputs' => [
          {'id': 1, 'name': 'MacBook Pro Speakers', 'current': true},
          {'id': 7, 'name': "Sam's AirPods Pro", 'current': false},
        ],
        'setOutput' => true,
        _ => null,
      },
    );
    expect(await f.mac.setOutput('airpods'), "Sound plays through Sam's AirPods Pro.");
    expect(f.asked.last, {'do': 'setOutput', 'id': 7});
    expect(() => f.mac.setOutput('HomePod'), throwsA(isA<MacTrouble>()));
  });

  test('quitting an app that is not open says so', () async {
    final f = fake(native: (a) => 'No open app is called Zoom.');
    final r = await MacTools(f.mac).call('mac_quit', {'app': 'Zoom'});
    expect(r['isError'], isTrue);
    expect(text(r), 'No open app is called Zoom.');
  });

  test('eject says what went and what is still in use', () async {
    final f = fake(
      native: (a) => {
        'ejected': ['Backup'],
        'failed': ['Photos'],
      },
    );
    expect(
      await f.mac.eject(),
      "Ejected Backup. Couldn't eject Photos: something is still using it.",
    );
  });

  test('the speed test is read from its JSON', () async {
    final f = fake(
      said: {
        'networkQuality':
            '{"dl_throughput": 94300000, "ul_throughput": 21000000, "responsiveness": 1450}',
      },
    );
    expect(
      await f.mac.speedTest(),
      startsWith('Download 94 Mbps, upload 21 Mbps, responsiveness 1450'),
    );
  });

  test('an until time is today, or tomorrow once it has passed', () {
    final now = DateTime(2026, 11, 5, 18, 0);
    expect(MacTools.nextAt('22:30', now), DateTime(2026, 11, 5, 22, 30));
    expect(MacTools.nextAt('06:00', now), DateTime(2026, 11, 6, 6, 0));
  });

  test('only the easily undone Mac tools are allowed without asking', () {
    expect(HelmyTools.claudeTools, contains('mcp__helmy__mac_sound'));
    expect(HelmyTools.claudeTools, isNot(contains('mcp__helmy__mac_quit')));
    expect(HelmyTools.claudeTools, isNot(contains('mcp__helmy__mac_eject')));
    expect(HelmyTools.claudeTools, isNot(contains('mcp__helmy__mac_power')));
  });

  test('every Mac tool listed is one it can do', () {
    expect([for (final t in MacTools.list) t['name']], MacTools.names);
  });
}
