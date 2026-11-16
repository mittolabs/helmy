import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../domain/models/settings.dart';
import '../../repositories/settings_repository.dart';
import 'relay_host.dart';
import 'remote_crypto.dart';
import 'remote_server.dart';

/// Keeps [RemoteServer] running while settings say a phone may reach Helmy,
/// and says how to pair: the link a phone reads from the QR code.
class RemoteHost extends ChangeNotifier {
  RemoteHost(this._server, this._settings, {this.relayUrl = Pairing.defaultRelay}) {
    _server
      ..keyOf = _keyOf
      ..onHello = _hello
      ..secretOf = _secretOf
      ..onExchanged = _exchanged;
    _settings.addListener(_apply);
    // A code shown too long is replaced: checked each minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(_apply()));
    // After it is made, not while: applying can save settings, and saving
    // tells their listeners, which must not happen in the middle of building.
    unawaited(Future(_apply));
  }

  /// The relay this computer keeps a line to (Helmy Connect).
  final String relayUrl;

  /// The line to the relay, while phones may reach Helmy from anywhere.
  RelayHost? relay;

  late final Timer _tick;

  /// How long a code shown can be used for.
  static const codeLasts = Duration(minutes: 15);

  String? _keyOf(String device) {
    final key = _settings.settings.phones.where((p) => p.id == device).firstOrNull?.key;
    return key == null || key.isEmpty ? null : key;
  }

  /// The code waiting for a phone, if it is still good.
  PairedPhone? get _pending => _settings.settings.phones
      .where(
        (p) =>
            p.pairedAt == null &&
            p.secret != null &&
            DateTime.now().difference(p.madeAt ?? DateTime(0)) < codeLasts,
      )
      .firstOrNull;

  String? _secretOf(String device) {
    final p = _pending;
    return p?.id == device ? p!.secret : null;
  }

  /// Phone [device] used its code: paired with the key agreed on, the code
  /// spent, and the next phone gets a new one.
  Future<void> _exchanged(String device, String key) async {
    final s = _settings.settings;
    final now = DateTime.now();
    await _settings.save(
      s.copyWith(
        phones: [
          for (final p in s.phones)
            if (p.id == device) p.exchanged(key, now) else p,
        ],
      ),
    );
    notifyListeners();
  }

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
                // A name it gives replaces none, or the "localhost" older
                // builds gave.
                name: (p.name.isEmpty || p.name == 'localhost') && name.isNotEmpty ? name : null,
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

  bool _disposed = false;

  Future<void> _apply() async {
    if (_disposed) return;
    // A change while one is being applied: applied after it.
    if (_applying) {
      _again = true;
      return;
    }
    _applying = true;
    try {
      final s = _settings.settings;
      if (!s.remoteScreen) await _server.endScreen();
      if (!s.remoteOn || !s.remoteAnywhere) await _stopRelay();
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
      // This computer's own key on the relay, the first time.
      var seed = _settings.settings.relayKey;
      if (seed.isEmpty) {
        seed = RelayHost.newSeed();
        await _settings.save(_settings.settings.copyWith(relayKey: seed));
      }
      // A one-time code for the next phone to pair: one at a time, good for
      // a while. Unused ones go: one too old, or one from before codes
      // were single-use (its key in the code).
      var pending = _pending;
      if (pending == null) {
        pending = PairedPhone(
          id: Pairing.newDevice(),
          key: '',
          secret: Pairing.newKey(),
          madeAt: DateTime.now(),
        );
        final now = _settings.settings;
        await _settings.save(
          now.copyWith(
            phones: [
              for (final p in now.phones)
                if (p.pairedAt != null) p,
              pending,
            ],
          ),
        );
      }
      final anywhere = _settings.settings.remoteAnywhere;
      final relayId = anywhere ? await RelayHost.idFor(seed) : null;
      if (_runningWith == key &&
          _server.running &&
          pairing?.device == pending.id &&
          pairing?.relay == relayId) {
        return;
      }
      if (_runningWith == key && _server.running) {
        if (anywhere) await _startRelay(seed);
        pairing = _offer(pairing?.hosts ?? await _hosts(), pending, relayId);
        notifyListeners();
        return;
      }
      try {
        await _server.start(key);
        _runningWith = key;
        trouble = null;
        if (anywhere) await _startRelay(seed);
        pairing = _offer(await _hosts(), pending, relayId);
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

  /// The code a phone pairs with: [pending]'s one-time secret, where to
  /// find this computer, and its id on the relay when it is reachable there.
  Pairing _offer(List<String> hosts, PairedPhone pending, String? relayId) => Pairing(
    hosts: hosts,
    port: _server.port,
    key: '',
    secret: pending.secret,
    name: Platform.localHostname.replaceAll(RegExp(r'\.local$'), ''),
    device: pending.id,
    relay: relayId,
    relayUrl: relayUrl,
  );

  Future<void> _startRelay(String seed) async {
    if (relay?.seed == seed) return;
    await _stopRelay();
    final r = relay = RelayHost(_server, seed: seed, url: relayUrl)..addListener(notifyListeners);
    unawaited(r.start());
  }

  Future<void> _stopRelay() async {
    final r = relay;
    if (r == null) return;
    relay = null;
    r.removeListener(notifyListeners);
    await r.stop();
    r.dispose();
    if (!_disposed) notifyListeners();
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
    _disposed = true;
    _tick.cancel();
    _settings.removeListener(_apply);
    unawaited(_stopRelay());
    unawaited(_server.stop());
    super.dispose();
  }

  /// Where a paired device looks for this computer: its addresses, then
  /// this computer itself, for Chrome running here (with no network, too).
  static Future<List<String>> _hosts() async => [...await RemoteServer.addresses(), '127.0.0.1'];
}
