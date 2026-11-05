import 'dart:async';
import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/remote/remote_crypto.dart';
import '../../data/services/remote/remote_link.dart';
import '../../domain/chat_icons.dart';
import '../../domain/models/chat_item.dart';
import '../../utils/format.dart';
import '../chat/widgets/chat_items.dart' show stepTitle;
import '../core/ashlar/app.dart';
import '../core/ashlar/app_theme.dart';
import '../core/ashlar/bubble.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/input.dart';
import '../core/ashlar/markdown.dart';
import '../core/ashlar/message.dart';
import '../core/ashlar/pressable.dart';
import '../core/ashlar/spinner.dart';
import '../core/ashlar/textarea.dart';
import '../core/ashlar/theme.dart';
import '../core/tinted_icon.dart';

/// Helmy on a phone: a remote for Helmy on a Mac. The chats there, each
/// conversation as it goes, and sending, approving and stopping. The work
/// stays on the Mac; nothing runs here but this window onto it.
Future<void> runPhone() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await _PairingFile.read();
  runApp(_PhoneApp(saved: saved));
}

/// The pairing, kept in the app's own folder so the phone stays paired.
abstract final class _PairingFile {
  static Future<File> _file() async =>
      File('${(await getApplicationSupportDirectory()).path}/pairing.txt');

  static Future<Pairing?> read() async {
    try {
      return Pairing.parse(await (await _file()).readAsString());
    } on Object {
      return null;
    }
  }

  static Future<void> write(Pairing? p) async {
    final f = await _file();
    if (p == null) {
      if (f.existsSync()) await f.delete();
      return;
    }
    await f.create(recursive: true);
    await f.writeAsString(p.link);
  }
}

class _PhoneApp extends StatefulWidget {
  const _PhoneApp({required this.saved});
  final Pairing? saved;

  @override
  State<_PhoneApp> createState() => _PhoneAppState();
}

class _PhoneAppState extends State<_PhoneApp> {
  RemoteLink? _link;

  @override
  void initState() {
    super.initState();
    if (widget.saved case final p?) _use(p);
  }

  void _use(Pairing p) {
    _link?.dispose();
    _link = RemoteLink(p);
    unawaited(_link!.connect());
  }

  Future<void> _paired(Pairing p) async {
    await _PairingFile.write(p);
    setState(() => _use(p));
  }

  Future<void> _unpair() async {
    await _PairingFile.write(null);
    setState(() {
      _link?.dispose();
      _link = null;
    });
  }

  @override
  void dispose() {
    _link?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AshlarApp(
    title: 'Helmy',
    theme: appTheme,
    darkTheme: appDarkTheme,
    home: _link == null
        ? _PairScreen(onPaired: _paired)
        : _ChatList(link: _link!, onUnpair: _unpair),
  );
}

/// Pairing: the Mac's code, scanned, or its link pasted.
class _PairScreen extends StatefulWidget {
  const _PairScreen({required this.onPaired});
  final ValueChanged<Pairing> onPaired;

  @override
  State<_PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<_PairScreen> {
  final _pasted = TextEditingController();
  String? _wrong;
  bool _scanning = false;

  void _try(String text) {
    final p = Pairing.parse(text);
    if (p == null) {
      setState(() => _wrong = "That isn't a Helmy pairing code.");
      return;
    }
    widget.onPaired(p);
  }

  @override
  void dispose() {
    _pasted.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    return ColoredBox(
      color: t.colors.background,
      child: SafeArea(
        child: Padding(
          padding: const .all(24),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              Image.asset(
                t.brightness == .dark
                    ? 'assets/helmy/head-dark.png'
                    : 'assets/helmy/head-light.png',
                width: 56,
                height: 56,
              ),
              Text(
                'Pair with Helmy on your Mac',
                style: t.text.xl.copyWith(fontWeight: .w600),
                textAlign: .center,
              ),
              Text(
                'On the Mac, open Settings, then Phone, and turn it on. Scan the code it shows.',
                style: muted,
                textAlign: .center,
              ),
              if (_scanning)
                Expanded(
                  child: ClipRRect(
                    borderRadius: .circular(t.radiusLg),
                    child: MobileScanner(
                      onDetect: (found) {
                        for (final b in found.barcodes) {
                          if (b.rawValue case final v? when Pairing.parse(v) != null) {
                            _try(v);
                            return;
                          }
                        }
                      },
                    ),
                  ),
                )
              else ...[
                Button(
                  onPressed: () => setState(() => _scanning = true),
                  child: const Text('Scan the code'),
                ),
                Text('Or paste the link under the code:', style: muted),
                Input(controller: _pasted, placeholder: 'helmy-pair:v1?…'),
                Button(
                  variant: .outline,
                  onPressed: () => _try(_pasted.text),
                  child: const Text('Pair'),
                ),
              ],
              if (_wrong case final w?)
                Text(w, style: t.text.sm.copyWith(color: t.colors.destructive)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Mac's chats, as its own list has them: what needs you first.
class _ChatList extends StatelessWidget {
  const _ChatList({required this.link, required this.onUnpair});
  final RemoteLink link;
  final VoidCallback onUnpair;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final rows = [
          for (final chat in link.chats)
            if (chat.threads.any((x) => !x.archived)) chat,
        ];
        int rank(RemoteChat r) => r.threads.any((x) => x.needsYou)
            ? 0
            : r.threads.any((x) => x.busy)
            ? 2
            : 1;
        DateTime latest(RemoteChat r) =>
            r.threads.map((x) => x.updatedAt).reduce((a, b) => a.isAfter(b) ? a : b);
        rows.sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0 ? byRank : latest(b).compareTo(latest(a));
        });
        return ColoredBox(
          color: c.background,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .fromLTRB(20, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: .start,
                          children: [
                            Text('Chats', style: t.text.xl.copyWith(fontWeight: .w600)),
                            Text(switch (link.state) {
                              LinkState.connected => 'On ${link.pairing.name}',
                              LinkState.connecting => 'Reaching ${link.pairing.name}…',
                              LinkState.unreachable => link.trouble ?? 'Not connected',
                            }, style: t.text.xs.copyWith(color: c.mutedForeground)),
                          ],
                        ),
                      ),
                      Button(
                        variant: .ghost,
                        size: .icon,
                        semanticLabel: 'New chat',
                        onPressed: () => _openNew(context),
                        child: const AshlarIcon(AshlarIconsRoundedStroke.squarePen, size: 20),
                      ),
                      Button(
                        variant: .ghost,
                        size: .icon,
                        semanticLabel: 'Pair with another Mac',
                        onPressed: onUnpair,
                        child: const AshlarIcon(AshlarIconsRoundedStroke.unlink, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: link.state == LinkState.connected
                              ? Text(
                                  'No chats yet.',
                                  style: t.text.sm.copyWith(color: c.mutedForeground),
                                )
                              : const Spinner(size: 20),
                        )
                      : ListView.builder(
                          padding: const .symmetric(horizontal: 8),
                          itemCount: rows.length,
                          itemBuilder: (context, i) =>
                              _ChatRow(row: rows[i], onOpen: () => _open(context, rows[i])),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, RemoteChat row) {
    final thread = [...row.threads]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    unawaited(
      Navigator.of(context).push(
        AshlarPageRoute(
          builder: (_) => _ChatView(link: link, threadId: thread.first.id, title: row.chat.title),
        ),
      ),
    );
  }

  void _openNew(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        AshlarPageRoute(
          builder: (_) => _ChatView(link: link, threadId: null, title: 'New chat'),
        ),
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.row, required this.onOpen});
  final RemoteChat row;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final chat = row.chat;
    final latest = row.threads.reduce((a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b);
    final needsYou = row.threads.any((x) => x.needsYou);
    final busy = row.threads.any((x) => x.busy);
    final line = needsYou
        ? 'Waiting for your approval'
        : busy
        ? 'Working'
        : chat.description.isNotEmpty
        ? chat.description
        : latest.last;
    return Pressable(
      onPressed: onOpen,
      semanticLabel: chat.title,
      builder: (context, state) => Container(
        padding: const .fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: state.pressed ? c.accent : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 3,
          children: [
            Row(
              spacing: 8,
              children: [
                TintedIcon(
                  chatIconOf(chat.icon),
                  hue: hueOf(chat.topic),
                  muted: chat.topic.isEmpty,
                  size: 20,
                ),
                Expanded(
                  child: Text(
                    chat.topic.isNotEmpty ? chat.topic : folderName(latest.cwd),
                    style: t.text.xs.copyWith(color: c.mutedForeground),
                  ),
                ),
                if (busy) const Spinner(size: 12),
                if (needsYou)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
                Text(ago(latest.updatedAt), style: t.text.xs.copyWith(color: c.mutedForeground)),
              ],
            ),
            Text(
              chat.title,
              maxLines: 1,
              overflow: .ellipsis,
              style: t.text.base.copyWith(fontWeight: .w600),
            ),
            if (line.isNotEmpty)
              Text(
                line,
                maxLines: 2,
                overflow: .ellipsis,
                style: t.text.sm.copyWith(color: needsYou ? c.foreground : c.mutedForeground),
              ),
          ],
        ),
      ),
    );
  }
}

/// One conversation, as it goes on the Mac; [threadId] null for a new chat,
/// started by its first message.
class _ChatView extends StatefulWidget {
  const _ChatView({required this.link, required this.threadId, required this.title});
  final RemoteLink link;
  final String? threadId;
  final String title;

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  String? _id;

  RemoteLink get link => widget.link;

  @override
  void initState() {
    super.initState();
    _id = widget.threadId;
    if (_id case final id?) unawaited(link.open(id));
    link.made.addListener(_made);
    link.addListener(_follow);
  }

  void _made() {
    final id = link.made.value;
    if (id == null || _id != null) return;
    setState(() => _id = id);
    unawaited(link.open(id));
  }

  /// Keeps the newest in view as it arrives, when it already was.
  void _follow() {
    if (!_scroll.hasClients) return;
    final atEnd = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 80;
    if (atEnd) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    if (_id case final id?) unawaited(link.close(id));
    link.made.removeListener(_made);
    link.removeListener(_follow);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    if (_id case final id?) {
      unawaited(link.send(id, text));
    } else {
      unawaited(link.newChat(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final conv = _id == null ? null : link.of(_id!);
        final items = conv?.items ?? const <ChatItem>[];
        final title = [
          for (final r in link.chats)
            if (r.threads.any((x) => x.id == _id)) r.chat.title,
        ].firstOrNull;
        return ColoredBox(
          color: c.background,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                Padding(
                  padding: const .fromLTRB(4, 4, 12, 4),
                  child: Row(
                    children: [
                      Button(
                        variant: .ghost,
                        size: .icon,
                        semanticLabel: 'Chats',
                        onPressed: () => Navigator.of(context).pop(),
                        child: const AshlarIcon(AshlarIconsRoundedStroke.chevronLeft, size: 22),
                      ),
                      Expanded(
                        child: Text(
                          title ?? widget.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: t.text.base.copyWith(fontWeight: .w600),
                        ),
                      ),
                      if (conv?.busy ?? false)
                        Button(
                          variant: .outline,
                          size: .sm,
                          onPressed: () => unawaited(link.interrupt(_id!)),
                          child: const Text('Stop'),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const .fromLTRB(16, 8, 16, 16),
                    children: [
                      for (final item in items)
                        if (_row(context, item) case final w?)
                          Padding(padding: const .only(bottom: 12), child: w),
                      if (conv?.busy ?? false)
                        Text('Working…', style: t.text.sm.copyWith(color: c.mutedForeground)),
                    ],
                  ),
                ),
                Padding(
                  padding: const .fromLTRB(12, 4, 12, 12),
                  child: Row(
                    crossAxisAlignment: .end,
                    spacing: 8,
                    children: [
                      Expanded(
                        child: Textarea(
                          controller: _text,
                          minLines: 1,
                          maxLines: 6,
                          resizable: false,
                          placeholder: 'Message Helmy',
                        ),
                      ),
                      Button(
                        size: .icon,
                        semanticLabel: 'Send',
                        onPressed: _send,
                        child: const AshlarIcon(AshlarIconsRoundedStroke.arrowUp, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// What one part of the conversation shows as, on a phone.
  Widget? _row(BuildContext context, ChatItem item) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    return switch (item) {
      UserMessage(:final text) when text.trim().isNotEmpty => Message(
        align: .end,
        child: Bubble(variant: .muted, child: Text(text)),
      ),
      AssistantText(:final text) when text.trim().isNotEmpty => Markdown(text),
      ToolCall call => Row(
        spacing: 6,
        children: [
          AshlarIcon(
            AshlarIconsRoundedStroke.chevronRight,
            size: 14,
            color: t.colors.mutedForeground,
          ),
          // In Helmy's words, as on the Mac: "Ran a command", never the tool's name.
          Expanded(
            child: Text(
              stepTitle(call, done: call.done),
              style: muted,
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
        ],
      ),
      PermissionPrompt p when p.decision == .pending => _Approval(
        prompt: p,
        onAnswer: (answer) => unawaited(link.answer(_id!, p, answer)),
      ),
      Notice(:final text) => Text(text, style: muted),
      _ => null,
    };
  }
}

/// A step waiting on the person: what it wants, and the answers.
class _Approval extends StatelessWidget {
  const _Approval({required this.prompt, required this.onAnswer});
  final PermissionPrompt prompt;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final what = prompt.input['command'] ?? prompt.input['file_path'] ?? prompt.input['url'];
    return Container(
      padding: const .all(12),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(
            // As the Mac says it, never the tool's own name.
            'Waiting for you: ${stepTitle(ToolCall(id: prompt.requestId, name: prompt.toolName, input: prompt.input), done: false)}',
            style: t.text.sm.copyWith(fontWeight: .w600),
          ),
          if (what != null)
            Text('$what', style: t.text.xs.copyWith(fontFamily: 'monospace'), maxLines: 6),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: Button(onPressed: () => onAnswer('allow'), child: const Text('Allow')),
              ),
              Expanded(
                child: Button(
                  variant: .outline,
                  onPressed: () => onAnswer('deny'),
                  child: const Text('Deny'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
