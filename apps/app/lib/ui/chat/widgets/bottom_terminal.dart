import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/chat_view_model.dart';
import 'terminal_panel.dart';

/// The terminal under the conversation, as an editor's bottom panel: its
/// top edge drags it taller or shorter, its terminals sit side by side, and
/// hidden (⌘J) they keep running.
class BottomTerminal extends StatefulWidget {
  const BottomTerminal({super.key, required this.vm});
  final ChatViewModel vm;

  /// Never shorter than this, nor taller than all but this of the window.
  static const minHeight = 120.0;
  static const keepAbove = 200.0;

  @override
  State<BottomTerminal> createState() => _BottomTerminalState();
}

class _BottomTerminalState extends State<BottomTerminal> {
  bool _dragging = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final room = MediaQuery.sizeOf(context).height - BottomTerminal.keepAbove;
    final height = vm.bottomHeight.clamp(
      BottomTerminal.minHeight,
      room.clamp(BottomTerminal.minHeight, double.infinity),
    );
    Widget tool(String label, IconData icon, VoidCallback onPressed) => Tooltip(
      message: label,
      child: Button(
        variant: .ghost,
        size: .iconXs,
        semanticLabel: label,
        onPressed: onPressed,
        child: AshlarIcon(icon, size: 13),
      ),
    );
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          // The edge: a hairline, lit while dragged, with room to grab.
          MouseRegion(
            cursor: SystemMouseCursors.resizeRow,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: .opaque,
              onVerticalDragStart: (_) => setState(() => _dragging = true),
              onVerticalDragUpdate: (d) =>
                  vm.resizeBottom((height - d.delta.dy).clamp(BottomTerminal.minHeight, room)),
              onVerticalDragEnd: (_) => setState(() => _dragging = false),
              child: SizedBox(
                height: 7,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    height: _dragging || _hovered ? 2 : 1,
                    color: _dragging ? c.ring : (_hovered ? c.mutedForeground : c.border),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: .stretch,
                    children: [
                      for (final (i, id) in vm.bottomTerminals.indexed) ...[
                        if (i > 0) Container(width: 1, color: c.border),
                        Expanded(
                          child: TerminalPanel(
                            key: ValueKey('bottom-$id'),
                            cwd: vm.session?.cwd ?? homeDir,
                            active: vm.bottomOpen && i == vm.bottomTerminals.length - 1,
                            onClosed: () => vm.closeBottom(id),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Its controls, over the top right as T3 Code has them.
                Positioned(
                  top: 0,
                  right: 8,
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.background,
                      border: Border.all(color: c.border),
                      borderRadius: .circular(8),
                    ),
                    padding: const .all(2),
                    child: Row(
                      mainAxisSize: .min,
                      children: [
                        tool(
                          'Another terminal beside',
                          AshlarIconsRoundedStroke.columns2,
                          vm.splitBottom,
                        ),
                        tool(
                          'Close the last terminal',
                          AshlarIconsRoundedStroke.trash,
                          () => vm.closeBottom(vm.bottomTerminals.last),
                        ),
                        tool(
                          'Hide (${Desktop.current.keys('⌘J')})',
                          AshlarIconsRoundedStroke.x,
                          vm.toggleBottom,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
