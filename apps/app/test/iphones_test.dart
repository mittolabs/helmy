import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/iphones.dart';

void main() {
  test('paired iPhones and iPads Apple still reaches, and how', () {
    final phones = iphonesFrom(File('test/fixtures/devicectl_devices.json').readAsStringSync());
    expect(phones.map((p) => (p.name, p.os, p.wired)), [
      ('Alex’s iPhone', '26.3.1', false),
      ('Test iPhone', '26.5', true),
    ], reason: 'the iPad out of reach and the watch are left out');
    expect(iphonesFrom('not json'), isEmpty);
    expect(iphonesFrom('{"result":{}}'), isEmpty);
  });

  test('the apps worth launching are the ones their developer built', () {
    final apps = phoneAppsFrom(
      jsonEncode({
        'result': {
          'apps': [
            {
              'bundleIdentifier': 'com.apple.Preferences',
              'name': 'Settings',
              'builtByDeveloper': false,
            },
            {'bundleIdentifier': 'com.example.tasks', 'name': 'tasks', 'builtByDeveloper': true},
            {'bundleIdentifier': 'com.example.budget', 'name': 'Budget', 'builtByDeveloper': true},
          ],
        },
      }),
    );
    expect(apps.map((a) => a.bundle), ['com.example.budget', 'com.example.tasks']);
  });

  test("what went wrong says why and what fixes it, in Helmy's words", () {
    final locked = File('test/fixtures/devicectl_locked.json').readAsStringSync();
    expect(
      phoneTrouble('Alex’s iPhone', locked),
      'Alex’s iPhone is locked. Unlock it, then try again.',
    );
    expect(
      phoneTrouble('Test iPhone', 'ERROR: Developer Mode is disabled on the device.'),
      startsWith('Test iPhone has Developer Mode off. Turn it on'),
    );
    expect(
      phoneTrouble('Test iPhone', 'ApplicationVerificationFailed: Failed to verify code signature'),
      contains("isn't signed for this iPhone"),
    );
    expect(phoneTrouble('Test iPhone', 'Operation timed out'), contains("can't be reached"));
    expect(
      phoneTrouble(
        'Test iPhone',
        '{"error":{"userInfo":{"NSLocalizedDescription":{"string":"Something new."}}}}',
      ),
      "Test iPhone didn't do it: Something new.",
    );
  });
}
