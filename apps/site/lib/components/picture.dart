import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A picture from web/img/, made by tool/images.sh at each of [widths] as AVIF
/// and WebP. The browser takes the smallest that is sharp at [sizes] (the
/// width the page shows it at) in the first format it can show.
///
/// Each file's address carries a hash of its bytes (?v=), so the server can
/// let browsers keep it for a year (infra/Caddyfile): a changed picture gets a
/// new address. The site is built ahead of time, so the hashes are read then.
class Picture extends StatelessComponent {
  const Picture(
    this.name, {
    super.key,
    required this.widths,
    required this.sizes,
    required this.width,
    required this.height,
    this.alt = '',
    this.classes,
    this.lazy = true,
    this.first = false,
  });

  /// The name tool/images.sh gives it: `web/img/<name>-<width>.<format>`.
  final String name;
  final List<int> widths;
  final String sizes;

  /// The size it takes up, for its box before it loads (or its shape, when
  /// the page's styles set its width).
  final int width, height;
  final String alt;
  final String? classes;

  /// Waits until it is about to scroll into view.
  final bool lazy;

  /// The first thing a visitor sees: fetched ahead of everything else.
  final bool first;

  String _srcset(String format) =>
      [for (final w in widths) '${_at('$name-$w.$format')} ${w}w'].join(', ');

  @override
  Component build(BuildContext context) => Component.element(
    tag: 'picture',
    children: [
      source(type: 'image/avif', attributes: {'srcset': _srcset('avif'), 'sizes': sizes}),
      img(
        src: _at('$name-${widths.last}.webp'),
        alt: alt,
        width: width,
        height: height,
        classes: classes,
        loading: lazy ? MediaLoading.lazy : null,
        attributes: {
          'srcset': _srcset('webp'),
          'sizes': sizes,
          'decoding': 'async',
          if (first) 'fetchpriority': 'high',
        },
      ),
    ],
  );
}

/// The address of a file in web/img/, with a hash of what is in it.
String _at(String file) => '/img/$file?v=${_hashes[file] ??= _hash(file)}';

final _hashes = <String, String>{};

/// FNV-1a, 32 bits: enough to tell one version of a picture from the next.
String _hash(String file) {
  var h = 0x811c9dc5;
  for (final b in File('web/img/$file').readAsBytesSync()) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
