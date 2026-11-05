import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/helmy_dialog.dart';
import '../view_models/chat_view_model.dart';
import 'chat_screen.dart';

/// A side chat in its tab: a question asked beside the session without
/// adding to it. It starts from all the session knows, the session goes on
/// working meanwhile, and what it found is brought back when wanted.
class SideChatPanel extends StatefulWidget {
  const SideChatPanel({super.key, required this.vm, required this.tab});

  /// The session it is beside.
  final ChatViewModel vm;
  final PanelTab tab;

  @override
  State<SideChatPanel> createState() => _SideChatPanelState();
}

class _SideChatPanelState extends State<SideChatPanel> {
  late final ChatViewModel side = ChatViewModel(
    sessionId: widget.tab.sideId!,
    sessions: context.read(),
    conversations: context.read(),
    settings: _maybe(),
    projects: _maybe(),
    desktop: _maybe(),
    watch: _maybe(),
    fixes: _maybe(),
    embedded: true,
  );

  /// A service where the app gives it; null where it does not (a test).
  T? _maybe<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    // The question it was started with, asked once it has loaded.
    final ask = widget.tab.ask;
    if (ask != null) {
      widget.tab.ask = null;
      unawaited(side.ready.then((_) => side.send.execute(ask)));
    }
  }

  @override
  void dispose() {
    side.dispose();
    super.dispose();
  }

  Future<void> _bringBack() async {
    final ok = await widget.vm.bringBack(side.sessionId);
    if (!mounted) return;
    showToast(
      context,
      title: ok ? 'Brought back' : 'The thread is working',
      description: ok
          ? 'What was said here goes with your next message in the session.'
          : 'Bring this back when it has finished its turn.',
      type: ok ? .success : .info,
    );
  }

  Future<void> _delete() async {
    final sure = await confirm(
      context,
      title: 'Delete this side chat?',
      body: 'What was said in it goes. The thread it is beside stays as it is.',
      action: 'Delete',
      destructive: true,
    );
    if (sure) await widget.vm.deleteSide(side.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return ChatScreen(
      viewModel: side,
      bar: ListenableBuilder(
        listenable: Listenable.merge([widget.vm, side]),
        builder: (context, _) => Container(
          height: 40,
          padding: const .fromLTRB(12, 0, 8, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            spacing: 4,
            children: [
              Expanded(
                child: Text(
                  'Beside "${widget.vm.session?.title ?? ''}"',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
              ),
              Tooltip(
                message: widget.vm.busy
                    ? 'When the thread has finished its turn'
                    : 'Give what was said here to the thread, with your next message there',
                child: Button(
                  variant: .ghost,
                  size: .xs,
                  onPressed: widget.vm.busy || widget.vm.sideUnused(side.sessionId)
                      ? null
                      : _bringBack,
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.cornerDownLeft, size: 14),
                  child: const Text('Bring back'),
                ),
              ),
              Tooltip(
                message: 'Delete this side chat',
                child: Button(
                  variant: .ghost,
                  size: .iconXs,
                  semanticLabel: 'Delete this side chat',
                  onPressed: _delete,
                  child: const AshlarIcon(AshlarIconsRoundedStroke.trash, size: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
