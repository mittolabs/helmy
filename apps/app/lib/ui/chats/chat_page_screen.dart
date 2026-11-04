import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/session.dart';
import '../../utils/format.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/dropdown_menu.dart';
import '../core/ashlar/pressable.dart';
import '../core/ashlar/scroll_area.dart';
import '../core/ashlar/textarea.dart';
import '../core/ashlar/theme.dart';
import '../core/ashlar/tooltip.dart';
import '../core/helmy_dialog.dart';
import 'chat_page_view_model.dart';

/// A chat (decision `0014`): the topic, its brief, where its threads work,
/// and the threads themselves, each opened, moved to another chat, or a new
/// one started here.
class ChatPageScreen extends StatefulWidget {
  const ChatPageScreen({super.key, required this.viewModel});
  final ChatPageViewModel viewModel;

  @override
  State<ChatPageScreen> createState() => _ChatPageScreenState();
}

class _ChatPageScreenState extends State<ChatPageScreen> {
  ChatPageViewModel get vm => widget.viewModel;
  late final _brief = TextEditingController(text: vm.chat?.brief ?? '');
  final _briefFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // The brief is saved when it is left, not at every key.
    _briefFocus.addListener(() {
      if (!_briefFocus.hasFocus) vm.setBrief(_brief.text);
    });
    vm.addListener(_sync);
  }

  /// The brief kept by Helmy while the page is open: shown, unless the person
  /// is writing in it.
  void _sync() {
    final brief = vm.chat?.brief;
    if (brief != null && !_briefFocus.hasFocus && _brief.text != brief) _brief.text = brief;
  }

  @override
  void dispose() {
    vm.removeListener(_sync);
    _brief.dispose();
    _briefFocus.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final title = await askText(
      context,
      title: 'Rename chat',
      action: 'Rename',
      initial: vm.chat?.title ?? '',
      body: 'Named by you, it keeps this name whatever its threads are called.',
      icon: AshlarIconsRoundedStroke.pencil,
    );
    if (title != null) await vm.rename(title);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.sm.copyWith(color: c.mutedForeground, height: 1.5);
    return ColoredBox(
      color: c.background,
      child: ListenableBuilder(
        listenable: vm,
        builder: (context, _) {
          final chat = vm.chat;
          if (chat == null) {
            return Center(child: Text('This chat is no longer here.', style: muted));
          }
          final threads = vm.threads;
          return ScrollArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const .fromLTRB(32, 40, 32, 40),
                  child: Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      Row(
                        spacing: 8,
                        children: [
                          // The title with its pencil; the button at the end.
                          Expanded(
                            child: Row(
                              spacing: 8,
                              children: [
                                Flexible(
                                  child: Text(
                                    chat.title,
                                    maxLines: 2,
                                    overflow: .ellipsis,
                                    style: t.text.xl.copyWith(fontWeight: .w600),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Rename',
                                  child: Button(
                                    variant: .ghost,
                                    size: .iconSm,
                                    semanticLabel: 'Rename chat',
                                    onPressed: _rename,
                                    child: const AshlarIcon(
                                      AshlarIconsRoundedStroke.pencil,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Button(
                            onPressed: () async {
                              final id = await vm.newThread();
                              if (id != null && context.mounted) context.go('/s/$id');
                            },
                            leading: const AshlarIcon(AshlarIconsRoundedStroke.plus, size: 14),
                            child: const Text('New thread'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        [
                          '${threads.length} thread${threads.length == 1 ? '' : 's'}',
                          if (vm.places.isNotEmpty)
                            'in ${[for (final p in vm.places) projectName(p)].join(', ')}',
                        ].join(' '),
                        style: muted,
                      ),
                      const SizedBox(height: 24),
                      Text('Brief', style: t.text.sm.copyWith(fontWeight: .w600)),
                      const SizedBox(height: 4),
                      Text(
                        'What this chat has come to: decisions, and what is still open. '
                        'Each new thread here starts knowing it.',
                        style: muted,
                      ),
                      const SizedBox(height: 8),
                      Textarea(
                        controller: _brief,
                        focusNode: _briefFocus,
                        minLines: 3,
                        maxLines: 10,
                        placeholder: 'Nothing yet. Write what every thread here should know.',
                      ),
                      const SizedBox(height: 6),
                      // Who keeps it, said as it is.
                      Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            child: Text(
                              chat.briefByPerson
                                  ? 'Written by you: Helmy leaves it as it is.'
                                  : vm.localModel != null
                                  ? 'Kept by Helmy as threads here go quiet, on the model on this Mac.'
                                  : 'Helmy keeps this once a model runs on this Mac (Ollama). Until '
                                        'then, write it here.',
                              style: t.text.xs.copyWith(color: c.mutedForeground),
                            ),
                          ),
                          if (chat.briefByPerson && vm.localModel != null)
                            Button(
                              variant: .ghost,
                              size: .xs,
                              onPressed: vm.letHelmyKeep,
                              child: const Text('Let Helmy keep it'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text('Threads', style: t.text.sm.copyWith(fontWeight: .w600)),
                      const SizedBox(height: 8),
                      for (final s in threads) _ThreadRow(thread: s, vm: vm),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One thread: its title, where it works and when; opened by a press,
/// moved to another chat from its menu.
class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread, required this.vm});
  final Session thread;
  final ChatPageViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    return Pressable(
      onPressed: () => context.go('/s/${thread.id}'),
      semanticLabel: thread.title,
      builder: (context, state) => Container(
        padding: const .fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: state.hovered ? c.accent.withValues(alpha: .5) : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 10,
          children: [
            AshlarIcon(
              AshlarIconsRoundedStroke.messageSquareText,
              size: 15,
              color: c.mutedForeground,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(
                    thread.title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.sm.copyWith(fontWeight: .w500),
                  ),
                  if (thread.summary case final line? when line.isNotEmpty)
                    Text(
                      line,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: t.text.xs.copyWith(color: c.foreground.withValues(alpha: .8)),
                    ),
                  Text(
                    '${projectName(thread.repo ?? thread.cwd)} · ${ago(thread.updatedAt)}',
                    style: muted,
                  ),
                ],
              ),
            ),
            DropdownMenu(
              align: .end,
              items: [
                MenuSub(
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.folderInput, size: 16),
                  items: [
                    for (final other in vm.others)
                      MenuItem(
                        onPressed: () => vm.move(thread, other.id),
                        child: Text(other.title, maxLines: 1, overflow: .ellipsis),
                      ),
                  ],
                  enabled: vm.others.isNotEmpty,
                  child: const Text('Move to another chat'),
                ),
                MenuItem(
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.squarePlus, size: 16),
                  onPressed: vm.threads.length < 2
                      ? null
                      : () async {
                          final to = await vm.move(thread, null);
                          if (context.mounted) context.go('/c/$to');
                        },
                  child: const Text('Into a chat of its own'),
                ),
              ],
              builder: (context, menu) => Button(
                variant: .ghost,
                size: .iconSm,
                semanticLabel: 'Thread actions',
                onPressed: menu.open,
                child: const AshlarIcon(AshlarIconsRoundedStroke.ellipsis, size: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
