// Exports a design from the command line, as the app does:
//   fvm dart run tool/design_export.dart <design folder> <out folder> [web|react]
import 'dart:io';

import 'package:helmy/domain/design_export/export.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: design_export <design folder> <out folder> [web|react]');
    exit(64);
  }
  final target = ExportTarget.values.asNameMap()[args.length > 2 ? args[2] : 'react'];
  if (target == null) {
    stderr.writeln('targets: ${ExportTarget.values.map((t) => t.name).join(', ')}');
    exit(64);
  }
  final files = await exportDesign(args[0], args[1], target);
  stdout.writeln('${files.length} files in ${args[1]}');
}
