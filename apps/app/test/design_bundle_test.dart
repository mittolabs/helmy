import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/design_bundle.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('design'));
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'a design goes to the phone whole: its screens in order, its pictures inside them',
    () async {
      File('${dir.path}/canvas.json').writeAsStringSync(
        jsonEncode({
          'title': 'Bloom',
          'boards': {
            'a.html': {'x': 0, 'y': 0, 'w': 390, 'h': 844},
            'b.html': {'x': 470, 'y': 0, 'w': 390, 'h': 844},
          },
          'order': ['b.html', 'a.html', 'gone.html'],
        }),
      );
      File('${dir.path}/dot.png').writeAsBytesSync([137, 80, 78, 71]);
      File('${dir.path}/a.html').writeAsStringSync(
        '<img src="dot.png"><img src="https://example.com/x.png"><a href="b.html">next</a>'
        '<div style="background:url(\'dot.png\')"></div><img src="../outside.png">',
      );
      File('${dir.path}/b.html').writeAsStringSync('<p>B</p>');
      final d = (await designBundle(dir.path))!;
      expect(d['order'], ['b.html', 'a.html'], reason: 'only the screens it has, in order');
      final a = (d['screens'] as Map)['a.html'] as String;
      expect(a, contains('src="data:image/png;base64,'));
      expect(a, contains('url("data:image/png;base64,'));
      expect(a, contains('src="https://example.com/x.png"'), reason: 'web addresses stay');
      expect(a, contains('href="b.html"'), reason: 'links between screens stay');
      expect(a, contains('src="../outside.png"'), reason: 'nothing from outside the folder');
    },
  );

  test('no index, no design', () async {
    expect(await designBundle(dir.path), isNull);
  });
}
