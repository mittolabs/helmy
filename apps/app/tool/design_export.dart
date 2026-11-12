// Exports a design from the command line, as the app does:
//   fvm dart run tool/design_export.dart <design folder> <out folder> [target] [--measure]
// --measure keys every element of a Flutter export, for tool/design_check/flutter.mjs.
import 'dart:io';

import 'package:helmy/domain/design_export/export.dart';

Future<void> main(List<String> argv) async {
  final measure = argv.contains('--measure');
  final args = [for (final a in argv) if (a != '--measure') a];
  if (args.length < 2) {
    stderr.writeln('usage: design_export <design folder> <out folder> [target] [--measure]');
    exit(64);
  }
  final target = ExportTarget.values.asNameMap()[args.length > 2 ? args[2] : 'react'];
  if (target == null) {
    stderr.writeln('targets: ${ExportTarget.values.map((t) => t.name).join(', ')}');
    exit(64);
  }
  final files = await exportDesign(args[0], args[1], target, measure: measure);
  stdout.writeln('${files.length} files in ${args[1]}');
}
