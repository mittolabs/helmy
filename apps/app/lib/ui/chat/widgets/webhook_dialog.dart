import '../../../utils/format.dart';

import 'dart:async';

import '../../../data/repositories/settings_repository.dart';
import '../../core/ashlar/input.dart';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/services/webhooks.dart';
import '../../../utils/platform.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/helmy_dialog.dart';
import '../view_models/chat_view_model.dart';

/// A thread's webhook: its address, how to send to it, and a way to turn it
/// off; or, without one, what it is for and a way to give it one.
Future<void> showWebhook(BuildContext context, ChatViewModel vm) {
  final hooks = context.read<Webhooks>();
  return showAshlarDialog<void>(
    context: context,
    builder: (context) => CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: vm,
          builder: (context, _) => _WebhookDialog(vm: vm, hooks: hooks),
        ),
      ),
    ),
  );
}

class _WebhookDialog extends StatelessWidget {
  const _WebhookDialog({required this.vm, required this.hooks});
  final ChatViewModel vm;
  final Webhooks hooks;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground, height: 1.45);
    final secret = vm.session?.webhook;
    final on = vm.session?.hasWebhook ?? false;
    const what =
        "Events sent to this thread's address arrive here as messages, and its agent takes "
        'each up in turn: a pull request opened, a payment made, a build that failed.';
    if (!on) {
      return HelmyDialog(
        title: 'Webhook',
        icon: AshlarIconsRoundedStroke.webhook,
        body: hooks.trouble ?? what,
        actions: [
          DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
          if (hooks.trouble == null)
            DialogButton('Give it an address', main: true, onPressed: () => vm.setWebhook(true)),
        ],
      );
    }
    final address = hooks.address(secret!);
    final curl =
        "curl -X POST $address -H 'Content-Type: application/json' -d '{\"hello\": \"thread\"}'";
    Widget mono(String text, String copyLabel) => Container(
      padding: const .fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: .5),
        border: .all(color: c.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Expanded(
            child: Text(
              text,
              style: t.text.xs.copyWith(fontFamily: monoFonts.first, fontFamilyFallback: monoFonts),
            ),
          ),
          Button(
            variant: .ghost,
            size: .iconXs,
            semanticLabel: copyLabel,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) showToast(context, title: 'Copied');
            },
            child: const AshlarIcon(AshlarIconsRoundedStroke.copy, size: 13),
          ),
        ],
      ),
    );
    return HelmyDialog(
      title: 'Webhook',
      icon: AshlarIconsRoundedStroke.webhook,
      content: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Text(what, style: muted),
          if (hooks.trouble case final why?) Text(why, style: muted.copyWith(color: c.destructive)),
          mono(address, 'Copy the address'),
          Text('To try it:', style: muted),
          mono(curl, 'Copy the command'),
          Text(
            'Only this Mac reaches it. For a service outside to send here, point a tunnel you '
            'run (Tailscale Funnel, Cloudflare Tunnel, ngrok) at port ${hooks.port} and give '
            'the service its address, ending in /hooks/ and this secret. Up to '
            '${Webhooks.perHour} events an hour, each up to ${Webhooks.maxBytes ~/ 1024} KB.',
            style: muted,
          ),
          _Signing(sessionId: vm.sessionId),
          // What came, latest first, since Helmy opened.
          if (hooks.deliveriesOf(secret) case final got when got.isNotEmpty) ...[
            Text('Latest', style: t.text.sm.copyWith(fontWeight: .w500)),
            for (final d in got.take(6))
              Row(
                spacing: 8,
                children: [
                  Text(clock(d.at, seconds: true), style: muted),
                  Expanded(
                    child: Text(
                      [?d.event, d.said].join(' · '),
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: muted.copyWith(color: d.code >= 400 ? c.destructive : null),
                    ),
                  ),
                  Text('${d.code}', style: muted),
                ],
              ),
          ],
        ],
      ),
      actions: [
        DialogButton('Turn off', destructive: true, onPressed: () => vm.setWebhook(false)),
        DialogButton('Done', main: true, onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}

/// The secret the sender signs events with, if the user wants them
/// checked: events without a matching signature are turned away.
class _Signing extends StatefulWidget {
  const _Signing({required this.sessionId});
  final String sessionId;

  @override
  State<_Signing> createState() => _SigningState();
}

class _SigningState extends State<_Signing> {
  late final _settings = context.read<SettingsRepository>();
  late final _text = TextEditingController(
    text: _settings.settings.hookSigning[widget.sessionId] ?? '',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save(String v) {
    final s = _settings.settings;
    final next = {...s.hookSigning};
    v.trim().isEmpty ? next.remove(widget.sessionId) : next[widget.sessionId] = v.trim();
    unawaited(_settings.save(s.copyWith(hookSigning: next)));
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Text(
          'Signing secret, if the sender signs its events (GitHub, Stripe and most do): '
          'then an event whose signature does not match is turned away.',
          style: t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.45),
        ),
        Input(
          controller: _text,
          size: .sm,
          obscureText: true,
          placeholder: 'None: any event to the address is taken',
          semanticLabel: 'Signing secret',
          onChanged: _save,
        ),
      ],
    );
  }
}
