part of '../chat_screen.dart';

/// The conversation, and beside it the one open panel, as wide as it was
/// last dragged. The conversation keeps room to read: in a narrow window the
/// panel gives way first, and steps aside when even that is too little.
class _SidePanels extends StatelessWidget {
  const new({required this.vm, required this.chat});
  final ChatViewModel vm;
  final Widget chat;

  static const _chatMin = 420.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final p = vm.panel;
      // No room left beside the conversation (a narrow window): no panel.
      final room = box.maxWidth - _chatMin - _Divider.width;
      final width = room <= 0 ? 0.0 : vm.panelWidth.clamp(0.0, room);
      return Row(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(child: chat),
          if (p != null && width >= 260) ...[
            _Divider(onDrag: (dx) => vm.resize(width - dx)),
            SizedBox(
              width: width,
              child: switch (p) {
                .changes => ChangesPanel(vm: vm),
                .background => BackgroundPanel(vm: vm),
                .preview => PreviewPanel(vm: vm),
                .ship => ShipPanel(vm: vm),
              },
            ),
          ],
        ],
      );
    },
  );
}

/// The edge between two columns: a hairline, and a wider strip to drag.
class _Divider extends StatefulWidget {
  const new({required this.onDrag});
  final ValueChanged<double> onDrag;

  static const width = 1.0;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return SizedBox(
      width: _Divider.width,
      child: OverflowBox(
        maxWidth: 9,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hot = true),
          onExit: (_) => setState(() => _hot = false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
            child: Center(
              child: Container(
                width: _hot ? 2 : 1,
                color: _hot ? c.foreground.withValues(alpha: .3) : c.border.withValues(alpha: .6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
