part of '../settings_screen.dart';

/// Reaching Helmy from a phone: on or off, and the code a phone pairs with.
class _Phone extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final s = vm.settings;
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    final RemoteHost? host;
    try {
      host = context.watch<RemoteHost>();
    } on ProviderNotFoundException {
      return Text('Not available in this build.', style: muted);
    }
    final pairing = host.pairing;
    return _Page(
      children: [
        _Row(
          title: 'Reach Helmy from your phone',
          description:
              'Your chats on your phone, as they happen: send, approve, stop. The work stays on '
              '${Desktop.current.thisComputer}; the phone shows it and says what to do.',
          control: Switch(
            value: s.remoteOn,
            semanticLabel: 'Reach Helmy from your phone',
            onChanged: (v) => vm.update(s.copyWith(remoteOn: v)),
          ),
        ),
        if (host.trouble case final trouble?) Text(trouble, style: muted),
        if (s.remoteOn)
          _Row(
            title: 'See and use this Mac from your phone',
            description:
                'A paired phone can show this screen and click and type on it. A bar at the top '
                'says when one is watching, with Stop. Needs Screen Recording to show it and '
                'Accessibility to use it.',
            control: Switch(
              value: s.remoteScreen,
              semanticLabel: 'See and use this Mac from your phone',
              onChanged: (v) => vm.update(s.copyWith(remoteScreen: v)),
            ),
          ),
        if (s.remoteOn && pairing != null) ...[
          const _Heading('Pair a phone'),
          Row(
            crossAxisAlignment: .start,
            spacing: 24,
            children: [
              QrView(pairing.link, size: 180),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 10,
                  children: [
                    Text(
                      'Open Helmy on your phone and scan this. The phone then finds '
                      '${pairing.name} on the same Wi-Fi, or anywhere over Tailscale.',
                      style: muted,
                    ),
                    Text(
                      'What goes between them is sealed with a key only this code carries: '
                      'nothing readable crosses the network, and a phone without it is turned '
                      'away. Treat the code like a password.',
                      style: muted,
                    ),
                    Text(
                      'Each phone pairs with a code of its own: once one has scanned it, '
                      'the next phone gets a new one.',
                      style: muted,
                    ),
                    Text(
                      'Reached at ${pairing.hosts.join(', ')}, port ${pairing.port}.',
                      style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                    ),
                    Button(
                      variant: .outline,
                      size: .sm,
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: 'Pair again?',
                          body: 'Every phone paired before is turned away until it scans the new code.',
                          action: 'Pair again',
                        );
                        if (ok) await host!.pairAgain();
                      },
                      child: const Text('Forget every phone'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Heading('Paired phones'),
          if (host.phones.isEmpty && host.olderConnected == 0)
            _Block(
              title: 'None yet',
              child: Text('A phone shows here once it has scanned its code.', style: muted),
            ),
          for (final p in host.phones)
            _Row(
              title: p.name.isEmpty ? 'A phone' : p.name,
              description: host.isConnected(p.id)
                  ? 'Connected now. Paired ${ago(p.pairedAt!, now: DateTime.now())} ago.'
                  : 'Last seen ${ago(p.lastSeen ?? p.pairedAt!, now: DateTime.now())} ago. '
                        'Paired ${ago(p.pairedAt!, now: DateTime.now())} ago.',
              control: Button(
                variant: .ghost,
                size: .sm,
                semanticLabel: 'Unpair ${p.name}',
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Unpair ${p.name.isEmpty ? 'this phone' : p.name}?',
                    body:
                        'It is turned away from now on, and has to scan a code again to come '
                        'back. Other phones stay paired.',
                    action: 'Unpair',
                    destructive: true,
                  );
                  if (ok) await host!.unpair(p.id);
                },
                child: const Text('Unpair'),
              ),
            ),
          if (host.olderConnected > 0)
            Text(
              '${host.olderConnected} connected with an older code, from before phones had '
              'codes of their own. Forget every phone to turn it away, then pair again.',
              style: muted,
            ),
        ],
      ],
    );
  }
}
