import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../repositories/settings_repository.dart';
import 'remote_crypto.dart';
import 'remote_server.dart';

/// Keeps [RemoteServer] running while settings say a phone may reach Helmy,
/// and says how to pair: the link a phone reads from the QR code.
class RemoteHost extends ChangeNotifier {
  RemoteHost(this._server, this._settings) {
    _settings.addListener(_apply);
    unawaited(_apply());
  }

  final RemoteServer _server;
  final SettingsRepository _settings;

  /// The pairing a phone takes; null while off.
  Pairing? pairing;

  /// Why it could not start (the port taken, say); null when it runs or is off.
  String? trouble;

  int get connected => _server.connected;

  bool _applying = false, _again = false;
  String? _runningWith;

  Future<void> _apply() async {
    // A change while one is being applied: applied after it.
    if (_applying) {
      _again = true;
      return;
    }
    _applying = true;
    try {
      final s = _settings.settings;
      if (!s.remoteOn) {
        if (_server.running) await _server.stop();
        _runningWith = null;
        pairing = null;
        trouble = null;
        notifyListeners();
        return;
      }
      // The first time on: a key of its own, used at once.
      var key = s.remoteKey;
      if (key.isEmpty) {
        key = Pairing.newKey();
        await _settings.save(s.copyWith(remoteKey: key));
      }
      if (_runningWith == key && _server.running) return;
      try {
        await _server.start(key);
        _runningWith = key;
        trouble = null;
        pairing = Pairing(
          hosts: await RemoteServer.addresses(),
          port: _server.port,
          key: key,
          name: Platform.localHostname.replaceAll(RegExp(r'\.local$'), ''),
        );
      } on SocketException catch (e) {
        trouble =
            'Port ${_server.port} is taken by another app, so phones cannot reach Helmy. '
            'Quit that app, then turn this off and on. (${e.osError?.message ?? e.message})';
        pairing = null;
      }
      notifyListeners();
    } finally {
      _applying = false;
      if (_again) {
        _again = false;
        unawaited(_apply());
      }
    }
  }

  /// A new key: every phone paired before has to pair again.
  Future<void> pairAgain() async {
    await _settings.save(_settings.settings.copyWith(remoteKey: Pairing.newKey()));
  }

  @override
  void dispose() {
    _settings.removeListener(_apply);
    unawaited(_server.stop());
    super.dispose();
  }
}
