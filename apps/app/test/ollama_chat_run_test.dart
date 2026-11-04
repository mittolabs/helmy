import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/engines/ollama/ollama_chat_engine.dart';
import 'package:helmy/domain/models/chat_item.dart';

/// A stand-in for the model server: each answer streams [words], one chunk
/// every [gap], then a done chunk, and the connection closes [linger] later.
/// The requests it was sent are kept.
class _Server {
  _Server(this._server, this.requests);

  static Future<_Server> start(
    List<String> words,
    Duration gap, {
    Duration linger = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map>[];
    server.listen((req) async {
      requests.add(jsonDecode(await utf8.decodeStream(req)) as Map);
      req.response
        ..bufferOutput = false
        ..headers.contentType = ContentType.json;
      try {
        for (final w in words) {
          req.response.writeln(
            jsonEncode({
              'message': {'content': w},
              'done': false,
            }),
          );
          await req.response.flush();
          await Future<void>.delayed(gap);
        }
        req.response.writeln(
          jsonEncode({
            'message': {'content': ''},
            'done': true,
          }),
        );
        await req.response.flush();
        await Future<void>.delayed(linger);
        await req.response.close();
      } on Object {
        // The client hung up: that is the stop.
      }
    });
    return _Server(server, requests);
  }

  final HttpServer _server;
  final List<Map> requests;
  String get host => 'http://${_server.address.host}:${_server.port}';
  Future<void> close() => _server.close(force: true);
}

Future<void> _turnEnds(OllamaChatRun run) => run.changes.firstWhere((ended) => ended);

void main() {
  test('a Stop pressed after the answer is whole does not mark it interrupted', () async {
    // The last word is in, and the connection has yet to close.
    final server = await _Server.start(
      ["You're ", 'welcome! ', 'Just let me know.'],
      Duration.zero,
      linger: const Duration(milliseconds: 500),
    );
    final items = <ChatItem>[];
    final run = OllamaChatRun(host: server.host, model: 'test', items: items);
    final ended = _turnEnds(run);
    run.send('very nice');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(items.whereType<AssistantText>().single.text, contains('let me know'));
    run.interrupt();
    await ended;
    expect(items.whereType<Notice>(), isEmpty);
    expect(items.whereType<TurnSummary>().single.ok, isTrue);
    await run.close();
    await server.close();
  });

  test('a Stop mid-answer marks it interrupted, and Helmy knows it was cut off', () async {
    final words = [for (var i = 0; i < 40; i++) 'word$i '];
    final server = await _Server.start(words, const Duration(milliseconds: 50));
    final items = <ChatItem>[];
    final run = OllamaChatRun(host: server.host, model: 'test', items: items);
    var ended = _turnEnds(run);
    run.send('tell me a long story');
    await Future<void>.delayed(const Duration(milliseconds: 600));
    run.interrupt();
    await ended;
    expect(items.whereType<Notice>().single.text, 'Interrupted');
    expect((items.whereType<AssistantText>().single.text).split(' ').length, lessThan(40));

    ended = _turnEnds(run);
    run.send('did I interrupt?');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    run.interrupt();
    await ended;
    final sent = (server.requests.last['messages'] as List).cast<Map>();
    expect(sent.map((m) => m['role']).skip(1).toList(), ['user', 'assistant', 'system', 'user']);
    expect(sent[3]['content'], contains('stopped your answer'));
    await run.close();
    await server.close();
  });
}
