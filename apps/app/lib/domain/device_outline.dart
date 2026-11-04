import 'dart:convert';

/// One thing on a device's screen that can be read or used: what it is, its
/// words, and where it is (points on iOS, pixels on Android: the units taps
/// take).
typedef ScreenElement = ({
  String ref,
  String kind,
  String label,
  String? value,
  double x,
  double y,
  double width,
  double height,
  bool enabled,
});

/// The middle of [e], where a tap lands.
(double, double) centerOf(ScreenElement e) => (e.x + e.width / 2, e.y + e.height / 2);

/// What `axe describe-ui` gives for an iOS simulator, as the elements worth
/// reading: those with words, in reading order.
List<ScreenElement> iosElements(String json) {
  final out = <ScreenElement>[];
  void walk(Object? node) {
    if (node is List) {
      for (final n in node) {
        walk(n);
      }
      return;
    }
    if (node is! Map) return;
    final label = '${node['AXLabel'] ?? node['title'] ?? ''}'.trim();
    final value = node['AXValue'] == null ? null : '${node['AXValue']}'.trim();
    final f = node['frame'];
    // iOS puts a scroll bar on every scrolling view: nothing to read or use.
    final scrollBar = '${node['type']}' == 'Slider' && label.toLowerCase().contains('scroll bar');
    if ((label.isNotEmpty || (value?.isNotEmpty ?? false)) && f is Map && !scrollBar) {
      out.add((
        ref: 'd${out.length + 1}',
        kind: '${node['type'] ?? node['role_description'] ?? 'Element'}',
        label: label,
        value: value == null || value.isEmpty || value == label ? null : value,
        x: (f['x'] as num).toDouble(),
        y: (f['y'] as num).toDouble(),
        width: (f['width'] as num).toDouble(),
        height: (f['height'] as num).toDouble(),
        enabled: node['enabled'] != false,
      ));
    }
    walk(node['children']);
  }

  try {
    walk(jsonDecode(json));
  } on FormatException {
    return const [];
  }
  return out;
}

/// What `uiautomator dump` gives for an Android device, as the elements worth
/// reading: those with words, or a name for what they do.
List<ScreenElement> androidElements(String xml) {
  final out = <ScreenElement>[];
  final node = RegExp(r'<node ([^>]*?)/?>');
  final attr = RegExp(r'([\w-]+)="([^"]*)"');
  final bounds = RegExp(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]');
  String unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  for (final m in node.allMatches(xml)) {
    final a = {for (final p in attr.allMatches(m[1]!)) p[1]!: unescape(p[2]!)};
    final text = (a['text'] ?? '').trim();
    final desc = (a['content-desc'] ?? '').trim();
    final label = desc.isNotEmpty ? desc : text;
    final b = bounds.firstMatch(a['bounds'] ?? '');
    if (label.isEmpty || b == null) continue;
    final x1 = double.parse(b[1]!), y1 = double.parse(b[2]!);
    final x2 = double.parse(b[3]!), y2 = double.parse(b[4]!);
    if (x2 <= x1 || y2 <= y1) continue;
    final kind = (a['class'] ?? 'View').split('.').last;
    out.add((
      ref: 'd${out.length + 1}',
      kind: a['password'] == 'true' ? '$kind (password)' : kind,
      label: label,
      value: desc.isNotEmpty && text.isNotEmpty && text != desc ? text : null,
      x: x1,
      y: y1,
      width: x2 - x1,
      height: y2 - y1,
      enabled: a['enabled'] != 'false',
    ));
  }
  return out;
}

/// [elements] as the agent reads them: one line each, with the ref it acts
/// on. Short: words carry what a screenshot would, at a fraction of its cost.
String outline(String deviceName, List<ScreenElement> elements) {
  if (elements.isEmpty) {
    return '$deviceName: nothing on screen has words to read (a game, a picture, or a '
        'screen still loading). device_screen shows it.';
  }
  return [
    '$deviceName now:',
    for (final e in elements)
      '[${e.ref}] ${e.kind} "${e.label}"'
          '${e.value == null ? '' : ' = "${e.value}"'}'
          '${e.enabled ? '' : ' (disabled)'}',
  ].join('\n');
}
