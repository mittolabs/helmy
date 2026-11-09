import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Serves the design canvas and the designs it shows, to Helmy's own web
/// views only: bound to this Mac, behind a token made at start. Each
/// screen loads as a real page from its folder, so its pictures and links
/// work, and the canvas can reach into it to edit it.
class DesignServer {
  DesignServer._();
  static final shared = DesignServer._();

  HttpServer? _server;
  final _token = List.generate(16, (_) => Random.secure().nextInt(16).toRadixString(16)).join();
  final _folders = <String, String>{};

  /// Files the canvas saved, by full path, and when: the folder's watch
  /// leaves them be, so a screen being edited is not reloaded under the
  /// person editing it.
  final saved = <String, DateTime>{};

  /// Whether [path] was saved by the canvas just now.
  bool savedJustNow(String path) {
    final at = saved[path];
    return at != null && DateTime.now().difference(at) < const Duration(seconds: 2);
  }

  /// The canvas for the design in [folder] (a chat's `design/`), as a page
  /// address; starts the server the first time.
  Future<Uri> canvasFor(String folder) async {
    var server = _server;
    if (server == null) {
      server = _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) => unawaited(_serve(r)));
    }
    final id =
        _folders.entries.where((e) => e.value == folder).firstOrNull?.key ??
        (_folders.length + 1).toString();
    _folders[id] = folder;
    return Uri.parse('http://127.0.0.1:${server.port}/$_token/canvas.html?d=$id');
  }

  /// The file [rel] under [root], or null when it would leave it.
  static File? fileIn(String root, String rel) {
    final parts = rel.split('/');
    if (rel.isEmpty || parts.any((p) => p.isEmpty || p == '.' || p == '..' || p.contains('\\'))) {
      return null;
    }
    return File('$root/$rel');
  }

  Future<void> _serve(HttpRequest r) async {
    final res = r.response;
    try {
      final seg = r.uri.pathSegments;
      if (seg.length < 2 || seg.first != _token) return _status(res, HttpStatus.notFound);
      res.headers.set('Cache-Control', 'no-store');
      // The canvas itself.
      if (seg.length == 2 && seg[1] == 'canvas.html') {
        res.headers.contentType = ContentType.html;
        res.write(await rootBundle.loadString('assets/design/canvas.html'));
        return await res.close();
      }
      // A design's files: /<token>/d/<id>/<path>.
      if (seg.length >= 4 && seg[1] == 'd') {
        final root = _folders[seg[2]];
        final file = root == null ? null : fileIn(root, seg.sublist(3).join('/'));
        // Saved from the canvas: a screen or the index, nothing else.
        if (r.method == 'PUT') {
          final ext = file?.path.split('.').last.toLowerCase();
          if (file == null || !const {'html', 'htm', 'json'}.contains(ext)) {
            return _status(res, HttpStatus.forbidden);
          }
          final body = await utf8.decoder.bind(r).join();
          if (body.length > 8 << 20) return _status(res, HttpStatus.requestEntityTooLarge);
          saved[file.path] = DateTime.now();
          final temp = File('${file.path}.helmy-saving');
          await temp.writeAsString(body, flush: true);
          await temp.rename(file.path);
          saved[file.path] = DateTime.now();
          return _status(res, HttpStatus.noContent);
        }
        if (file == null || !file.existsSync()) return _status(res, HttpStatus.notFound);
        res.headers.contentType = _typeOf(file.path);
        await res.addStream(file.openRead());
        return await res.close();
      }
      _status(res, HttpStatus.notFound);
    } on Object {
      try {
        _status(res, HttpStatus.internalServerError);
      } on Object {
        // Gone already.
      }
    }
  }

  static void _status(HttpResponse res, int code) {
    res.statusCode = code;
    unawaited(res.close());
  }

  static ContentType _typeOf(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'html' || 'htm' => ContentType.html,
      'json' => ContentType.json,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'js' => ContentType('text', 'javascript', charset: 'utf-8'),
      'svg' => ContentType('image', 'svg+xml'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'gif' => ContentType('image', 'gif'),
      'webp' => ContentType('image', 'webp'),
      'woff2' => ContentType('font', 'woff2'),
      'woff' => ContentType('font', 'woff'),
      'ttf' => ContentType('font', 'ttf'),
      'otf' => ContentType('font', 'otf'),
      _ => ContentType.binary,
    };
  }
}
