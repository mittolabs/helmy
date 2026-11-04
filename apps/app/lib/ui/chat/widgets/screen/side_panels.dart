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
      // Expanded: the panel has the page, the conversation a press away.
      if (p != null && vm.panelExpanded) return _Panel(vm: vm, panel: p);
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
              child: _Panel(vm: vm, panel: p),
            ),
          ],
        ],
      );
    },
  );
}

/// One panel, under a bar that names it and can expand or close it.
class _Panel extends StatelessWidget {
  const new({required this.vm, required this.panel});
  final ChatViewModel vm;
  final SidePanel panel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final expanded = vm.panelExpanded;
    Widget tool(String label, IconData icon, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 14),
      ),
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          height: 32,
          margin: .only(top: titleLine - 16),
          // Expanded, the bar starts past the window's buttons, as the header does.
          padding: .only(
            left: expanded && !sidebarBeside(context) ? titleRowStart + 40 : 14,
            right: 12,
          ),
          child: Row(
            spacing: 2,
            children: [
              Expanded(
                child: Text(
                  switch (panel) {
                    .changes => 'Changes',
                    .background => 'Background',
                    .preview => 'Preview',
                    .ship => 'Ship',
                    .device => 'Device',
                  },
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              ),
              tool(
                expanded ? 'Back beside the conversation' : 'Expand',
                expanded
                    ? AshlarIconsRoundedStroke.arrowsMinimize
                    : AshlarIconsRoundedStroke.arrowsMaximize,
                vm.toggleExpanded,
              ),
              tool('Close', AshlarIconsRoundedStroke.x, vm.closePanel),
            ],
          ),
        ),
        Expanded(
          child: switch (panel) {
            .changes => ChangesPanel(vm: vm),
            .background => BackgroundPanel(vm: vm),
            .preview => PreviewPanel(vm: vm),
            .ship => ShipPanel(vm: vm),
            .device => DevicePanel(vm: vm),
          },
        ),
      ],
    );
  }
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
