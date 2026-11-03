// Ashlar UI: selection. Copied in by `ashlar add` with Input and with AshlarApp; it is
// yours to change. The handles and the cut, copy and paste menu, for text fields and for
// text selected anywhere in the app.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'theme.dart';

/// Selection handles for touch: a small dot on a stem at each end of the selection.
class AshlarSelectionControls extends TextSelectionControls {
  AshlarSelectionControls(this.color);

  /// The selection handles' colour.
  final Color color;
  static const _size = 18.0;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    // Handles are for dragging a selection with a finger. A mouse needs none, so the
    // desktop shows none, as its own apps do.
    final desktop = switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (desktop || type == TextSelectionHandleType.collapsed) {
      return const SizedBox.shrink();
    }
    final start = type == TextSelectionHandleType.left;
    return SizedBox(
      width: _size,
      height: _size + textLineHeight,
      child: CustomPaint(painter: _HandlePainter(color, start, textLineHeight)),
    );
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      switch (type) {
        TextSelectionHandleType.left => Offset(_size / 2, textLineHeight),
        TextSelectionHandleType.right => const Offset(_size / 2, 0),
        TextSelectionHandleType.collapsed => Offset.zero,
      };

  @override
  Size getHandleSize(double textLineHeight) => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => Size.zero,
    _ => _sizeFor(textLineHeight),
  };

  Size _sizeFor(double textLineHeight) => Size(_size, _size + textLineHeight);

  // The menu is built by contextMenuBuilder; this older hook is not used.
  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) => const SizedBox.shrink();
}

class _HandlePainter extends CustomPainter {
  _HandlePainter(this.color, this.start, this.lineHeight);

  final Color color;
  final bool start;
  final double lineHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final x = size.width / 2;
    // The start handle hangs below the text line, the end handle sits above it.
    final dot = start ? Offset(x, size.height - 6) : const Offset(9, 6);
    canvas.drawRect(
      Rect.fromLTWH(
        x - .75,
        start ? lineHeight : 6,
        1.5,
        size.height - lineHeight - 6,
      ),
      paint,
    );
    canvas.drawCircle(dot, 6, paint);
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.color != color;
}

/// The cut, copy, paste and select-all menu, drawn as a popover above the selection.
class AshlarSelectionMenu extends StatelessWidget {
  const AshlarSelectionMenu({
    super.key,
    required this.anchors,
    required this.items,
  });

  /// Where the selection is, from the field's or the region's state.
  final TextSelectionToolbarAnchors anchors;

  /// The menu's buttons: cut, copy, paste, select all.
  final List<ContextMenuButtonItem> items;

  static String _label(ContextMenuButtonItem item) =>
      item.label ??
      switch (item.type) {
        ContextMenuButtonType.cut => 'Cut',
        ContextMenuButtonType.copy => 'Copy',
        ContextMenuButtonType.paste => 'Paste',
        ContextMenuButtonType.selectAll => 'Select all',
        ContextMenuButtonType.delete => 'Delete',
        ContextMenuButtonType.lookUp => 'Look up',
        ContextMenuButtonType.searchWeb => 'Search',
        ContextMenuButtonType.share => 'Share',
        ContextMenuButtonType.liveTextInput => 'Scan text',
        ContextMenuButtonType.custom => '',
      };

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final shown = items.where((i) => _label(i).isNotEmpty).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return CustomSingleChildLayout(
      delegate: TextSelectionToolbarLayoutDelegate(
        anchorAbove: anchors.primaryAnchor - const Offset(0, 8),
        anchorBelow:
            (anchors.secondaryAnchor ?? anchors.primaryAnchor) +
            const Offset(0, 24),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.popover,
          borderRadius: BorderRadius.circular(t.radiusMd),
          border: Border.all(color: c.border),
          boxShadow: t.shadowLg,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in shown)
              GestureDetector(
                onTap: item.onPressed,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    _label(item),
                    style: t.text.sm.copyWith(color: c.popoverForeground),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
