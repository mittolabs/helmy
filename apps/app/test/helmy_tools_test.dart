import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/cli_locator.dart';
import 'package:helmy/data/services/helmy_tools.dart';
import 'package:helmy/data/services/watch_service.dart';

/// Posts one JSON-RPC message to [url], as an MCP client does.
Future<Map> call(String url, String method, [Map params = const {}]) async {
  final client = HttpClient();
  final req = await client.postUrl(Uri.parse(url));
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}));
  final res = await req.close();
  final body = await utf8.decodeStream(res);
  client.close();
  return jsonDecode(body) as Map;
}

void main() {
  late Directory dir;
  late String video;
  late HelmyTools tools;
  final hasFfmpeg = Process.runSync('which', ['ffmpeg']).exitCode == 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('watch');
    video = '${dir.path}/two colors.mp4';
    if (hasFfmpeg) {
      // Two seconds red, then two seconds blue, no sound.
      await Process.run('ffmpeg', [
        '-v', 'error', '-f', 'lavfi', '-i', 'color=c=red:s=320x180:d=2', //
        '-f', 'lavfi', '-i', 'color=c=blue:s=320x180:d=2',
        '-filter_complex', '[0][1]concat=n=2:v=1', '-pix_fmt', 'yuv420p', video,
      ]);
    }
    tools = HelmyTools(WatchService(CliLocator()));
  });
  tearDownAll(() async {
    await tools.close();
    await dir.delete(recursive: true);
  });

  test('Helmy serves its tools as MCP, on this computer only, behind a secret', () async {
    final url = (await tools.url)!;
    expect(url, startsWith('http://127.0.0.1:'));
    final init = await call(url, 'initialize', {'protocolVersion': '2025-06-18'});
    expect((init['result'] as Map)['serverInfo'], {'name': 'helmy', 'version': '1'});
    final list = await call(url, 'tools/list');
    final names = [for (final t in (list['result'] as Map)['tools'] as List) (t as Map)['name']];
    expect(names, ['watch_video']);
    // The wrong secret gets nothing.
    final wrong = url.replaceFirst(RegExp(r'/mcp/.*'), '/mcp/guess');
    final client = HttpClient();
    final res = await (await client.postUrl(Uri.parse(wrong))).close();
    expect(res.statusCode, HttpStatus.notFound);
    client.close();
  });

  test('watching a video gives frames across it, with when each is', () async {
    final url = (await tools.url)!;
    final r = await call(url, 'tools/call', {
      'name': 'watch_video',
      'arguments': {'path': video},
    });
    final result = r['result'] as Map;
    final content = (result['content'] as List).cast<Map>();
    expect(result['isError'], isFalse, reason: '${content.first['text']}');
    expect(content.first['text'], contains('0:04 long'));
    expect(content.first['text'], contains('no sound'));
    final images = content.where((c) => c['type'] == 'image').toList();
    expect(images.length, 6, reason: 'at least six, about one every 5 seconds');
    expect(content.where((c) => '${c['text']}'.startsWith('At 0:0')).length, 6);
    expect(images.first['mimeType'], 'image/jpeg');
  }, skip: hasFfmpeg ? false : 'needs ffmpeg');

  test('a missing file is said plainly', () async {
    final r = await call((await tools.url)!, 'tools/call', {
      'name': 'watch_video',
      'arguments': {'path': '/no/such/video.mp4'},
    });
    expect((r['result'] as Map)['isError'], isTrue);
  });
}
