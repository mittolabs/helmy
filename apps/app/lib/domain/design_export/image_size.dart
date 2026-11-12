/// A picture's own size in px, read from its file's header, as a browser
/// reads it to lay out an `<img>` before it has drawn it.
library;

import 'dart:convert';

/// [bytes]' width and height: PNG, JPEG, GIF, WebP or SVG; null for what it
/// cannot read.
(double, double)? imageSize(List<int> bytes) {
  int at(int i) => i < bytes.length ? bytes[i] : 0;
  int be16(int i) => at(i) << 8 | at(i + 1);
  int be32(int i) => be16(i) << 16 | be16(i + 2);
  int le16(int i) => at(i) | at(i + 1) << 8;
  int le24(int i) => le16(i) | at(i + 2) << 16;
  bool starts(List<int> sig, [int from = 0]) {
    for (var i = 0; i < sig.length; i++) {
      if (at(from + i) != sig[i]) return false;
    }
    return true;
  }

  if (starts(const [0x89, 0x50, 0x4E, 0x47])) {
    return (be32(16).toDouble(), be32(20).toDouble());
  }
  if (starts(ascii.encode('GIF'))) return (le16(6).toDouble(), le16(8).toDouble());
  if (starts(const [0xFF, 0xD8])) {
    // The first start-of-frame marker holds it.
    var i = 2;
    while (i + 9 < bytes.length) {
      if (at(i) != 0xFF) return null;
      final marker = at(i + 1);
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        return (be16(i + 7).toDouble(), be16(i + 5).toDouble());
      }
      i += 2 + be16(i + 2);
    }
    return null;
  }
  if (starts(ascii.encode('RIFF')) && starts(ascii.encode('WEBP'), 8)) {
    if (starts(ascii.encode('VP8X'), 12)) {
      return ((le24(24) + 1).toDouble(), (le24(27) + 1).toDouble());
    }
    if (starts(ascii.encode('VP8L'), 12)) {
      final b = at(21) | at(22) << 8 | at(23) << 16 | at(24) << 24;
      return (((b & 0x3FFF) + 1).toDouble(), ((b >> 14 & 0x3FFF) + 1).toDouble());
    }
    if (starts(ascii.encode('VP8 '), 12)) {
      return ((le16(26) & 0x3FFF).toDouble(), (le16(28) & 0x3FFF).toDouble());
    }
    return null;
  }
  final text = utf8.decode(bytes.take(4096).toList(), allowMalformed: true);
  final svg = RegExp(r'<svg\b[^>]*>', caseSensitive: false).firstMatch(text)?[0];
  if (svg != null) {
    double? attr(String name) {
      final v = RegExp('\\s$name\\s*=\\s*["\']([\\d.]+)(px)?["\']').firstMatch(svg)?[1];
      return v == null ? null : double.tryParse(v);
    }

    final w = attr('width'), h = attr('height');
    if (w != null && h != null) return (w, h);
    final box = RegExp(
      'viewBox\\s*=\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(svg)?[1];
    final p = box?.trim().split(RegExp(r'[\s,]+')).map(double.tryParse).toList();
    if (p != null && p.length == 4 && p[2] != null && p[3] != null && p[3]! > 0) {
      // Without both sizes its box gives the ratio at least.
      return w != null ? (w, w * p[3]! / p[2]!) : (p[2]!, p[3]!);
    }
  }
  return null;
}
