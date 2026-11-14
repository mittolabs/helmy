import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// [bytes] of the file at [path] there, kept in this page; where they are.
Future<String> keepFetched(String path, Uint8List bytes) async =>
    web.URL.createObjectURL(web.Blob([bytes.toJS].toJS));
