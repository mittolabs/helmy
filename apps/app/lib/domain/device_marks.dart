import 'device_outline.dart';

/// A mark on a device's screen: its number, where it is (shares of the
/// screen, 0 to 1), what the person wrote of it, and the element under it.
typedef DeviceMark = ({
  int n,
  double left,
  double top,
  double width,
  double height,
  String note,
  ScreenElement? element,
});

/// The element a mark points at: the smallest whose box holds the mark's
/// middle, from [elements] in units [unitsWide] by [unitsHigh]. Null when
/// none does.
ScreenElement? elementUnder(
  List<ScreenElement> elements, {
  required double left,
  required double top,
  required double width,
  required double height,
  required double unitsWide,
  required double unitsHigh,
}) {
  final x = (left + width / 2) * unitsWide, y = (top + height / 2) * unitsHigh;
  ScreenElement? best;
  for (final e in elements) {
    if (x < e.x || x > e.x + e.width || y < e.y || y > e.y + e.height) continue;
    if (best == null || e.width * e.height < best.width * best.height) best = e;
  }
  return best;
}

/// The marks as the agent reads them beside their picture: each number,
/// what is under it, and what the person wants of it.
String deviceMarksMarkdown(String deviceName, List<DeviceMark> marks, {String? picture}) {
  final out = StringBuffer()
    ..writeln('# Marks on $deviceName')
    ..writeln()
    ..writeln(
      picture == null
          ? 'Each mark is numbered as below.'
          : 'The picture ($picture) shows the screen with each mark numbered as below.',
    )
    ..writeln();
  for (final m in marks) {
    final e = m.element;
    out.writeln(
      '${m.n}. ${e == null ? 'A part of the screen' : '${e.kind} "${e.label}"'}'
      '${m.note.trim().isEmpty ? '' : ': ${m.note.trim()}'}',
    );
  }
  return out.toString();
}
