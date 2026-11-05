import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] so [shot] can draw it to a file.
Widget shootable(Widget child) => RepaintBoundary(key: _key, child: child);
final _key = GlobalKey();

/// Draws what [shootable] wraps to [path] as a PNG, from Flutter's own
/// layers: it works with the display asleep, where a window capture is blank.
Future<void> shot(WidgetTester tester, String path) async {
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
