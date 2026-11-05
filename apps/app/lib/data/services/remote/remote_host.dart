import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../domain/models/settings.dart';
import '../../repositories/settings_repository.dart';
import 'remote_crypto.dart';
import 'remote_server.dart';

/// Keeps [RemoteServer] running while settings say a phone may reach Helmy,
/// and says how to pair: the link a phone reads from the QR code.
class RemoteHost extends ChangeNotifier {
  RemoteHost(this._server, this._settings) {
    _server
      ..keyOf = _keyOf
      ..onHello = _hello;
    _settings.addListener(_apply);
    unawaited(_apply());
  }

  String? _keyOf(String device) =>
      _settings.settings.phones.where((p) => p.id == device).firstOrNull?.key;

  /// The phones paired by their own keys, most recently seen first.
  List<PairedPhone> get phones => [
    for (final p in _settings.settings.phones)
      if (p.pairedAt != null) p,
  ]..sort((a, b) => (b.lastSeen ?? b.pairedAt!).compareTo(a.lastSeen ?? a.pairedAt!));

  /// Whether phone [id] is connected now.
  bool isConnected(String id) => _server.connectedDevices.contains(id);

  /// Phones connected that were paired before phones had keys of their own.
  int get olderConnected => _server.connectedDevices.where((d) => d == null).length;

  /// A phone said hello: the first time, it is paired, by the name it gives,
  /// and the next phone gets a code of its own.
  Future<void> _hello(String device, String name) async {
    final s = _settings.settings;
    final now = DateTime.now();
    await _settings.save(
      s.copyWith(
        phones: [
          for (final p in s.phones)
            if (p.id == device)
              p.copyWith(
                name: p.name.isEmpty && name.isNotEmpty ? name : null,
                pairedAt: p.pairedAt ?? now,
                lastSeen: now,
              )
            else
              p,
        ],
      ),
    );
    notifyListeners();
  }

  /// Turns phone [id] away, alone: its key goes, so it is refused from now
  /// on, and it is disconnected.
  Future<void> unpair(String id) async {
    final s = _settings.settings;
    await _settings.save(
      s.copyWith(
        phones: [
          for (final p in s.phones)
            if (p.id != id) p,
        ],
      ),
    );
    await _server.drop(id);
    notifyListeners();
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
      // A code of its own for the next phone to pair: one at a time.
      var pending = s.phones.where((p) => p.pairedAt == null).firstOrNull;
      if (pending == null) {
        pending = PairedPhone(id: Pairing.newDevice(), key: Pairing.newKey());
        await _settings.save(_settings.settings.copyWith(phones: [...s.phones, pending]));
      }
      if (_runningWith == key && _server.running && pairing?.device == pending.id) return;
      if (_runningWith == key && _server.running) {
        pairing = Pairing(
          hosts: pairing?.hosts ?? await RemoteServer.addresses(),
          port: _server.port,
          key: pending.key,
          name: Platform.localHostname.replaceAll(RegExp(r'\.local$'), ''),
          device: pending.id,
        );
        notifyListeners();
        return;
      }
      try {
        await _server.start(key);
        _runningWith = key;
        trouble = null;
        pairing = Pairing(
          hosts: await RemoteServer.addresses(),
          port: _server.port,
          key: pending.key,
          name: Platform.localHostname.replaceAll(RegExp(r'\.local$'), ''),
          device: pending.id,
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

  /// A new key, and every phone forgotten: each has to pair again.
  Future<void> pairAgain() async {
    for (final p in _settings.settings.phones) {
      await _server.drop(p.id);
    }
    await _settings.save(
      _settings.settings.copyWith(remoteKey: Pairing.newKey(), phones: const []),
    );
  }

  @override
  void dispose() {
    _settings.removeListener(_apply);
    unawaited(_server.stop());
    super.dispose();
  }
}
