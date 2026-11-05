import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

/// [data] as a QR code, dark on light whatever the theme (cameras read it
/// best that way), with the quiet margin readers need.
class QrView extends StatelessWidget {
  const QrView(this.data, {super.key, this.size = 200});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(data)));
    return Container(
      width: size,
      height: size,
      padding: .all(size / 16),
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: .circular(size / 20)),
      child: Semantics(
        label: 'Pairing code',
        image: true,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;

  @override
  void paint(Canvas canvas, Size size) {
    final n = image.moduleCount;
    final cell = size.width / n;
    final dark = Paint()..color = const Color(0xFF000000);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (image.isDark(y, x)) {
          // A hair over a cell, so no seams show between neighbours.
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell + .5, cell + .5), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
