@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/pull_requests.dart';

void main() {
  test('open pull requests across real projects (read only)', () async {
    final home = Platform.environment['HOME']!;
    final folders = [
      '$home/Mittolabs/products/helmy',
      '$home/Mittolabs/products/rika',
      '$home/Mittolabs/products/funnier',
    ];
    final watch = Stopwatch()..start();
    final r = await PullRequests(CliLocator()).list(folders);
    // ignore: avoid_print
    print(
      '${watch.elapsedMilliseconds} ms, me=${r.me}, problem=${r.problem}, ${r.prs.length} open',
    );
    for (final p in r.prs.take(6)) {
      // ignore: avoid_print
      print(
        '  ${p.repo}#${p.number} ${p.checks?.name} review=${p.review} draft=${p.draft} labels=${p.labels.length}',
      );
    }
  });
}
