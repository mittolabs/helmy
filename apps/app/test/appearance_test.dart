import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/widgets/chat_items.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/utils/format.dart';
import 'package:helmy/utils/platform.dart';

/// Appearance: clocks read as chosen, fonts and contrast reach the theme.
void main() {
  tearDown(() {
    use24Hour = false;
    chosenCodeFont = null;
  });

  test('clocks read 12 or 24 hours, everywhere through one helper', () {
    final t = DateTime(2026, 11, 5, 13, 5, 9);
    expect(clock(t), '1:05 PM');
    expect(clock(t, seconds: true), '1:05:09 PM');
    use24Hour = true;
    expect(clock(t), '13:05');
    expect(threadStamp(DateTime(2026, 11, 2, 17, 40), DateTime(2026, 11, 5)), 'Nov 2, 17:40');
  });

  test('the chosen code font comes first, the usual ones after', () {
    expect(monoFonts.first, 'Menlo');
    chosenCodeFont = 'JetBrains Mono';
    expect(monoFonts.take(2), ['JetBrains Mono', 'Menlo']);
  });

  test('a font and contrast reach the theme', () {
    final plain = themeFor(Brightness.dark);
    final firm = themeFor(Brightness.dark, font: 'Avenir', contrast: 1);
    expect(firm.text.fontFamily, 'Avenir');
    expect(firm.colors.border, isNot(plain.colors.border));
    expect(firm.colors.mutedForeground, isNot(plain.colors.mutedForeground));
    expect(plain.text.fontFamily, isNull);
    const s = AppSettings(codeFont: 'Menlo', clock: .twentyFour, width: .full);
    final back = AppSettings.fromJson(s.toJson());
    expect((back.codeFont, back.clock, back.width), ('Menlo', ClockFormat.twentyFour, Width.full));
    expect(s.copyWith(codeFont: '').codeFont, isNull, reason: "'' is back to the system's");
  });
}
