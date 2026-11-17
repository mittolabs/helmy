import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/browser/browser_host.dart';
import 'package:helmy/data/services/browser/browser_tools.dart';

/// A page that names no character set is read as Western, and its symbols
/// come out garbled (· as Â·): reading it says so, with the fix.
class _Page implements PageDriver {
  _Page({required this.named});
  final bool named;

  @override
  Future<Object?> eval(String script) async {
    if (script.contains('characterSet')) {
      return {'set': named ? 'UTF-8' : 'windows-1252', 'unnamed': !named};
    }
    if (script.contains('snapshot()')) {
      return {'title': 'Skateboard Â· 3D', 'url': 'file:///s.html', 'text': 'Maple deck'};
    }
    return true;
  }

  @override
  Future<void> navigate(String url) async {}
  @override
  Future<void> back() async {}
  @override
  String get url => 'file:///s.html';
  @override
  Future<void> Function(double x, double y)? get click => null;
  @override
  Future<void> Function(String text)? get typeText => null;
  @override
  Future<void> Function(String key)? get press => null;
  @override
  Future<Uint8List?> screenshot() async => null;
}

void main() {
  Future<String> read(bool named) async {
    final host = BrowserHost()..attach('s', _Page(named: named));
    final r = await BrowserTools(host).call('browser_read', {}, 's');
    return '${((r['content'] as List).first as Map)['text']}';
  }

  test('a page with no character set is said to need one', () async {
    expect(await read(false), contains('<meta charset="utf-8">'));
  });

  test('a page that names one is read as it is', () async {
    expect(await read(true), isNot(contains('character set')));
  });
}
