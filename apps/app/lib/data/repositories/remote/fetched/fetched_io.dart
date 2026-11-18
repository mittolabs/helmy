import 'dart:io';
import 'dart:typed_data';

import '../../../../utils/paths.dart';

/// [bytes] of the file at [path] there, kept here; where they are.
Future<String> keepFetched(String path, Uint8List bytes) async {
  final dir = Directory('${Directory.systemTemp.path}/helmy-files');
  await dir.create(recursive: true);
  final f = File('${dir.path}/${path.hashCode.toUnsigned(32)}-${baseName(path)}');
  await f.writeAsBytes(bytes);
  return f.path;
}
