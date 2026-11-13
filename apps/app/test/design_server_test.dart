import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/design_server.dart';

void main() {
  test('a design file is served only from inside its folder', () {
    expect(DesignServer.fileIn('/d', 'welcome.html')?.path, '/d/welcome.html');
    expect(DesignServer.fileIn('/d', 'img/hero.png')?.path, '/d/img/hero.png');
    for (final bad in ['../secret', 'a/../../b', '', '/etc/passwd', 'a//b', './x', r'a\..\b']) {
      expect(DesignServer.fileIn('/d', bad), isNull, reason: bad);
    }
  });

  test('the version fingerprint is the canvas page\'s (FNV-1a over UTF-8)', () {
    // The same string through the canvas's fnv() in JavaScript.
    expect(DesignServer.fnv(utf8.encode('<p>café ✓ 日本</p>\n')), '1b15c771');
    expect(DesignServer.fnv(utf8.encode('')), '811c9dc5');
    expect(DesignServer.fnv(utf8.encode('a')), 'e40c292c');
  });

  test('a save from the canvas over a version the agent has since changed is refused', () async {
    final dir = await Directory.systemTemp.createTemp('design');
    addTearDown(() => dir.delete(recursive: true));
    final screen = File('${dir.path}/home.html')..writeAsStringSync('<p>read by the canvas</p>');
    final canvas = await DesignServer.shared.canvasFor(dir.path);
    final url = canvas.replace(
      path: canvas.path.replaceFirst('canvas.html', 'd/${canvas.queryParameters['d']}/home.html'),
      query: '',
    );
    Future<int> put(String text, String over) async {
      final client = HttpClient();
      try {
        final r = await client.putUrl(url);
        r.headers.set('X-Helmy-Base', DesignServer.fnv(utf8.encode(over)));
        r.write(text);
        return (await r.close()).statusCode;
      } finally {
        client.close();
      }
    }

    // Over what is there: written.
    expect(await put('<p>edited</p>', '<p>read by the canvas</p>'), HttpStatus.noContent);
    expect(screen.readAsStringSync(), '<p>edited</p>');
    // The agent writes it; a save over the old version is refused, and the agent's stands.
    screen.writeAsStringSync('<p>the agent wrote this</p>');
    expect(await put('<p>edited again</p>', '<p>edited</p>'), HttpStatus.conflict);
    expect(screen.readAsStringSync(), '<p>the agent wrote this</p>');
  });
}
