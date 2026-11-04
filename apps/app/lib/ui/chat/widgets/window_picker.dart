import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/window_snapshots.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/helmy_dialog.dart';
import '../view_models/chat_view_model.dart';

/// The windows open on screen, to snapshot one into the message being
/// written: its picture, and its text where macOS gives it.
Future<void> pickWindow(BuildContext context, ChatViewModel vm) async {
  final picked = await showAshlarDialog<ScreenWindow>(
    context: context,
    builder: (context) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Focus(autofocus: true, child: _Picker(vm: vm)),
    ),
  );
  if (picked != null) snapshotRequests.value = (window: picked, fromKeys: false);
}

class _Picker extends StatefulWidget {
  const _Picker({required this.vm});
  final ChatViewModel vm;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  List<ScreenWindow>? _windows;

  @override
  void initState() {
    super.initState();
    widget.vm.snapshotWindows().then((w) {
      if (mounted) setState(() => _windows = w);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    final windows = _windows;
    return HelmyDialog(
      title: 'Snapshot a window',
      body:
          'Its picture goes into your message, with the text in it where macOS gives it. '
          'With snapshots on in Settings, both Shift keys take the window in front.',
      icon: AshlarIconsRoundedStroke.appWindow,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: switch (windows) {
          null => const Padding(
            padding: .all(16),
            child: Center(child: Spinner(size: 16)),
          ),
          [] => Text(
            'No other windows are open.',
            style: t.text.sm.copyWith(color: c.mutedForeground),
          ),
          _ => ScrollArea.builder(
            itemCount: windows.length,
            itemBuilder: (context, i) {
              final w = windows[i];
              return Pressable(
                onPressed: () => Navigator.pop(context, w),
                semanticLabel: '${w.app}, ${w.title}',
                builder: (context, state) => Container(
                  padding: const .symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: state.hovered || state.focused ? c.accent : null,
                    borderRadius: .circular(t.radiusMd),
                  ),
                  child: Row(
                    spacing: 10,
                    children: [
                      AshlarIcon(
                        AshlarIconsRoundedStroke.appWindow,
                        size: 16,
                        color: c.mutedForeground,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            Text(w.app, style: t.text.sm.copyWith(fontWeight: .w500)),
                            if (w.title.isNotEmpty)
                              Text(w.title, maxLines: 1, overflow: .ellipsis, style: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        },
      ),
      actions: [DialogButton('Cancel', onPressed: () => Navigator.pop(context))],
    );
  }
}
