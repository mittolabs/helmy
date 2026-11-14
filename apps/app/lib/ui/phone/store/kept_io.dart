import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file(String name) async =>
    File('${(await getApplicationSupportDirectory()).path}/$name.txt');

/// What was kept under [name]; null when nothing was.
Future<String?> keptRead(String name) async {
  try {
    return await (await _file(name)).readAsString();
  } on Object {
    return null;
  }
}

/// Keeps [value] under [name]; null forgets it.
Future<void> keptWrite(String name, String? value) async {
  final f = await _file(name);
  if (value == null) {
    if (f.existsSync()) await f.delete();
    return;
  }
  await f.create(recursive: true);
  await f.writeAsString(value);
}
