import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;

import '../../../data/services/devices.dart';
import '../../../domain/device_outline.dart';
import '../../../domain/device_marks.dart';

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

  /// How much of AXe has downloaded (0 to 1), while Homebrew says.
  double? installShare;

  /// Why the screen is not showing, when it is not.
  String? trouble;

  Timer? _poll;
  StreamSubscription<Uint8List>? _stream;
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
      // Started, an Android virtual device has the running emulator's id.
      device =
          devices.where((x) => x.id == d.id).firstOrNull ??
          devices.where((x) => x.booted && x.name == d.name && x.ios == d.ios).firstOrNull ??
          d;
    }
    if (d.ios) dark = await _devices.isDark(device!) ?? dark;
    _poll?.cancel();
    await _stream?.cancel();
    _stream = null;
    // A stream of frames where the device gives one; else a picture asked
    // for four times a second.
    final frames = await _devices.stream(device!);
    if (frames != null) {
      // One picture now: a stream may wait for the screen to change.
      unawaited(_read());
      _stream = frames.listen((f) {
        screen = f;
        trouble = null;
        _changed();
      });
      return;
    }
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

  // Keys typed on the keyboard straight onto the screen, sent in order: each
  // goes as soon as the one before has landed, and keys typed while a send is
  // on its way go together in the next. Where sending is fast that is key by
  // key; where it is slow, they gather by themselves.
  final _keys = StringBuffer();
  Future<void> _sending = Future.value();

  void _queue(Future<void> Function() send) {
    _sending = _sending.then((_) => send()).catchError((Object _) {});
  }

  void _flush() {
    _queue(() async {
      if (_keys.isEmpty) return;
      final text = _keys.toString();
      _keys.clear();
      await type(text);
    });
  }

  /// Return or Backspace pressed onto the screen, after what was typed.
  Future<void> press(String key) async {
    if (device == null || !canTouch) return;
    final d = device!;
    _flush();
    _queue(() async {
      await _devices.keyPress(d, key);
    });
    await _sending;
  }

  /// A key typed onto the screen.
  void key(String text) {
    if (device == null || !canTouch) return;
    final idle = _keys.isEmpty;
    _keys.write(text);
    // One send queued for whatever gathers; more keys join it.
    if (idle) _flush();
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
    final ok = await _devices.installIosInput(
      progress: (step, share) {
        // Homebrew's own figures; a step without one says only the step.
        doing = share == null ? '$step…' : '$step… ${(share * 100).round()}%';
        installShare = share;
        _changed();
      },
    );
    installShare = null;
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
    unawaited(_stream?.cancel());
    _stream = null;
  }

  // The device's own settings (T3 Code's device tools): each true when it
  // took, so the panel can say when it did not.

  DeviceText? textSize;
  bool cleanStatusBar = false;

  /// Reads the settings the menu shows ticked.
  Future<void> readSettings() async {
    final d = device;
    if (d == null) return;
    textSize = await _devices.textSizeOf(d);
    notifyListeners();
  }

  Future<bool> setTextSize(DeviceText size) async {
    final d = device;
    if (d == null) return false;
    final ok = await _devices.textSize(d, size);
    if (ok) textSize = size;
    notifyListeners();
    return ok;
  }

  Future<bool> setLocation(double? lat, double? lon) async {
    final d = device;
    return d != null && await _devices.location(d, lat: lat, lon: lon);
  }

  Future<bool> openLink(String url) async {
    final d = device;
    return d != null && await _devices.openUrl(d, url);
  }

  Future<bool> toggleStatusBar() async {
    final d = device;
    if (d == null) return false;
    final ok = await _devices.cleanStatusBar(d, !cleanStatusBar);
    if (ok) cleanStatusBar = !cleanStatusBar;
    notifyListeners();
    return ok;
  }

  Future<bool> resetPermissions() async {
    final d = device;
    return d != null && await _devices.resetPermissions(d);
  }

  Future<bool> push(String bundle, String payload) async {
    final d = device;
    return d != null && await _devices.push(d, bundle, payload);
  }

  // The screen in 3D: its elements stacked over it by their depth, as the
  // screen's accessibility tree has them.

  bool threeD = false;

  /// The elements, read when the view opened; null while reading.
  List<ScreenElement>? layers;

  Future<void> toggle3D() async {
    threeD = !threeD;
    layers = null;
    notifyListeners();
    final d = device;
    if (!threeD || d == null) return;
    final raw = await _devices.describe(d);
    if (!threeD || _closed) return;
    layers = raw == null ? const [] : (d.ios ? iosElements(raw) : androidElements(raw));
    notifyListeners();
  }

  // Marking the screen for the agent, as pages are marked: the picture held
  // still, boxes drawn on it, each named by what is under it.

  bool marking = false;
  final marks = <DeviceMark>[];
  List<ScreenElement> _markElements = const [];

  /// Holds the picture still and reads what is on it, to name the marks.
  Future<void> startMarking() async {
    if (screen == null || device == null) return;
    pause();
    marking = true;
    marks.clear();
    notifyListeners();
    final d = device!;
    final raw = await _devices.describe(d);
    _markElements = raw == null ? const [] : (d.ios ? iosElements(raw) : androidElements(raw));
  }

  /// A box drawn at [left], [top], [width], [height] (shares of the screen).
  void addMark(double left, double top, double width, double height, Size picture) {
    final ios = device?.ios ?? false;
    final unitsWide = ios && _markElements.isNotEmpty
        ? _markElements.map((e) => e.x + e.width).reduce((a, b) => a > b ? a : b)
        : picture.width;
    final unitsHigh = unitsWide * picture.height / picture.width;
    marks.add((
      n: marks.length + 1,
      left: left,
      top: top,
      width: width,
      height: height,
      note: '',
      element: elementUnder(
        _markElements,
        left: left,
        top: top,
        width: width,
        height: height,
        unitsWide: unitsWide,
        unitsHigh: unitsHigh,
      ),
    ));
    notifyListeners();
  }

  void noteMark(int n, String note) {
    final i = marks.indexWhere((m) => m.n == n);
    if (i < 0) return;
    final m = marks[i];
    marks[i] = (
      n: m.n,
      left: m.left,
      top: m.top,
      width: m.width,
      height: m.height,
      note: note,
      element: m.element,
    );
  }

  void removeLastMark() {
    if (marks.isNotEmpty) marks.removeLast();
    notifyListeners();
  }

  /// Back to the live screen, the marks put away.
  void stopMarking() {
    marking = false;
    marks.clear();
    notifyListeners();
    unawaited(_ready());
  }

  /// The picture with its marks drawn on it, as PNG, and the marks as text.
  Future<(Uint8List, String)?> markedPicture() async {
    final bytes = screen, d = device;
    if (bytes == null || d == null || marks.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final w = image.width.toDouble(), h = image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..drawImage(image, ui.Offset.zero, ui.Paint());
    final stroke = w / 120;
    const red = ui.Color(0xFFFF3B30);
    for (final m in marks) {
      final rect = ui.Rect.fromLTWH(m.left * w, m.top * h, m.width * w, m.height * h);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(stroke * 2)),
        ui.Paint()
          ..color = red
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      // Its number, in a badge at its corner.
      final r = stroke * 5;
      final center = ui.Offset(rect.left, rect.top);
      canvas.drawCircle(center, r, ui.Paint()..color = red);
      final builder =
          ui.ParagraphBuilder(ui.ParagraphStyle(textAlign: ui.TextAlign.center, fontSize: r * 1.2))
            ..pushStyle(
              ui.TextStyle(color: const ui.Color(0xFFFFFFFF), fontWeight: ui.FontWeight.w700),
            )
            ..addText('${m.n}');
      final p = builder.build()..layout(ui.ParagraphConstraints(width: r * 2));
      canvas.drawParagraph(p, ui.Offset(center.dx - r, center.dy - p.height / 2));
    }
    final picture = await recorder.endRecording().toImage(image.width, image.height);
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) return null;
    return (
      png.buffer.asUint8List(),
      deviceMarksMarkdown(d.name, marks, picture: 'the attached picture'),
    );
  }

  // The device's logs, under its screen while asked for: the same lines its
  // agent reads, refreshed while they show.

  bool logsOpen = false;

  /// The latest lines; null while the first are read.
  List<String>? logLines;

  /// Only lines holding this.
  String logFind = '';
  Timer? _logTimer;

  void toggleLogs() {
    logsOpen = !logsOpen;
    _logTimer?.cancel();
    if (logsOpen) {
      unawaited(readLogs());
      _logTimer = Timer.periodic(const Duration(seconds: 3), (_) => unawaited(readLogs()));
    }
    notifyListeners();
  }

  void findInLogs(String words) {
    logFind = words;
    unawaited(readLogs());
  }

  bool _readingLogs = false;

  Future<void> readLogs() async {
    final d = device;
    if (d == null || _readingLogs || _closed) return;
    _readingLogs = true;
    try {
      final lines = await _devices.logs(d, find: logFind.trim().isEmpty ? null : logFind.trim());
      if (_closed) return;
      logLines = lines ?? const [];
      notifyListeners();
    } finally {
      _readingLogs = false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _logTimer?.cancel();
    _poll?.cancel();
    unawaited(_stream?.cancel());
    super.dispose();
  }
}
