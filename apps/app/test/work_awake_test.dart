import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/conversation_repository.dart';
import 'package:helmy/data/services/work_awake.dart';

/// A stand-in program: running until killed.
class _Held implements Process {
  final _done = Completer<int>();
  bool killed = false;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    if (!_done.isCompleted) _done.complete(0);
    return true;
  }

  @override
  Future<int> get exitCode => _done.future;
  @override
  int get pid => 1;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
}

class _Chats extends ConversationRepository {
  bool busy = false;
  @override
  bool get anyBusy => busy;
  void set(bool b) {
    busy = b;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Chats chats;
  late List<(String, List<String>)> started;
  late List<_Held> held;
  var on = true;

  WorkAwake make(String os) => WorkAwake(
    chats,
    enabled: () => on,
    os: os,
    self: 4242,
    linger: const Duration(milliseconds: 50),
    start: (exe, args) async {
      started.add((exe, args));
      final p = _Held();
      held.add(p);
      return p;
    },
  );

  setUp(() {
    chats = _Chats();
    started = [];
    held = [];
    on = true;
  });

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 120));

  test('held while a chat works, let go a little after it stops', () async {
    final awake = make('macos');
    addTearDown(awake.dispose);
    chats.set(true);
    await settle();
    expect(awake.holding, isTrue);
    expect(started.single.$1, '/usr/bin/caffeinate');
    expect(started.single.$2, ['-i', '-w', '4242']);

    // A pause between turns: still held.
    chats.set(false);
    chats.set(true);
    await settle();
    expect(started, hasLength(1));
    expect(held.single.killed, isFalse);

    chats.set(false);
    await settle();
    expect(awake.holding, isFalse);
    expect(held.single.killed, isTrue);
  });

  test('turned off in Settings: let go at once, and not held again', () async {
    final awake = make('macos');
    addTearDown(awake.dispose);
    chats.set(true);
    await settle();
    on = false;
    awake.check();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(held.single.killed, isTrue);
    chats.set(true);
    await settle();
    expect(started, hasLength(1));
  });

  test('every desktop has its way, each ending with Helmy', () {
    final linux = make('linux').command!;
    expect(linux.$1, 'systemd-inhibit');
    expect(linux.$2, [
      '--what=idle:sleep',
      '--who=Helmy',
      '--why=A chat is working',
      '--mode=block',
      'tail',
      '--pid=4242',
      '-f',
      '/dev/null',
    ]);
    final windows = make('windows').command!;
    expect(windows.$1, 'powershell');
    final encoded = windows.$2.last;
    final bytes = base64.decode(encoded);
    final script = String.fromCharCodes([
      for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
    ]);
    expect(script, WorkAwake.windowsScript(4242));
    expect(script, contains('SetThreadExecutionState([uint32]"0x80000001")'));
    expect(script, contains('Get-Process -Id 4242'));
  });

  test('where it cannot, it says so', () async {
    final awake = WorkAwake(
      chats,
      enabled: () => true,
      os: 'linux',
      self: 1,
      start: (_, _) async => null,
    );
    addTearDown(awake.dispose);
    chats.set(true);
    await settle();
    expect(awake.holding, isFalse);
    expect(awake.trouble, contains('systemd-inhibit'));
  });
}
