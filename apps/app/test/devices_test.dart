import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/devices.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/watch_service.dart';
import 'package:helmy/domain/helmy_voice.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';
import 'package:helmy/ui/chat/view_models/device_view_model.dart';

/// A PNG's first bytes: the signature and an IHDR of [w] by [h].
List<int> png(int w, int h) => [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, //
  w >> 24, w >> 16 & 255, w >> 8 & 255, w & 255, h >> 24, h >> 16 & 255, h >> 8 & 255, h & 255,
  8, 6, 0, 0, 0,
];

/// A JPEG's first bytes: an APP0 segment, then a baseline frame of [w] by [h].
List<int> jpeg(int w, int h) => [
  0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, //
  0xFF, 0xC0, 0, 11, 8, h >> 8, h & 255, w >> 8, w & 255, 1, 1, 0x11, 0,
];

/// Devices without Xcode or adb: one iPhone running, one iPad not.
class FakeDevices extends DeviceService {
  FakeDevices({this.input = true}) : super(CliLocator());
  bool input;
  final taps = <(double, double)>[];
  final booted = <String>[];

  @override
  Future<List<Device>> list() async => const [
    Device(id: 'phone', name: 'iPhone 17 Pro', ios: true, booted: true, runtime: 'iOS 26.5'),
    Device(id: 'pad', name: 'iPad Air', ios: true, booted: false, runtime: 'iOS 26.5'),
  ];

  @override
  Future<bool> boot(Device d) async {
    booted.add(d.id);
    return true;
  }

  @override
  Future<bool> iosInput() async => input;

  @override
  Future<List<int>?> screen(Device d) async => jpeg(1206, 2622);

  @override
  Future<bool> tap(Device d, double x, double y) async {
    taps.add((x, y));
    return true;
  }

  @override
  Future<bool?> isDark(Device d) async => true;

  // Pictures asked for, as where no stream is to be had.
  @override
  Future<Stream<Uint8List>?> stream(Device d) async => null;
}

void main() {
  test('a picture\'s size comes from its header', () {
    expect(imageSize(png(1080, 2400)), (1080, 2400));
    expect(imageSize(jpeg(1206, 2622)), (1206, 2622));
    expect(imageSize([1, 2, 3]), isNull);
  });

  test('a folder with an iOS or Android app is a mobile project', () async {
    final dir = await Directory.systemTemp.createTemp('mobile');
    addTearDown(() => dir.delete(recursive: true));
    expect(isMobileProject(dir.path), isFalse);
    Directory('${dir.path}/ios').createSync();
    expect(isMobileProject(dir.path), isTrue);

    final xcode = await Directory.systemTemp.createTemp('xcode');
    addTearDown(() => xcode.delete(recursive: true));
    Directory('${xcode.path}/App.xcodeproj').createSync();
    expect(isMobileProject(xcode.path), isTrue);
    expect(isMobileProject('${xcode.path}/missing'), isFalse);
  });

  test('the panel opens on the running device, in its own appearance', () async {
    final devices = FakeDevices();
    final vm = DeviceViewModel(devices);
    addTearDown(vm.dispose);
    await vm.open();
    vm.pause();
    expect(vm.device?.id, 'phone');
    expect(vm.dark, isTrue, reason: 'as the simulator says, not assumed');
    expect(vm.screen, isNotNull);

    // A click halfway across a 3x picture lands at the screen's middle, in points.
    await vm.tap(.5, .5, const .new(1206, 2622));
    vm.pause();
    expect(devices.taps.single, (201.0, 437.0));
  });

  test('without AXe, the screen shows but taps are not sent', () async {
    final devices = FakeDevices(input: false);
    final vm = DeviceViewModel(devices);
    addTearDown(vm.dispose);
    await vm.open();
    vm.pause();
    expect(vm.canTouch, isFalse);
    await vm.tap(.5, .5, const .new(1206, 2622));
    expect(devices.taps, isEmpty);
  });

  group('the device tools', () {
    Future<Map> call(HelmyTools tools, String name, [Map args = const {}]) async {
      final r = await tools.answer('tools/call', {'name': name, 'arguments': args});
      return r['result']! as Map;
    }

    String text(Map r) => (r['content'] as List).first['text'] as String;

    test('are listed and allowed without asking', () async {
      final tools = HelmyTools(WatchService(CliLocator()), FakeDevices());
      final listed = await tools.answer('tools/list', const {});
      final names = [for (final t in (listed['result']! as Map)['tools'] as List) t['name']];
      expect(names, containsAll(HelmyTools.deviceTools));
      expect(HelmyTools.claudeTools, contains('mcp__helmy__device_tap'));
      expect(toolLabel('mcp__helmy__device_tap'), 'Tapped the device');
    });

    test('give the screen with its size in points, and tap there', () async {
      final devices = FakeDevices();
      final tools = HelmyTools(WatchService(CliLocator()), devices);
      final list = await call(tools, 'device_list');
      expect(text(list), contains('phone: iPhone 17 Pro (iOS 26.5), running'));

      final screen = await call(tools, 'device_screen');
      expect(text(screen), contains('402 by 874 points'));
      final image = (screen['content'] as List)[1] as Map;
      expect(image['mimeType'], 'image/jpeg');
      expect(base64Decode(image['data'] as String), jpeg(1206, 2622));

      expect((await call(tools, 'device_tap', {'x': 201, 'y': 437}))['isError'], isFalse);
      expect(devices.taps.single, (201.0, 437.0));
    });

    test('start a device that is not running', () async {
      final devices = FakeDevices();
      final tools = HelmyTools(WatchService(CliLocator()), devices);
      await call(tools, 'device_screen', {'device': 'pad'});
      expect(devices.booted, ['pad']);
    });

    test('say what is missing for taps, with the link that installs it', () async {
      final tools = HelmyTools(WatchService(CliLocator()), FakeDevices(input: false));
      final r = await call(tools, 'device_tap', {'x': 1, 'y': 1});
      expect(r['isError'], isTrue);
      expect(text(r), contains('helmy://fix/install-device-input'));
    });

    test('show the device in the session panel, and say whether the user sees it', () async {
      final shownFor = <String?>[];
      final tools = HelmyTools(WatchService(CliLocator()), FakeDevices(), null, (s) {
        shownFor.add(s);
        return s == 'on-screen';
      });
      Future<Map> screen(String session) async =>
          (await tools.answer('tools/call', {
                'name': 'device_screen',
                'arguments': {},
              }, session: session))['result']!
              as Map;
      expect(text(await screen('on-screen')), contains('shows live in the Device panel'));
      expect(text(await screen('elsewhere')), contains('user does not see it'));
      expect(shownFor, ['on-screen', 'elsewhere']);
    });
  });
}
