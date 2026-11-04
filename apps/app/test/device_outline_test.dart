import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/device_outline.dart';

void main() {
  test("an iOS simulator's screen, from AXe: the elements with words, where to tap them", () {
    // A real description of the booted iPhone 17 Pro's home screen, taken while testing.
    final f = File('test/fixtures/axe_describe_ui.json');
    final elements = iosElements(f.readAsStringSync());
    expect(elements, isNotEmpty);
    expect(elements.every((e) => e.label.isNotEmpty || e.value != null), isTrue);
    final first = elements.first;
    final (cx, cy) = centerOf(first);
    expect((cx, cy), (first.x + first.width / 2, first.y + first.height / 2));
    expect(outline('iPhone 17 Pro', elements), startsWith('iPhone 17 Pro now:\n[d1] '));
  });

  test("an Android screen, from uiautomator: words or a name, in pixels", () {
    const xml =
        '<hierarchy rotation="0">'
        '<node index="0" text="" content-desc="" class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" enabled="true">'
        '<node index="1" text="Wi-Fi" content-desc="" class="android.widget.TextView" bounds="[48,300][400,360]" enabled="true" />'
        '<node index="2" text="" content-desc="Search settings" class="android.widget.ImageButton" bounds="[900,120][1020,240]" enabled="true" />'
        '<node index="3" text="hunter2" content-desc="Password" class="android.widget.EditText" password="true" bounds="[48,500][1032,600]" enabled="false" />'
        '<node index="4" text="Tom &amp; Jerry" content-desc="" class="android.widget.TextView" bounds="[0,0][0,0]" enabled="true" />'
        '</node></hierarchy>';
    final elements = androidElements(xml);
    expect([for (final e in elements) e.label], ['Wi-Fi', 'Search settings', 'Password']);
    expect(centerOf(elements[1]), (960.0, 180.0));
    expect(elements[2].kind, 'EditText (password)');
    expect([for (final e in elements) e.depth], [1, 1, 1], reason: 'all inside the frame layout');
    final text = outline('Pixel', elements);
    expect(text, contains('[d2] ImageButton "Search settings"'));
    expect(text, contains('[d3] EditText (password) "Password" = "hunter2" (disabled)'));
  });

  test('nothing with words: said, with the way to look', () {
    expect(outline('Pixel', const []), contains('device_screen'));
  });
}
