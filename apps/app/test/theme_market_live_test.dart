// Reads real themes from Open VSX: MARKET=1 fvm flutter test test/theme_market_live_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/theme_market.dart';

void main() {
  test('Dracula from Open VSX, its themes read', () async {
    final market = ThemeMarket();
    final found = await market.search('dracula');
    expect(found, isNotNull);
    final official = found!.firstWhere((l) => l.id == 'dracula-theme.theme-dracula');
    final themes = await market.themesIn(official.download);
    // ignore: avoid_print
    print([
      for (final t in themes)
        '${t.name} dark=${t.dark} ${t.colors['background']?.toRadixString(16)}',
    ]);
    expect(themes, isNotEmpty);
    expect(themes.first.dark, isTrue);
    expect(themes.first.colors['background'], 0xFF282A36);
  }, skip: Platform.environment['MARKET'] == null ? 'set MARKET=1 to reach Open VSX' : null);
}
