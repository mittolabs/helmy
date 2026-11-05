import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/browser/browser_host.dart';
import 'package:helmy/data/services/browser/browser_tools.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/watch_service.dart';

/// A project with the browser turned off: its agent is not offered the
/// browser, and a call anyway is refused with where to turn it on.
void main() {
  test('browser tools follow the project setting', () async {
    final tools = HelmyTools(WatchService(CliLocator()), null, BrowserTools(BrowserHost()))
      ..browserAllowed = (session) => session != 'off';
    Future<List<String>> names(String session) async {
      final r = await tools.answer('tools/list', const {}, session: session);
      return [for (final t in ((r['result'] as Map)['tools'] as List)) '${(t as Map)['name']}'];
    }

    expect(await names('on'), contains('browser_open'));
    expect(await names('off'), isNot(contains('browser_open')));
    final r = await tools.answer('tools/call', {
      'name': 'browser_open',
      'arguments': {'url': 'https://example.com'},
    }, session: 'off');
    final result = r['result'] as Map;
    expect(result['isError'], isTrue);
    expect('${result['content']}', contains('Settings > Projects'));
  });

  test('a program chosen by hand is used while it is there', () async {
    final dir = await Directory.systemTemp.createTemp('programs');
    addTearDown(() => dir.delete(recursive: true));
    final mine = File('${dir.path}/claude')..writeAsStringSync('#!/bin/sh\n');
    var chosen = <String, String>{'claude': mine.path};
    final locator = CliLocator(chosen: () => chosen);
    expect(await locator.find('claude'), mine.path);
    chosen = {'claude': '${dir.path}/gone'};
    expect(await locator.find('claude'), isNot('${dir.path}/gone'));
  });
}
