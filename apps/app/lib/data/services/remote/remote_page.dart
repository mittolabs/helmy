import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The page a phone's browser opens to use Helmy with no app: the phone's
/// remote built for the web, packed by `tool/remote.mjs` (each file gzipped,
/// behind an index), and served by [RemoteServer] on the port phones reach.
///
/// The page is public code, like the app in a store: what pairs a browser is
/// the key after the `#` in the link, which a browser never sends to a
/// server, so it never crosses the network.
class RemotePage {
  RemotePage._(this._bytes, this._index, this._tag);

  final Uint8List _bytes;
  final Map<String, (int, int)> _index;

  /// Changes with the pack: a browser keeps no stale copy across updates.
  final String _tag;

  /// The pack in [bytes]; null when they are not one.
  static RemotePage? read(Uint8List bytes) {
    try {
      final view = ByteData.sublistView(bytes);
      final len = view.getUint32(0);
      final start = 4 + len;
      final j = jsonDecode(utf8.decode(bytes.sublist(4, start))) as Map<String, Object?>;
      final index = {
        for (final e in j.entries)
          if (e.value case [final int at, final int n]) e.key: (start + at, n),
      };
      if (!index.containsKey('index.html')) return null;
      return RemotePage._(
        bytes,
        index,
        '"${bytes.length.toRadixString(36)}-${len.toRadixString(36)}"',
      );
    } on Object {
      return null;
    }
  }

  /// The file at [path] ('' for the page itself); null when there is none.
  ({Uint8List gzipped, String type})? file(String path) {
    final p = path.isEmpty || path.endsWith('/') ? '${path}index.html' : path;
    final at = _index[p];
    if (at == null) return null;
    return (gzipped: Uint8List.sublistView(_bytes, at.$1, at.$1 + at.$2), type: typeOf(p));
  }

  /// Answers [req] for [path] (without the leading slash).
  Future<void> serve(HttpRequest req, String path) async {
    final res = req.response;
    final f = file(path);
    res.headers
      // A browser asks again each time, and gets "not changed" when it is not.
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Content-Type-Options', 'nosniff');
    if (f == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers.set(HttpHeaders.etagHeader, _tag);
    if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == _tag) {
      res.statusCode = HttpStatus.notModified;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.parse(f.type);
    final gzipOk = (req.headers.value(HttpHeaders.acceptEncodingHeader) ?? '').contains('gzip');
    final body = gzipOk ? f.gzipped : Uint8List.fromList(gzip.decode(f.gzipped));
    // Sent as it is: Dart's server must not gzip it again.
    res.headers.set(HttpHeaders.varyHeader, 'Accept-Encoding');
    if (gzipOk) res.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
    res.contentLength = body.length;
    if (req.method != 'HEAD') res.add(body);
    await res.close();
  }

  static String typeOf(String path) => switch (path.split('.').last.toLowerCase()) {
    'html' => 'text/html; charset=utf-8',
    'js' || 'mjs' => 'text/javascript; charset=utf-8',
    'json' => 'application/json',
    'wasm' => 'application/wasm',
    'css' => 'text/css; charset=utf-8',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'svg' => 'image/svg+xml',
    'ico' => 'image/x-icon',
    'otf' => 'font/otf',
    'ttf' => 'font/ttf',
    'woff2' => 'font/woff2',
    _ => 'application/octet-stream',
  };

  /// What a browser is shown when this build has no page to serve.
  static const missing =
      '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">'
      '<title>Helmy</title><body style="font:16px system-ui;margin:2rem;max-width:32rem">'
      '<h1 style="font-size:1.25rem">This Helmy has no page for phone browsers</h1>'
      '<p>It was built without one. Install the Helmy app on this phone and scan the code '
      'with it, or update Helmy on the computer.</p>';
}
