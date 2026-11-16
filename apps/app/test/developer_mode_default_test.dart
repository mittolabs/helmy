import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/settings.dart';

/// Developer mode is on by default, for people from earlier builds too, and
/// stays off once someone turns it off.
void main() {
  test('on for a new install', () {
    expect(const AppSettings().developerMode, isTrue);
    expect(AppSettings.fromJson(const {}).developerMode, isTrue);
  });

  test('on for someone whose earlier build saved it off, once', () {
    expect(AppSettings.fromJson(const {'developerMode': false}).developerMode, isTrue);
  });

  test('turned off from now on, it stays off', () {
    final off = const AppSettings().copyWith(developerMode: false);
    expect(AppSettings.fromJson(off.toJson()).developerMode, isFalse);
  });
}
