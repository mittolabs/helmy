import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/chromium/chromium_service.dart';
import 'package:helmy/domain/models/settings.dart';

/// The Chromium preview's profiles: each its own folder, so its own
/// sign-ins; the first where it always was; clearing one leaves the rest.
void main() {
  test('each profile its own folder, cleared alone', () async {
    final root = await Directory.systemTemp.createTemp('profiles');
    addTearDown(() => root.delete(recursive: true));
    final chromium = ChromiumService(appData: () async => root);
    const brave = ChromiumBrowser(name: 'Brave Browser', executable: '/x/brave');
    final main = await chromium.profileDir(brave, '');
    final work = await chromium.profileDir(brave, 'Work stuff');
    expect(main.path, '${root.path}/chromium/profiles/Brave-Browser');
    expect(work.path, '${root.path}/chromium/profiles/Brave-Browser-p-Work-stuff');
    File('${work.path}/Cookies').writeAsStringSync('signed in');
    File('${main.path}/Cookies').writeAsStringSync('signed in too');
    await chromium.clearProfile('Work stuff');
    expect(work.existsSync(), isFalse);
    expect(main.existsSync(), isTrue, reason: 'the others are left');
    await chromium.clearProfile('');
    expect(main.existsSync(), isFalse);
    const s = AppSettings(browserProfiles: ['Work'], browserProfile: 'Work');
    expect(AppSettings.fromJson(s.toJson()).browserProfiles, ['Work']);
  });
}
