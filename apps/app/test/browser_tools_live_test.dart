// Drives a real Chromium-based browser: run with a browser installed.
@Tags(['browser'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/browser/browser_host.dart';
import 'package:helmy/data/services/browser/browser_tools.dart';
import 'package:helmy/data/services/chromium/chromium_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an agent reads, fills and checks a page in a few fast calls', () async {
    final root = await Directory.systemTemp.createTemp('browser-tools');
    final page = File('${root.path}/form.html')
      ..writeAsStringSync('''
<html><head><title>Greeter</title></head><body>
<h1>Say hello</h1>
<label for="name">Your name</label> <input id="name">
<button id="go" onclick="document.getElementById('out').textContent = 'Hello, ' + document.getElementById('name').value + '!'; console.error('greeted');">Greet</button>
<p id="out"></p>
<a href="https://example.com/about">About us</a>
</body></html>''');
    final chromium = ChromiumService(appData: () async => root);
    final tools = BrowserTools(BrowserHost(chromium: chromium));
    String text(Map r) => ((r['content'] as List).first as Map)['text'] as String;
    final times = <String, int>{};
    Future<Map> timed(String name, Map args) async {
      final w = Stopwatch()..start();
      final r = await tools.call(name, args, 's1');
      times[name] = w.elapsedMilliseconds;
      return r;
    }

    final opened = await timed('browser_open', {'url': Uri.file(page.path).toString()});
    expect(opened['isError'], isFalse, reason: text(opened));
    final outline = text(opened);
    expect(outline, contains('Greeter'));
    expect(outline, contains('# Say hello'));
    final box = RegExp(r'textbox "Your name" \[(e\d+)\]').firstMatch(outline)?.group(1);
    final button = RegExp(r'button "Greet" \[(e\d+)\]').firstMatch(outline)?.group(1);
    expect(box, isNotNull, reason: outline);
    expect(button, isNotNull, reason: outline);
    expect(outline, contains('link "About us"'));

    final acted = await timed('browser_act', {
      'steps': [
        {'do': 'type', 'ref': box, 'text': 'Tito'},
        {'do': 'click', 'ref': button},
      ],
    });
    expect(acted['isError'], isFalse, reason: text(acted));
    expect(text(acted), contains('Hello, Tito!'));
    expect(text(acted), contains('= "Tito"'));

    final found = await timed('browser_read', {'find': 'about'});
    expect(text(found), contains('link "About us"'));

    final logs = await timed('browser_logs', {});
    expect(text(logs), contains('greeted'));

    final evaluated = await timed('browser_eval', {'script': 'document.title.length'});
    expect(text(evaluated), '7');

    final shot = await timed('browser_screenshot', {});
    expect(((shot['content'] as List).first as Map)['type'], 'image');

    final missing = await tools.call('browser_act', {
      'steps': [
        {'do': 'click', 'ref': 'e999'},
      ],
    }, 's1');
    expect(missing['isError'], isTrue);
    expect(text(missing), contains('read it again'));

    // ignore: avoid_print
    print('times (ms): $times');
    await chromium.stop();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
