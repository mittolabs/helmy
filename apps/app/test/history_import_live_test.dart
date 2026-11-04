@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/history_import.dart';

void main() {
  test('what this Mac has to bring in (read only: nothing is imported)', () async {
    final watch = Stopwatch()..start();
    final found = await HistoryImport().scan();
    // ignore: avoid_print
    print('scanned in ${watch.elapsedMilliseconds} ms: ${found.length} folders');
    for (final p in found.take(12)) {
      // ignore: avoid_print
      print('  ${p.cwd}  ${p.kinds}  ${p.conversations.length}  ${p.latest}');
    }
    final sample = found.expand((p) => p.conversations).take(3);
    for (final c in sample) {
      final r = await HistoryImport().read(c);
      // ignore: avoid_print
      print('  read ${c.engineId}: ${r?.items.length} items, title length ${r?.title.length}');
    }
  });
}
