part of '../chat_screen.dart';

/// The conversation, and beside it the panel of tabs, as wide as it was last
/// dragged. The conversation keeps room to read: in a narrow window the panel
/// gives way first, and steps aside when even that is too little. Every tab
/// stays alive while another shows, the panel is hidden, or it is expanded.
class _SidePanels extends StatefulWidget {
  const new({required this.vm, required this.chat});
  final ChatViewModel vm;
  final Widget chat;

  static const _chatMin = 420.0;

  @override
  State<_SidePanels> createState() => _SidePanelsState();
}

class _SidePanelsState extends State<_SidePanels> {
  // The one panel, moved whole between beside, expanded and hidden.
  final _panel = GlobalKey();

  // The device, moved whole between its tab and floating: its screen, marks
  // and logs go with it.
  final _device = GlobalKey();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final vm = widget.vm;
      final panel = vm.tabs.isEmpty ? null : _Panel(key: _panel, vm: vm, device: _device);
      // No room left beside the conversation (a narrow window): no panel.
      final room = box.maxWidth - _SidePanels._chatMin - _Divider.width;
      final width = room <= 0 ? 0.0 : vm.panelWidth.clamp(0.0, room);
      final expanded = panel != null && vm.panelOpen && vm.panelExpanded;
      final shown = !expanded && panel != null && vm.panelOpen && width >= 260;
      // Always a stack, so floating the device does not rebuild what is under it.
      return Stack(
        fit: .expand,
        children: [
          // Expanded: the panel has the page, the conversation a press away.
          if (expanded) panel else _beside(vm, panel, shown, width),
          if (vm.deviceFloating && vm.device != null)
            _FloatingDevice(
              vm: vm,
              area: box.biggest,
              // At first, the top right of the conversation, clear of the panel.
              start: shown ? box.maxWidth - width - _Divider.width : box.maxWidth,
              child: DevicePanel(key: _device, vm: vm),
            ),
        ],
      );
    },
  );

  Widget _beside(ChatViewModel vm, Widget? panel, bool shown, double width) => Row(
    crossAxisAlignment: .stretch,
    children: [
      Expanded(child: widget.chat),
      if (shown) ...[
        _Divider(onDrag: (dx) => vm.resize(width - dx)),
        SizedBox(width: width, child: panel),
      ] else if (panel != null)
        // Hidden, its tabs stay as they were.
        Offstage(
          child: SizedBox(width: vm.panelWidth, child: panel),
        ),
    ],
  );
}

/// The device floating over the conversation: a card with a bar to drag it
/// by, kept inside the page, with a way back into the panel and a way to put
/// it away.
class _FloatingDevice extends StatelessWidget {
  const _FloatingDevice({
    required this.vm,
    required this.area,
    required this.start,
    required this.child,
  });
  final ChatViewModel vm;

  /// The page it floats over.
  final Size area;

  /// Where the room it starts in ends, on the right.
  final double start;
  final Widget child;

  static const width = 340.0;
  static const _bar = 30.0;

  /// Clear of the header.
  static const _top = titleLine + 28;

  /// [at] moved inside the page, a margin clear of its edges.
  Offset _inside(Offset at, Size size) => Offset(
    at.dx.clamp(8.0, (area.width - size.width - 8).clamp(8.0, double.infinity)),
    at.dy.clamp(_top, (area.height - size.height - 8).clamp(_top, double.infinity)),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final size = Size(
      width.clamp(0.0, area.width - 16),
      (area.height - titleLine - 32).clamp(0.0, 700.0),
    );
    final at = _inside(vm.deviceFloatAt ?? Offset(start - size.width - 16, 0), size);
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
    return Positioned(
      left: at.dx,
      top: at.dy,
      width: size.width,
      height: size.height,
      child: Semantics(
        container: true,
        label: 'Floating device',
        // Selecting the conversation does not reach into it.
        child: SelectionContainer.disabled(
          child: Container(
            clipBehavior: .antiAlias,
            decoration: BoxDecoration(
              color: c.background,
              border: .all(color: c.border),
              borderRadius: .circular(t.radiusLg),
              boxShadow: t.shadowLg,
            ),
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                // Dragged by its bar; the screen below keeps its taps and swipes.
                // Raw pointer moves, since the page's text selection would win
                // a drag in the gesture arena.
                MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerMove: (e) =>
                        vm.moveFloatingDevice(_inside((vm.deviceFloatAt ?? at) + e.delta, size)),
                    child: Container(
                      height: _bar,
                      padding: const .only(left: 10, right: 4),
                      color: c.muted.withValues(alpha: .5),
                      child: Row(
                        spacing: 2,
                        children: [
                          AshlarIcon(
                            AshlarIconsRoundedStroke.gripHorizontal,
                            size: 13,
                            color: c.mutedForeground,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              vm.device?.device?.name ?? 'Device',
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: t.text.xs.copyWith(
                                fontWeight: .w500,
                                color: c.mutedForeground,
                              ),
                            ),
                          ),
                          tool(
                            'Back into the panel',
                            AshlarIconsRoundedStroke.panelRight,
                            vm.dockDevice,
                          ),
                          tool(
                            'Put the device away',
                            AshlarIconsRoundedStroke.x,
                            vm.closeFloatingDevice,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(height: 1, color: c.border),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tab kind's name and icon.
(String, IconData) _kindOf(SidePanel kind) => switch (kind) {
  .preview => ('Browser', AshlarIconsRoundedStroke.globe),
  .terminal => ('Terminal', AshlarIconsRoundedStroke.squareTerminal),
  .files => ('Files', AshlarIconsRoundedStroke.files),
  .side => ('Side chat', AshlarIconsRoundedStroke.messageSquareText),
  .changes => ('Changes', AshlarIconsRoundedStroke.fileDiff),
  .ship => ('Pull request', AshlarIconsRoundedStroke.gitPullRequest),
  .device => ('Device', AshlarIconsRoundedStroke.smartphone),
  .background => ('Background', AshlarIconsRoundedStroke.loader),
};

/// The panel: its tabs along the top, with + to add one, and the tab showing.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.vm, required this.device});
  final ChatViewModel vm;

  /// The device's key, so it can move to float over the conversation whole.
  final GlobalKey device;

  String _label(PanelTab tab) => switch (tab.kind) {
    .preview when (tab.title ?? '').isNotEmpty => tab.title!,
    .preview => switch (Uri.tryParse(tab.url ?? '')) {
      final u? when u.host.isNotEmpty => u.host.replaceFirst('www.', ''),
      final u? when u.scheme == 'file' => u.pathSegments.lastOrNull ?? 'Page',
      _ => 'New page',
    },
    .changes =>
      vm.changedFiles == null || vm.changedFiles == 0 ? 'Changes' : 'Changes ${vm.changedFiles}',
    .device => vm.device?.device?.name ?? 'Device',
    .terminal when tab.action != null => tab.action!.name,
    .side => vm.sideTitle(tab.sideId!),
    .terminal => 'Terminal ${vm.tabs.where((t) => t.kind == .terminal).toList().indexOf(tab) + 1}',
    _ => _kindOf(tab.kind).$1,
  };

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
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
    final active = vm.active;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        // In the window's title bar: a double-click on its empty space zooms
        // the window, as on the conversation's side.
        TitleBar(
          child: Container(
            height: 32,
            margin: .only(top: titleLine - 16),
            // Expanded, the bar starts past the window's buttons, as the header does.
            padding: .only(
              left: expanded && !sidebarBeside(context) ? titleRowStart + titleControlsRoom : 6,
              right: 8,
            ),
            child: Row(
              spacing: 2,
              children: [
                Expanded(
                  // As wide as the tabs: the space past them is the title bar's.
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SingleChildScrollView(
                      scrollDirection: .horizontal,
                      child: Row(
                        spacing: 2,
                        children: [
                          for (final tab in vm.tabs)
                            _TabChip(
                              label: _label(tab),
                              // An action's: running, finished, or stopped by an error.
                              icon: switch (tab) {
                                PanelTab(action: _?, exitCode: null) =>
                                  AshlarIconsRoundedStroke.play,
                                PanelTab(action: _?, exitCode: 0) =>
                                  AshlarIconsRoundedStroke.circleCheck,
                                PanelTab(action: _?) => AshlarIconsRoundedStroke.circleAlert,
                                _ => _kindOf(tab.kind).$2,
                              },
                              failed: tab.action != null && (tab.exitCode ?? 0) != 0,
                              image: tab.kind == .preview ? tab.icon : null,
                              on: tab == active,
                              onPressed: () => vm.focus(tab),
                              onClose: () => vm.closeTab(tab),
                            ),
                          DropdownMenu(
                            items: [
                              for (final kind in vm.addable)
                                MenuItem(
                                  leading: AshlarIcon(_kindOf(kind).$2, size: 16),
                                  // Several pages and terminals; one of each other kind.
                                  onPressed: () => switch (kind) {
                                    .preview || .terminal => vm.add(kind),
                                    .side => unawaited(vm.sideChat()),
                                    _ => vm.show(kind),
                                  },
                                  child: Text(_kindOf(kind).$1),
                                ),
                            ],
                            builder: (context, menu) =>
                                tool('Add a tab', AshlarIconsRoundedStroke.plus, menu.open),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (active?.kind == .device)
                  tool(
                    'Float over the conversation',
                    AshlarIconsRoundedStroke.pictureInPicture2,
                    vm.floatDevice,
                  ),
                tool(
                  expanded ? 'Back beside the conversation' : 'Expand',
                  expanded
                      ? AshlarIconsRoundedStroke.arrowsMinimize
                      : AshlarIconsRoundedStroke.arrowsMaximize,
                  vm.toggleExpanded,
                ),
                tool('Hide the panel', AshlarIconsRoundedStroke.x, vm.closePanel),
              ],
            ),
          ),
        ),
        Container(height: 1, color: c.border),
        Expanded(
          child: IndexedStack(
            index: active == null ? 0 : vm.tabs.indexOf(active),
            children: [
              for (final tab in vm.tabs)
                KeyedSubtree(
                  key: ValueKey(tab.id),
                  child: switch (tab.kind) {
                    .changes => ChangesPanel(vm: vm),
                    .background => BackgroundPanel(vm: vm),
                    .preview => PreviewPanel(
                      vm: vm,
                      tab: tab,
                      active: tab == active && vm.panelOpen,
                    ),
                    .ship => ShipPanel(vm: vm),
                    .terminal => TerminalPanel(
                      cwd: vm.session?.cwd ?? homeDir,
                      active: tab == active && vm.panelOpen,
                      command: tab.action?.command,
                      name: tab.action?.name,
                      runs: tab.runs,
                      onOutput: tab.action == null ? null : (text) => vm.actionOutput(tab, text),
                      onExit: tab.action == null ? null : (code) => vm.actionEnded(tab, code),
                      onRunAgain: tab.action == null ? null : () => vm.run(tab.action!),
                    ),
                    .device => DevicePanel(key: device, vm: vm),
                    .files => FilesPanel(vm: vm, active: tab == active && vm.panelOpen),
                    .side => SideChatPanel(vm: vm, tab: tab),
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tab along the panel's top: its icon and name, and a way to close it.
class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    this.image,
    this.failed = false,
    required this.on,
    required this.onPressed,
    required this.onClose,
  });
  final String label;
  final IconData icon;

  /// What it ran stopped with an error: its icon says so in red.
  final bool failed;

  /// The page's own icon, when it has one; [icon] until then, or if it fails.
  final String? image;
  final bool on;
  final VoidCallback onPressed;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      selected: on,
      semanticLabel: label,
      builder: (context, state) => Container(
        height: 26,
        padding: const .only(left: 8, right: 4),
        decoration: BoxDecoration(
          color: on
              ? c.accent
              : state.hovered
              ? c.accent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd - 2),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            if (image case final src?)
              Image.network(
                src,
                width: 14,
                height: 14,
                errorBuilder: (_, _, _) =>
                    AshlarIcon(icon, size: 13, color: on ? c.foreground : c.mutedForeground),
              )
            else
              AshlarIcon(
                icon,
                size: 13,
                color: failed ? c.destructive : (on ? c.foreground : c.mutedForeground),
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.xs.copyWith(
                  fontWeight: .w500,
                  color: on ? c.foreground : c.mutedForeground,
                ),
              ),
            ),
            // Closing shows on the tab showing, or under the mouse.
            Opacity(
              opacity: on || state.hovered ? 1 : 0,
              child: Tooltip(
                message: 'Close the tab',
                child: Pressable(
                  onPressed: onClose,
                  semanticLabel: 'Close $label',
                  builder: (context, s) => Padding(
                    padding: const .all(2),
                    child: AshlarIcon(
                      AshlarIconsRoundedStroke.x,
                      size: 12,
                      color: s.hovered ? c.foreground : c.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The edge between the conversation and a panel: a hairline, and a strip to
/// drag. The strip is a real column on the conversation's side of the line,
/// since a page in the panel (a web view) takes the mouse on its own side,
/// and it keeps the conversation's scrollbar clear of the edge.
class _Divider extends StatefulWidget {
  const new({required this.onDrag});
  final ValueChanged<double> onDrag;

  static const width = 11.0;

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
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        // Lit only while dragged: a page in the panel (a native view) takes
        // the mouse without saying it left, so a hover would stay lit.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Follows the pointer from where it was pressed.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => setState(() => _hot = true),
          onHorizontalDragEnd: (_) => setState(() => _hot = false),
          onHorizontalDragCancel: () => setState(() => _hot = false),
          onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: _hot ? 2 : 1,
              // The theme's hairline, brighter only while dragged.
              color: _hot ? c.foreground.withValues(alpha: .3) : c.border,
            ),
          ),
        ),
      ),
    );
  }
}
