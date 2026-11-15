import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/chat_share.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/utils/result.dart';

/// Sharing a chat as a link: a secret gist, through gh, never anything else.
void main() {
  test('shared: a secret gist of the conversation, its link and id', () async {
    final calls = <List<String>>[];
    String? written;
    final share = ChatShare(
      CliLocator(),
      run: (args) async {
        calls.add(args);
        if (args.first == 'gist') written = File(args.last).readAsStringSync();
        return args.first == 'auth'
            ? (code: 0, out: '', err: '')
            : (code: 0, out: 'https://gist.github.com/someone/0123abcd\n', err: '');
      },
    );
    final r = await share.share('Plan: Q3 / pricing', '# Plan\n\nWhat was said.');
    expect((r as Ok).value, (url: 'https://gist.github.com/someone/0123abcd', id: '0123abcd'));
    final create = calls.last;
    expect(create.take(2), ['gist', 'create']);
    expect(create, isNot(contains('--public')), reason: 'secret: by link only');
    expect(create.last, endsWith('Plan  Q3   pricing.md'));
    expect(written, '# Plan\n\nWhat was said.');
  });

  test('gh missing, or signed out: said, with what fixes it', () async {
    final none = ChatShare(CliLocator(), run: (_) async => null);
    expect(await none.trouble(), contains('brew install gh'));
    final out = ChatShare(CliLocator(), run: (_) async => (code: 1, out: '', err: 'not logged in'));
    final r = await out.share('Chat', 'x');
    expect('${(r as Error).error}', contains('gh auth login'));
  });

  test('stopping deletes the gist; one already gone counts as stopped', () async {
    final asked = <List<String>>[];
    final ok = ChatShare(
      CliLocator(),
      run: (args) async {
        asked.add(args);
        return (code: 0, out: '', err: '');
      },
    );
    expect(await ok.stop('0123abcd'), isA<Ok>());
    expect(asked.single, ['gist', 'delete', '0123abcd', '--yes']);
    final gone = ChatShare(CliLocator(), run: (_) async => (code: 1, out: '', err: 'HTTP 404'));
    expect(await gone.stop('0123abcd'), isA<Ok>());
  });
}
