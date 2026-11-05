import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One picture of this Mac's screen, and its size in pixels.
typedef MacShot = ({Uint8List jpeg, int width, int height});

/// What [MacControl] needs of the Mac itself: injectable for tests.
abstract class MacNative {
  /// A picture of the main screen, at most [maxWidth] wide. Throws
  /// [MacUseTrouble] with "record" when Screen Recording is not allowed.
  Future<MacShot> shot({int maxWidth = 1280, double quality = .7});

  /// Posts input, as the screen share's `input` takes it. Null when done;
  /// "accessibility", "person" or what went wrong otherwise.
  Future<String?> input(Map<String, Object?> args);

  /// Shows the "Helmy is using this Mac" bar, or hides it with null.
  Future<void> mark(String? text);

  /// Called when the bar's Stop is pressed.
  set onStop(void Function()? f);
}

class MacUseTrouble implements Exception {
  const MacUseTrouble(this.code, this.message);

  /// "record", "accessibility", "person", "declined", "unseen" or "other".
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// Through `helmy/screen` in MainFlutterWindow.swift.
class ChannelMacNative implements MacNative {
  ChannelMacNative() {
    agentStopped = () => _onStop?.call();
  }

  static const _ch = MethodChannel('helmy/screen');

  /// Set by whoever handles the channel's calls from Swift (MacScreen).
  static void Function()? agentStopped;

  void Function()? _onStop;
  @override
  set onStop(void Function()? f) => _onStop = f;

  @override
  Future<MacShot> shot({int maxWidth = 1280, double quality = .7}) async {
    try {
      final r = await _ch.invokeMapMethod<String, Object?>('shot', {
        'maxWidth': maxWidth,
        'quality': quality,
      });
      return (
        jpeg: r!['data']! as Uint8List,
        width: r['width']! as int,
        height: r['height']! as int,
      );
    } on PlatformException catch (e) {
      throw MacUseTrouble(e.code == 'record' ? 'record' : 'other', e.message ?? '$e');
    } on MissingPluginException {
      throw const MacUseTrouble('other', 'This computer cannot show its screen.');
    }
  }

  @override
  Future<String?> input(Map<String, Object?> args) async {
    try {
      return await _ch.invokeMethod<String>('input', args);
    } on Object catch (e) {
      return '$e';
    }
  }

  @override
  Future<void> mark(String? text) async {
    try {
      await _ch.invokeMethod<void>('agentMark', {'text': text});
    } on Object {
      // No bar to show.
    }
  }
}

/// An agent using this Mac's screen, mouse and keyboard, and the person's
/// say over it: each chat asks once ([ask]); Stop on the bar or in the panel
/// takes it back from every chat ([stop]); and an action while the person is
/// using the Mac does nothing ("person").
class MacControl extends ChangeNotifier {
  MacControl(
    this._native, {
    this.idle = const Duration(seconds: 15),
    this.waitFor = const Duration(minutes: 5),
  }) {
    _native.onStop = stop;
  }

  final MacNative _native;

  /// How long the bar stays after an agent's last action.
  final Duration idle;

  /// How long an ask waits for the person.
  final Duration waitFor;

  /// Shows a chat's Device panel on This Mac; false when the chat is not on
  /// screen. Set once the browser host is ready.
  bool Function(String? session) show = (_) => false;

  final _allowed = <String>{};
  final _asking = <String, Completer<bool>>{};

  /// The chat whose agent used the Mac last, while the bar shows.
  String? using;
  Timer? _done;

  /// The agent's picture size, for its x and y: from its last [see].
  ({int width, int height})? _size;

  bool allowed(String session) => _allowed.contains(session);
  bool asking(String session) => _asking.containsKey(session);

  /// The person's answer to a chat's ask.
  void answer(String session, bool yes) {
    if (yes) _allowed.add(session);
    _asking.remove(session)?.complete(yes);
    notifyListeners();
  }

  /// Takes the Mac back from every chat: each asks again next time.
  void stop() {
    _allowed.clear();
    for (final c in _asking.values) {
      c.complete(false);
    }
    _asking.clear();
    _release();
  }

  void _release() {
    _done?.cancel();
    using = null;
    unawaited(_native.mark(null));
    notifyListeners();
  }

  /// Waits for the person to let [session]'s agent use the Mac, once per chat.
  Future<void> _permit(String session) async {
    if (_allowed.contains(session)) return;
    final asked = _asking[session] ??= Completer<bool>();
    notifyListeners();
    if (!show(session)) {
      _asking.remove(session);
      notifyListeners();
      throw const MacUseTrouble(
        'unseen',
        "Using this Mac's mouse and keyboard needs the user's yes, asked in this chat, and the "
            "chat isn't open on screen. Tell them to open it and ask you again.",
      );
    }
    final yes = await asked.future.timeout(
      waitFor,
      onTimeout: () {
        _asking.remove(session);
        notifyListeners();
        return false;
      },
    );
    if (!yes) {
      throw const MacUseTrouble(
        'declined',
        "The user didn't let you use this Mac's mouse and keyboard. Don't try again unless they "
            'ask you to.',
      );
    }
  }

  /// A picture of the screen for an agent; its x and y are in its pixels.
  Future<MacShot> see(String? session) async {
    show(session);
    final s = await _native.shot();
    _size = (width: s.width, height: s.height);
    return s;
  }

  /// A smaller picture, for the panel to show.
  Future<MacShot> look() => _native.shot(maxWidth: 960, quality: .6);

  /// Does [args] (the screen share's input, with x and y in the agent's
  /// picture pixels) for [session]'s agent, once the person allows it.
  Future<void> act(String session, Map<String, Object?> args) async {
    await _permit(session);
    if (_size == null) await see(session);
    final size = _size!;
    double? share(Object? v, int of) => v is num ? (v / of).clamp(0.0, 1.0).toDouble() : null;
    final said = await _native.input({
      ...args,
      'x': ?share(args['x'], size.width),
      'y': ?share(args['y'], size.height),
      'agent': true,
    });
    switch (said) {
      case null:
        _using(session);
      case 'accessibility':
        throw const MacUseTrouble(
          'accessibility',
          "Helmy needs the Accessibility permission to click and type on this Mac. Tell the user, "
              'and give them this link, which opens the setting: '
              '[Allow Accessibility](helmy://fix/allow-accessibility). Then try again once they have.',
        );
      case 'person':
        throw const MacUseTrouble(
          'person',
          'The user is using this Mac right now (they moved the mouse or typed in the last few '
              'seconds), so nothing was done. Stop here: tell them what you were doing and what is '
              'left, and carry on only when they say so.',
        );
      case final other:
        throw MacUseTrouble('other', "That didn't work on this Mac: $other.");
    }
  }

  void _using(String session) {
    if (using != session) {
      using = session;
      notifyListeners();
    }
    unawaited(_native.mark('Helmy is using this Mac'));
    _done?.cancel();
    _done = Timer(idle, _release);
  }

  @override
  void dispose() {
    _done?.cancel();
    stop();
    super.dispose();
  }
}
