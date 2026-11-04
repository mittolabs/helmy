import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/chromium/chromium_service.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/utils/platform.dart';

void main() {
  late Directory data;
  setUp(() async => data = await Directory.systemTemp.createTemp('chromium'));
  tearDown(() async {
    Desktop.current = Platform.isMacOS ? .mac : (Platform.isWindows ? .windows : .linux);
    await data.delete(recursive: true);
  });

  test('installed Chromium browsers are found, the most used first', () async {
    Desktop.current = .mac;
    final there = {
      '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
      '/Users/me/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      '/Applications/Safari.app/Contents/MacOS/Safari',
    };
    final service = ChromiumService(
      appData: () async => data,
      exists: there.contains,
      environment: const {'HOME': '/Users/me'},
    );
    final found = await service.installed();
    expect(
      [for (final b in found) b.name],
      ['Brave Browser', 'Google Chrome'],
      reason: 'by where each is looked for, then the order Helmy prefers; no Safari',
    );
    expect((await service.pick(null))?.name, 'Brave Browser');
    expect(
      (await service.pick('/Users/me/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'))
          ?.name,
      'Google Chrome',
      reason: 'the one chosen in settings, while it is installed',
    );
    expect((await service.pick('/gone/Chromium'))?.name, 'Brave Browser');
  });

  test('none installed is said as none', () async {
    Desktop.current = .linux;
    final service = ChromiumService(
      appData: () async => data,
      exists: (_) => false,
      environment: const {'PATH': '/usr/bin:/bin'},
    );
    expect(await service.installed(), isEmpty);
    expect(await service.pick(null), isNull);
  });

  test("Chrome for Testing's feed gives this computer's download", () {
    final feed = {
      'channels': {
        'Stable': {
          'version': '157.0.8103.38',
          'downloads': {
            'chrome': [
              {'platform': 'mac-arm64', 'url': 'https://x/mac-arm64/chrome-mac-arm64.zip'},
              {'platform': 'win64', 'url': 'https://x/win64/chrome-win64.zip'},
            ],
          },
        },
      },
    };
    final d = ChromiumService.parseLatest(feed, 'mac-arm64');
    expect(d?.version, '157.0.8103.38');
    expect(d?.url, 'https://x/mac-arm64/chrome-mac-arm64.zip');
    expect(ChromiumService.parseLatest(feed, 'linux64'), isNull);
    expect(ChromiumService.parseLatest(const {}, 'mac-arm64'), isNull);
  });

  test('what draws Preview, and the browser chosen, are kept', () {
    final s = const AppSettings().copyWith(
      previewWith: PreviewEngine.chromium,
      chromiumBrowser: '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
    );
    final back = AppSettings.fromJson(s.toJson());
    expect(back.previewWith, PreviewEngine.chromium);
    expect(back.chromiumBrowser, s.chromiumBrowser);
    expect(AppSettings.fromJson(const {}).previewWith, PreviewEngine.system);
  });
}
