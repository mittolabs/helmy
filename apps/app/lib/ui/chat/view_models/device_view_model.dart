import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;

import '../../../data/services/devices.dart';

/// The Device panel's state: which simulator or emulator, its screen kept
/// fresh while the panel shows, and what a tap or a key does to it.
class DeviceViewModel extends ChangeNotifier {
  DeviceViewModel(this._devices);
  final DeviceService _devices;

  List<Device> devices = const [];
  Device? device;
  Uint8List? screen;

  /// Whether taps and typing reach this device; for an iOS simulator, only
  /// with AXe installed.
  bool canTouch = true;

  /// What is happening, when something is (starting, installing).
  String? doing;

  /// Why the screen is not showing, when it is not.
  String? trouble;

  Timer? _poll;
  bool _reading = false;
  bool _closed = false;

  /// Lists the devices and picks one for the user: one already running,
  /// an iPhone before an iPad or an emulator.
  Future<void> open() async {
    devices = await _devices.list();
    device ??=
        devices.where((d) => d.booted).firstOrNull ??
        devices.where((d) => d.ios && d.name.startsWith('iPhone')).firstOrNull ??
        devices.firstOrNull;
    trouble = devices.isEmpty
        ? 'No simulator or emulator is installed. Xcode brings iOS simulators; Android Studio, emulators.'
        : null;
    await _ready();
  }

  Future<void> choose(Device d) async {
    device = d;
    screen = null;
    await _ready();
  }

  /// Starts the chosen device if it is not running, then keeps its screen fresh.
  Future<void> _ready() async {
    final d = device;
    if (d == null || _closed) return _changed();
    canTouch = !d.ios || await _devices.iosInput();
    if (!d.booted) {
      doing = 'Starting ${d.name}…';
      _changed();
      final ok = await _devices.boot(d);
      doing = null;
      if (!ok) {
        trouble = "${d.name} didn't start.";
        return _changed();
      }
      devices = await _devices.list();
      device = devices.where((x) => x.id == d.id).firstOrNull ?? d;
    }
    if (d.ios) dark = await _devices.isDark(device!) ?? dark;
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) => unawaited(_read()));
    await _read();
  }

  Future<void> _read() async {
    final d = device;
    if (d == null || _reading || _closed) return;
    _reading = true;
    final bytes = await _devices.screen(d);
    _reading = false;
    if (bytes == null) {
      trouble ??= "${d.name}'s screen can't be read right now.";
    } else {
      screen = Uint8List.fromList(bytes);
      trouble = null;
    }
    _changed();
  }

  /// The device's own coordinates for a share (0 to 1) of the picture: iOS
  /// simulators take points, the picture is in pixels at the screen's scale.
  (double, double) _at(double fx, double fy, Size picture) {
    final d = device!;
    final scale = d.ios ? (picture.width >= 1000 ? 3.0 : 2.0) : 1.0;
    return (fx * picture.width / scale, fy * picture.height / scale);
  }

  Future<void> tap(double fx, double fy, Size picture) async {
    if (device == null || !canTouch) return;
    final (x, y) = _at(fx, fy, picture);
    await _devices.tap(device!, x, y);
    unawaited(_read());
  }

  Future<void> swipe((double, double) from, (double, double) to, Size picture) async {
    if (device == null || !canTouch) return;
    await _devices.swipe(device!, _at(from.$1, from.$2, picture), _at(to.$1, to.$2, picture));
    unawaited(_read());
  }

  Future<void> type(String text) async {
    if (device == null || !canTouch || text.isEmpty) return;
    await _devices.type(device!, text);
    unawaited(_read());
  }

  Future<void> home() async {
    if (device == null || !canTouch) return;
    await _devices.home(device!);
    unawaited(_read());
  }

  /// Whether the device is in dark mode, as it last said.
  bool dark = false;

  Future<void> toggleAppearance() async {
    if (device == null) return;
    dark = !dark;
    await _devices.appearance(device!, dark: dark);
    _changed();
    unawaited(_read());
  }

  /// Asks again whether taps and typing reach the device (after an install).
  Future<void> checkTouch() async {
    final d = device;
    if (d == null) return;
    canTouch = !d.ios || await _devices.iosInput();
    _changed();
  }

  /// Installs what carries taps and typing to iOS simulators.
  Future<void> installTouch() async {
    doing = 'Installing…';
    _changed();
    final ok = await _devices.installIosInput();
    doing = null;
    canTouch = ok;
    if (!ok) trouble = "It didn't install. Homebrew is needed for it: brew.sh.";
    _changed();
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  /// Stops reading the screen (the panel closed).
  void pause() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _closed = true;
    _poll?.cancel();
    super.dispose();
  }
}
