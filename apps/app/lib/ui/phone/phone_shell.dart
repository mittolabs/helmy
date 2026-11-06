import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/remote/remote_repositories.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/services/remote/remote_link.dart';
import '../../domain/models/settings.dart';
import '../../utils/format.dart';
import '../../version.dart';
import '../chat/view_models/chat_view_model.dart';
import '../chat/widgets/chat_items.dart';
import '../chat/widgets/composer.dart';
import '../chat/widgets/media.dart';
import '../core/ashlar/app.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/markdown.dart';
import '../core/ashlar/message_scroller.dart';
import '../core/ashlar/pressable.dart';
import '../core/ashlar/sheet.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/theme.dart';
import 'mac_screen_view.dart';
import 'phone_app.dart' show PhoneSafeArea;

/// How the phone looks: as the system does, or always light or dark.
enum PhoneLook { system, light, dark }

/// Settings the chat's rows read on the Mac; on the phone, the defaults.
class PhoneSettings extends SettingsRepository {
  @override
  AppSettings get settings => const AppSettings();
  @override
  Future<void> load() async {}
  @override
  Future<void> save(AppSettings settings) async {}
}

/// Helmy on a phone, laid out the way phone apps for talking to an
/// assistant are: a new chat to start with, the chats in a drawer from the
/// left, settings in a sheet from the bottom. Everything in a chat is the
/// Mac's own chat, drawn here.
class PhoneShell extends StatefulWidget {
  const PhoneShell({
    super.key,
    required this.link,
    required this.onUnpair,
    required this.look,
    required this.onLook,
  });
  final RemoteLink link;
  final VoidCallback onUnpair;
  final PhoneLook look;
  final ValueChanged<PhoneLook> onLook;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  RemoteLink get link => widget.link;
  late final _sessions = RemoteSessions(link);
  late final _conversations = RemoteConversations(link);
  late final _apps = RemoteChatApps(link);

  /// The thread open now; null for a new chat.
  String? _open;

  /// A new chat's first message, sent and waiting for the Mac to make it.
  String? _starting;

  @override
  void initState() {
    super.initState();
    link.made.addListener(_made);
  }

  @override
  void dispose() {
    link.made.removeListener(_made);
    _conversations.dispose();
    _sessions.dispose();
    super.dispose();
  }

  void _made() {
    if (link.made.value case final id? when _starting != null) {
      setState(() {
        _open = id;
        _starting = null;
      });
    }
  }

  void _start(String text) {
    if (text.trim().isEmpty) return;
    setState(() => _starting = text.trim());
    unawaited(link.newChat(text.trim()));
  }

  void _openThread(String? id) {
    setState(() {
      _open = id;
      _starting = null;
    });
  }

  void _drawer() => unawaited(
    showSheet<void>(
      context: context,
      side: .left,
      // Each way out closes the drawer first, then goes.
      builder: (drawer) => _Drawer(
        link: link,
        open: _open,
        onOpen: (id) {
          Navigator.of(drawer).pop();
          _openThread(id);
        },
        onScreen: () {
          Navigator.of(drawer).pop();
          _screen();
        },
        onSettings: () {
          Navigator.of(drawer).pop();
          _settings();
        },
      ),
    ),
  );

  void _screen() => unawaited(
    Navigator.of(context).push(AshlarPageRoute(builder: (_) => MacScreenView(link: link))),
  );

  void _settings() => unawaited(
    showSheet<void>(
      context: context,
      side: .bottom,
      builder: (sheet) => _Settings(
        link: link,
        look: widget.look,
        onLook: widget.onLook,
        onUnpair: () {
          Navigator.of(sheet).pop();
          widget.onUnpair();
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final open = _open;
    return MultiProvider(
      providers: [ChangeNotifierProvider<SettingsRepository>(create: (_) => PhoneSettings())],
      child: ColoredBox(
        color: t.colors.background,
        child: PhoneSafeArea(
          child: ListenableBuilder(
            listenable: link,
            builder: (context, _) {
              final title = open == null ? 'Helmy' : (_sessions.byId(open)?.title ?? 'Chat');
              return Column(
                crossAxisAlignment: .stretch,
                children: [
                  _Header(
                    title: title,
                    status: switch (link.state) {
                      LinkState.connected => null,
                      LinkState.connecting => 'Reaching ${link.pairing.name}…',
                      LinkState.unreachable => link.trouble ?? 'Not connected',
                    },
                    onMenu: _drawer,
                    trailing: open == null
                        ? _Round(
                            icon: AshlarIconsRoundedStroke.deviceLaptop,
                            label: 'See and use ${link.pairing.name}',
                            onPressed: _screen,
                          )
                        : _Round(
                            icon: AshlarIconsRoundedStroke.squarePen,
                            label: 'New chat',
                            onPressed: () => _openThread(null),
                          ),
                  ),
                  Expanded(
                    child: open == null
                        ? _Home(link: link, starting: _starting, onSend: _start)
                        : _Chat(
                            key: ValueKey(open),
                            sessionId: open,
                            sessions: _sessions,
                            conversations: _conversations,
                            apps: _apps,
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The bar at the top: the menu, what is open, and one action.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.status,
    required this.onMenu,
    required this.trailing,
  });
  final String title;
  final String? status;
  final VoidCallback onMenu;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .fromLTRB(16, 6, 16, 6),
      child: Row(
        spacing: 12,
        children: [
          _Round(icon: AshlarIconsRoundedStroke.menu2, label: 'Chats', onPressed: onMenu),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: t.text.base.copyWith(fontWeight: .w600),
                ),
                if (status case final s?)
                  Text(
                    s,
                    maxLines: 1,
                    overflow: .ellipsis,
                    textAlign: .center,
                    style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// A round button with a fine ring, for the bar at the top.
class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AshlarTheme.of(context).colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: .circle,
          color: state.pressed ? c.accent : c.background,
          border: Border.all(color: c.border),
        ),
        alignment: .center,
        child: AshlarIcon(icon, size: 20, color: c.foreground),
      ),
    );
  }
}

/// A new chat: Helmy waving, the question, and the box to say it in.
class _Home extends StatefulWidget {
  const _Home({required this.link, required this.starting, required this.onSend});
  final RemoteLink link;
  final String? starting;
  final ValueChanged<String> onSend;

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final starting = widget.starting;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const .symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: .min,
                spacing: 12,
                children: [
                  // Always there; smaller while the keyboard takes room.
                  Image.asset(
                    'assets/helmy/hello.png',
                    width: keyboard ? 80 : 120,
                    height: keyboard ? 80 : 120,
                    semanticLabel: 'Helmy',
                  ),
                  Text(
                    starting == null ? 'What should we get done?' : 'Starting it on the Mac…',
                    textAlign: .center,
                    style: t.text.xl.copyWith(fontWeight: .w500),
                  ),
                  if (starting == null)
                    Text(
                      'Dream it, do it: tell me what you want, on '
                      '${widget.link.pairing.name} or in your accounts.',
                      textAlign: .center,
                      style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.45),
                    )
                  else
                    const Spinner(size: 18),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const .fromLTRB(12, 0, 12, 10),
          // A tap anywhere else puts the keyboard away.
          child: TapRegion(
            onTapOutside: (_) => _focus.unfocus(),
            child: Composer(
              controller: _text,
              focusNode: _focus,
              placeholder: 'Ask Helmy',
              onSubmit: (text) {
                widget.onSend(text);
                _text.clear();
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// A chat: the Mac's own conversation, row for row, and its composer.
class _Chat extends StatefulWidget {
  const _Chat({
    super.key,
    required this.sessionId,
    required this.sessions,
    required this.conversations,
    required this.apps,
  });
  final String sessionId;
  final RemoteSessions sessions;
  final RemoteConversations conversations;
  final RemoteChatApps apps;

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  late final vm = ChatViewModel(
    sessionId: widget.sessionId,
    sessions: widget.sessions,
    conversations: widget.conversations,
  );
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroller = MessageScrollerController();

  @override
  void dispose() {
    unawaited(widget.conversations.forget(widget.sessionId));
    vm.dispose();
    _text.dispose();
    _focus.dispose();
    _scroller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vm,
      builder: (context, _) {
        final session = vm.session;
        if (session == null) return const Center(child: Spinner(size: 20));
        final rows = buildRows(vm);
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(
              child: rows.isEmpty
                  ? const Center(child: Spinner(size: 20))
                  : MarkdownMedia(
                      show: (where, words) => Media(
                        where: where,
                        words: words,
                        cwd: session.cwd,
                        actions: vm,
                        apps: widget.apps,
                        session: session.id,
                      ),
                      // Scrolling the conversation by hand puts the keyboard away.
                      child: NotificationListener<ScrollUpdateNotification>(
                        onNotification: (n) {
                          if (n.dragDetails != null) _focus.unfocus();
                          return false;
                        },
                        child: MessageScroller(
                          controller: _scroller,
                          busy: vm.busy,
                          gap: 14,
                          padding: const .fromLTRB(16, 8, 16, 24),
                          semanticLabel: 'Conversation',
                          items: [
                            for (final r in rows)
                              MessageScrollerItem(id: r.id, anchor: r.anchor, child: r.child),
                          ],
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const .fromLTRB(12, 0, 12, 10),
              child: TapRegion(
                onTapOutside: (_) => _focus.unfocus(),
                child: Composer(
                  controller: _text,
                  focusNode: _focus,
                  placeholder: vm.busy
                      ? 'Helmy is working. Say more, or stop it'
                      : 'Reply to Helmy',
                  trailing: [
                    if (vm.busy)
                      ComposerButton(
                        icon: AshlarIconsRoundedStroke.playerStop,
                        label: 'Stop',
                        onPressed: vm.interrupt,
                      ),
                  ],
                  onSubmit: (text) {
                    if (text.trim().isEmpty) return;
                    unawaited(vm.send.execute(text));
                    _text.clear();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The drawer: where to go, then the chats, newest first.
class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.link,
    required this.open,
    required this.onOpen,
    required this.onScreen,
    required this.onSettings,
  });
  final RemoteLink link;
  final String? open;
  final ValueChanged<String?> onOpen;
  final VoidCallback onScreen;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final width = MediaQuery.sizeOf(context).width * .84;
    // At the left edge, the chat still showing beside it.
    return Align(
      alignment: .centerLeft,
      child: SizedBox(
        width: width,
        child: ColoredBox(
          color: c.background,
          child: SafeArea(
            child: ListenableBuilder(
              listenable: link,
              builder: (context, _) {
                final chats = [
                  for (final chat in link.chats)
                    if (chat.threads.any((x) => !x.archived)) chat,
                ]..sort((a, b) => _latest(b).compareTo(_latest(a)));
                final waiting = chats.where((r) => r.threads.any((x) => x.needsYou)).toList();
                // As the Mac's sidebar groups them.
                final working = chats
                    .where((r) => !waiting.contains(r) && r.threads.any((x) => x.busy))
                    .toList();
                final rest = chats
                    .where((r) => !waiting.contains(r) && !working.contains(r))
                    .toList();
                return Stack(
                  children: [
                    ListView(
                      padding: const .fromLTRB(12, 12, 12, 96),
                      children: [
                        Padding(
                          padding: const .fromLTRB(8, 4, 8, 16),
                          child: Row(
                            spacing: 10,
                            children: [
                              Image.asset(
                                t.brightness == .dark
                                    ? 'assets/helmy/head-dark.png'
                                    : 'assets/helmy/head-light.png',
                                width: 32,
                                height: 32,
                              ),
                              Text('Helmy', style: t.text.xxl),
                            ],
                          ),
                        ),
                        _Nav(
                          icon: AshlarIconsRoundedStroke.squarePen,
                          label: 'New chat',
                          onPressed: () => onOpen(null),
                        ),
                        _Nav(
                          icon: AshlarIconsRoundedStroke.deviceLaptop,
                          label: 'Your Mac',
                          onPressed: onScreen,
                        ),
                        if (waiting.isNotEmpty) ...[
                          const _Section('Needs you'),
                          for (final r in waiting) _Row(row: r, open: open, onOpen: onOpen),
                        ],
                        if (rest.isNotEmpty) ...[
                          _Section(
                            waiting.isEmpty && working.isEmpty ? 'Chats' : 'Everything else',
                          ),
                          for (final r in rest) _Row(row: r, open: open, onOpen: onOpen),
                        ],
                        if (working.isNotEmpty) ...[
                          const _Section('Working'),
                          for (final r in working) _Row(row: r, open: open, onOpen: onOpen),
                        ],
                      ],
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Row(
                        children: [
                          Pressable(
                            onPressed: onSettings,
                            semanticLabel: 'Settings',
                            builder: (context, state) => Container(
                              padding: const .fromLTRB(6, 6, 16, 6),
                              decoration: BoxDecoration(
                                color: state.pressed ? c.accent : c.secondary,
                                borderRadius: .circular(99),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                mainAxisSize: .min,
                                spacing: 10,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(color: c.background, shape: .circle),
                                    alignment: .center,
                                    child: AshlarIcon(
                                      AshlarIconsRoundedStroke.deviceLaptop,
                                      size: 16,
                                      color: c.foreground,
                                    ),
                                  ),
                                  Text(
                                    link.pairing.name,
                                    style: t.text.sm.copyWith(fontWeight: .w500),
                                  ),
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      shape: .circle,
                                      color: link.state == LinkState.connected
                                          ? const Color(0xFF34C759)
                                          : c.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Pressable(
                            onPressed: () => onOpen(null),
                            semanticLabel: 'New chat',
                            builder: (context, state) => Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: .circle,
                                color: c.primary.withValues(alpha: state.pressed ? .85 : 1),
                                boxShadow: t.shadowLg,
                              ),
                              alignment: .center,
                              child: AshlarIcon(
                                AshlarIconsRoundedStroke.squarePen,
                                size: 22,
                                color: c.primaryForeground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static DateTime _latest(RemoteChat r) =>
      r.threads.map((x) => x.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
}

class _Nav extends StatelessWidget {
  const _Nav({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: state.pressed ? t.colors.accent : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 14,
          children: [
            AshlarIcon(icon, size: 22, color: t.colors.foreground),
            Text(label, style: t.text.lg),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .fromLTRB(8, 20, 8, 6),
      child: Text(label, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
    );
  }
}

/// A chat in the drawer, as the Mac's sidebar has it: a spinner or a dot
/// when something goes on, its title and when, and one quiet line of what it
/// waits on or how it last answered.
class _Row extends StatelessWidget {
  const _Row({required this.row, required this.open, required this.onOpen});
  final RemoteChat row;
  final String? open;
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final threads = [...row.threads]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final latest = threads.first;
    final needsYou = row.threads.any((x) => x.needsYou);
    final busy = row.threads.any((x) => x.busy);
    final here = row.threads.any((x) => x.id == open);
    final line = needsYou
        ? 'Waiting for your approval'
        : row.chat.description.isNotEmpty
        ? row.chat.description
        : latest.last;
    final muted = t.text.sm.copyWith(color: c.mutedForeground);
    return Pressable(
      onPressed: () => onOpen(latest.id),
      semanticLabel: row.chat.title,
      builder: (context, state) => Container(
        padding: const .fromLTRB(10, 10, 10, 11),
        decoration: BoxDecoration(
          color: state.pressed || here ? c.accent : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 3,
          children: [
            Row(
              spacing: 8,
              children: [
                if (busy)
                  const Spinner(size: 12)
                else if (needsYou)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c.foreground, shape: .circle),
                  ),
                Expanded(
                  child: Text(
                    row.chat.title,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.base.copyWith(fontWeight: here ? .w600 : .w500),
                  ),
                ),
                Text(ago(latest.updatedAt), style: muted),
              ],
            ),
            if (line.isNotEmpty)
              Text(
                line,
                maxLines: 1,
                overflow: .ellipsis,
                style: muted.copyWith(color: needsYou ? c.foreground : c.mutedForeground),
              ),
          ],
        ),
      ),
    );
  }
}

/// Settings: the Mac this phone works with, and how the phone looks.
class _Settings extends StatelessWidget {
  const _Settings({
    required this.link,
    required this.look,
    required this.onLook,
    required this.onUnpair,
  });
  final RemoteLink link;
  final PhoneLook look;
  final ValueChanged<PhoneLook> onLook;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.sm.copyWith(color: c.mutedForeground);
    Widget card(List<Widget> children) => Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: .circular(t.radiusLg),
        border: Border.all(color: c.border),
      ),
      padding: const .all(16),
      child: Column(crossAxisAlignment: .stretch, spacing: 12, children: children),
    );
    return Sheet(
      title: const Text('Settings'),
      content: Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          card([
            Row(
              spacing: 10,
              children: [
                AshlarIcon(AshlarIconsRoundedStroke.deviceLaptop, size: 20, color: c.foreground),
                Expanded(
                  child: Text(link.pairing.name, style: t.text.base.copyWith(fontWeight: .w600)),
                ),
                Text(
                  link.state == LinkState.connected ? 'Connected' : 'Not connected',
                  style: muted,
                ),
              ],
            ),
            Text(
              'The work happens on this Mac. The phone shows it and says what to do.',
              style: muted,
            ),
            Button(
              variant: .outline,
              size: .sm,
              onPressed: onUnpair,
              child: const Text('Pair with another Mac'),
            ),
          ]),
          card([
            Text('Appearance', style: t.text.base.copyWith(fontWeight: .w600)),
            Row(
              spacing: 8,
              children: [
                for (final l in PhoneLook.values)
                  Expanded(
                    child: Button(
                      variant: l == look ? .secondary : .ghost,
                      size: .sm,
                      onPressed: () => onLook(l),
                      child: Text(switch (l) {
                        PhoneLook.system => 'System',
                        PhoneLook.light => 'Light',
                        PhoneLook.dark => 'Dark',
                      }),
                    ),
                  ),
              ],
            ),
          ]),
          Text('Helmy $shownVersion', style: muted, textAlign: .center),
        ],
      ),
    );
  }
}
