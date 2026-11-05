import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/mac/mac_actions.dart';
import 'package:helmy/data/services/mac/mac_control.dart';
import 'package:helmy/data/services/mac/mac_tools.dart';

class FakeNative implements MacNative {
  final inputs = <Map<String, Object?>>[];
  final marks = <String?>[];
  String? says;
  bool record = true;
  void Function()? stopper;

  @override
  set onStop(void Function()? f) => stopper = f;

  @override
  Future<MacShot> shot({int maxWidth = 1280, double quality = .7}) async {
    if (!record) throw const MacUseTrouble('record', 'Screen Recording is not allowed.');
    return (jpeg: Uint8List.fromList([1, 2, 3]), width: maxWidth, height: maxWidth * 5 ~/ 8);
  }

  @override
  Future<String?> input(Map<String, Object?> args) async {
    inputs.add(args);
    return says;
  }

  @override
  Future<void> mark(String? text) async => marks.add(text);
}

void main() {
  late FakeNative native;
  late MacControl control;
  late List<String?> shown;

  setUp(() {
    native = FakeNative();
    shown = [];
    control = MacControl(native, idle: const Duration(milliseconds: 50))
      ..show = (s) {
        shown.add(s);
        return true;
      };
  });

  test('the first action in a chat waits for the yes, then the next ones do not', () async {
    final first = control.act('a', {'kind': 'click', 'x': 640, 'y': 400});
    await pumpEventQueue();
    expect(control.asking('a'), isTrue);
    expect(native.inputs, isEmpty);
    control.answer('a', true);
    await first;
    expect(native.inputs.single['agent'], isTrue);
    // Pixels of the agent's picture become shares of the screen.
    expect(native.inputs.single['x'], 0.5);
    expect(native.inputs.single['y'], 0.5);
    expect(control.using, 'a');
    expect(native.marks.last, 'Helmy is using this Mac');

    await control.act('a', {'kind': 'text', 'text': 'hi'});
    expect(native.inputs, hasLength(2));
    // Another chat asks for itself.
    unawaited(control.act('b', {'kind': 'text', 'text': 'x'}).catchError((_) {}));
    await pumpEventQueue();
    expect(control.asking('b'), isTrue);
  });

  test('a no ends the action with what to tell the user', () async {
    final first = control.act('a', {'kind': 'click', 'x': 1, 'y': 1});
    await pumpEventQueue();
    control.answer('a', false);
    await expectLater(
      first,
      throwsA(isA<MacUseTrouble>().having((t) => t.code, 'code', 'declined')),
    );
    expect(native.inputs, isEmpty);
  });

  test('a chat not on screen cannot be asked', () async {
    control.show = (_) => false;
    await expectLater(
      control.act('a', {'kind': 'click', 'x': 1, 'y': 1}),
      throwsA(isA<MacUseTrouble>().having((t) => t.code, 'code', 'unseen')),
    );
    expect(control.asking('a'), isFalse);
  });

  test('the person using the Mac stops the agent', () async {
    control.answer('a', true);
    native.says = 'person';
    await expectLater(
      control.act('a', {'kind': 'click', 'x': 1, 'y': 1}),
      throwsA(isA<MacUseTrouble>().having((t) => t.code, 'code', 'person')),
    );
  });

  test("Stop on the bar takes the Mac back from every chat and hides the bar", () async {
    control.answer('a', true);
    await control.act('a', {'kind': 'click', 'x': 1, 'y': 1});
    final waiting = control.act('b', {'kind': 'click', 'x': 1, 'y': 1});
    await pumpEventQueue();
    native.stopper!();
    await expectLater(waiting, throwsA(isA<MacUseTrouble>()));
    expect(control.allowed('a'), isFalse);
    expect(control.using, isNull);
    expect(native.marks.last, isNull);
  });

  test('the bar goes once the agent has been idle a while', () async {
    control.answer('a', true);
    await control.act('a', {'kind': 'click', 'x': 1, 'y': 1});
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(control.using, isNull);
    expect(native.marks.last, isNull);
    // Still allowed: only the bar went.
    expect(control.allowed('a'), isTrue);
  });

  group('tools', () {
    late MacTools tools;
    setUp(() => tools = MacTools(MacActions(), control: control));

    test('mac_see gives the picture and its size, without asking', () async {
      final r = await tools.call('mac_see', {}, 'a');
      final content = r['content']! as List;
      expect(r['isError'], isFalse);
      expect((content.first as Map)['text'], contains('1280 by 800'));
      expect((content.last as Map)['type'], 'image');
      expect(control.asking('a'), isFalse);
      expect(shown, ['a']);
    });

    test('mac_see without Screen Recording links the setting', () async {
      native.record = false;
      final r = await tools.call('mac_see', {}, 'a');
      expect(r['isError'], isTrue);
      expect('${r['content']}', contains('helmy://fix/allow-screen-recording'));
    });

    test('mac_drag presses, moves through the way and lets go', () async {
      control.answer('a', true);
      await tools.call('mac_see', {}, 'a');
      final r = await tools.call('mac_drag', {'x': 0, 'y': 0, 'to_x': 1280, 'to_y': 800}, 'a');
      expect(r['isError'], isFalse);
      expect(native.inputs.first['kind'], 'down');
      expect(native.inputs.last, containsPair('kind', 'up'));
      expect(native.inputs.last['x'], 1.0);
      expect(native.inputs.where((i) => i['kind'] == 'drag'), hasLength(8));
    });

    test('the person taking over midway through a drag lets the button go', () async {
      // The third move meets the person.
      final fake = _Interrupting(after: 3);
      final t = MacTools(
        MacActions(),
        control: MacControl(fake)
          ..answer('a', true)
          ..show = (_) => true,
      );
      final r = await t.call('mac_drag', {'x': 0, 'y': 0, 'to_x': 100, 'to_y': 100}, 'a');
      expect(r['isError'], isTrue);
      expect(fake.inputs.last, containsPair('kind', 'up'));
      expect(fake.inputs.last['quiet'], 0);
    });

    test('mac_scroll down is the wheel turned toward the person', () async {
      control.answer('a', true);
      await tools.call('mac_scroll', {'x': 10, 'y': 10, 'down': 3}, 'a');
      expect(native.inputs.single['dy'], -30);
    });

    test('mac_key passes the key and the held mods', () async {
      control.answer('a', true);
      await tools.call('mac_key', {
        'key': 'c',
        'mods': ['cmd'],
      }, 'a');
      expect(native.inputs.single, containsPair('key', 'c'));
      expect(native.inputs.single['mods'], ['cmd']);
    });
  });
}

class _Interrupting extends FakeNative {
  _Interrupting({required this.after});
  final int after;

  @override
  Future<String?> input(Map<String, Object?> args) async {
    inputs.add(args);
    if (args['quiet'] == 0) return null;
    return inputs.length > after ? 'person' : null;
  }
}
