// Drives what only a Mac has.
@TestOn('mac-os')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/sim_input.dart';

/// A stand-in for the helper, as a script: says ready, then answers each line
/// as [answer] (shell, with the line in \$line) says.
Uint8List script(String answer, {String start = 'echo ready'}) => Uint8List.fromList(
  utf8.encode('#!/bin/sh\n$start\nwhile IFS= read -r line; do\n$answer\ndone\n'),
);

void main() {
  late Directory dir;
  late String axe;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sim_input');
    // AXe as Homebrew lays it out: the command, and its frameworks beside it.
    Directory('${dir.path}/axe/libexec/Frameworks').createSync(recursive: true);
    Directory('${dir.path}/axe/bin').createSync();
    axe = '${dir.path}/axe/bin/axe';
    File(axe).writeAsStringSync('');
  });
  tearDown(() => dir.delete(recursive: true));

  SimInput input(Uint8List helper, {String? axeAt}) => SimInput(
    helper: () async => helper,
    appData: () async => Directory('${dir.path}/data'),
    axe: () async => axeAt ?? axe,
  );

  test('answers each action, in order, from one helper kept running', () async {
    final starts = File('${dir.path}/starts');
    final seen = File('${dir.path}/seen');
    final sim = input(
      script('''
echo "\$line" >> ${seen.path}
case "\$line" in
  *'"x":0'*) echo "error: off the screen" ;;
  *) echo ok ;;
esac''', start: 'echo x >> ${starts.path}; echo ready'),
    );
    addTearDown(sim.dispose);
    expect(await sim.tap('phone', 10, 20), isTrue);
    expect(await sim.tap('phone', 0, 0), isFalse, reason: 'the simulator refused it');
    final all = await Future.wait([for (var i = 1; i < 6; i++) sim.tap('phone', i * 10.0, 5)]);
    expect(all, everyElement(isTrue));
    expect(await sim.text('phone', 'Hi!'), isTrue);
    expect(starts.readAsLinesSync(), hasLength(1), reason: 'one connection, kept');
    final xs = [
      for (final l in seen.readAsLinesSync())
        (jsonDecode(l) as Map)['x'] ?? (jsonDecode(l) as Map)['text'],
    ];
    expect(xs, [10, 0, 10, 20, 30, 40, 50, 'Hi!']);
  });

  test('says when the helper cannot run, so the slower way is used', () async {
    final sim = input(script('echo ok', start: 'echo "error: no simulator" ; exit 1'));
    addTearDown(sim.dispose);
    expect(await sim.tap('phone', 1, 1), isNull);
  });

  test('a helper that will not start is not tried again for a minute', () async {
    final marker = File('${dir.path}/starts');
    final sim = input(script('echo ok', start: 'echo x >> ${marker.path}; exit 1'));
    addTearDown(sim.dispose);
    expect(await sim.tap('phone', 1, 1), isNull);
    expect(await sim.home('phone'), isNull);
    expect(marker.readAsLinesSync(), hasLength(1));
  });

  test('a helper that ends is started again for the next action', () async {
    final marker = File('${dir.path}/starts');
    // Answers once, then ends.
    final sim = input(script('echo ok; exit 0', start: 'echo x >> ${marker.path}; echo ready'));
    addTearDown(sim.dispose);
    expect(await sim.tap('phone', 1, 1), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(await sim.tap('phone', 1, 1), isTrue);
    expect(marker.readAsLinesSync(), hasLength(2));
  });

  test('without AXe there is nothing to run it against', () async {
    final sim = SimInput(
      helper: () async => script('echo ok'),
      appData: () async => Directory('${dir.path}/data'),
      axe: () async => null,
    );
    expect(await sim.tap('phone', 1, 1), isNull);
  });

  test('a changed helper replaces the copy from before', () async {
    final first = input(script('echo ok'));
    expect(await first.tap('phone', 1, 1), isTrue);
    first.dispose();
    final second = input(script('echo "error: new"'));
    addTearDown(second.dispose);
    expect(await second.tap('phone', 1, 1), isFalse);
    expect(File('${dir.path}/data/bin/sim_input').readAsStringSync(), contains('new'));
  });
}
