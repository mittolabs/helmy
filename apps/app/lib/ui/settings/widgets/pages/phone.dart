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
          title: 'Use Helmy from your phone',
          description:
              'Your chats on your phone, as they happen: send, approve, stop. The work stays on '
              '${Desktop.current.thisComputer}; the phone shows it and says what to do.',
          control: Switch(
            value: s.remoteOn,
            semanticLabel: 'Use Helmy from your phone',
            onChanged: (v) => vm.update(s.copyWith(remoteOn: v)),
          ),
        ),
        if (host.trouble case final trouble?) Text(trouble, style: muted),
        if (s.remoteOn)
          _Row(
            title: 'Screen sharing',
            description:
                'A paired phone can show this screen and click and type on it. A bar at the top '
                'says when one is watching, with Stop. Needs Screen Recording to show it and '
                'Accessibility to use it.',
            control: Switch(
              value: s.remoteScreen,
              semanticLabel: 'Screen sharing',
              onChanged: (v) => vm.update(s.copyWith(remoteScreen: v)),
            ),
          ),
        if (s.remoteOn)
          _Row(
            title: 'From anywhere',
            description:
                'Through Helmy Connect (connect.helmy.ke), a paired phone reaches this computer '
                'from any network, and its browser opens Helmy over HTTPS. What passes is sealed '
                'with the phone\'s own key, which the relay never has. Off, only the same Wi-Fi '
                '(or Tailscale) works.',
            control: Switch(
              value: s.remoteAnywhere,
              semanticLabel: 'From anywhere',
              onChanged: (v) => vm.update(s.copyWith(remoteAnywhere: v)),
            ),
          ),
        if (s.remoteOn && s.remoteAnywhere)
          if (host.relay case final relay?)
            Text(
              relay.connected
                  ? 'Connected to Helmy Connect: phones reach this computer from anywhere.'
                  : relay.trouble ?? 'Connecting to Helmy Connect…',
              style: muted,
            ),
        if (s.remoteOn && pairing != null) ...[
          const _Heading('Pair a phone'),
          Row(
            crossAxisAlignment: .start,
            spacing: 24,
            children: [
              QrView(pairing.webLink, size: 180),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 10,
                  children: [
                    Text(
                      "Scan this with your phone's camera and open the link: Helmy opens in "
                      "the phone's browser, with nothing to install. With the Helmy app, scan "
                      'it there instead. Either way, the phone finds ${pairing.name} '
                      '${pairing.relay != null ? 'from anywhere' : 'on the same Wi-Fi, or over Tailscale'}.',
                      style: muted,
                    ),
                    Text(
                      'The code works once, within 15 minutes. When the phone uses it, the '
                      'phone and this computer agree on a key of its own, which is never in '
                      'the code: a copy of it (a screenshot, the link left in a browser) opens '
                      'nothing afterwards. Then the next phone gets a new code.',
                      style: muted,
                    ),
                    if (pairing.relay == null)
                      Text(
                        'The browser page comes from this computer without encryption, so use '
                        'it on a network you trust (at home, at work, or over Tailscale), not '
                        'on public Wi-Fi. Turn on From anywhere for a page over HTTPS.',
                        style: muted,
                      ),
                    Text(
                      'In Chrome, with the Helmy extension, or on another computer: copy the '
                      'link instead and paste it there. It is the same one-time code.',
                      style: muted,
                    ),
                    Button(
                      variant: .outline,
                      size: .sm,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: pairing.link));
                        if (!context.mounted) return;
                        showToast(
                          context,
                          title: 'Link copied',
                          description: 'Paste it in Helmy in Chrome to pair.',
                        );
                      },
                      child: const Text('Copy the link for Chrome or another computer'),
                    ),
                    Text(
                      'Reached at ${pairing.hosts.where((h) => h != '127.0.0.1').join(', ')}, '
                      'port ${pairing.port}.',
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
        const _Heading('Other computers'),
        _Computers(vm: vm),
      ],
    );
  }
}

/// The person's other computers with Helmy: a background agent can work on
/// them too. Paired with the link each one's Phone page copies.
class _Computers extends StatefulWidget {
  const _Computers({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_Computers> createState() => _ComputersState();
}

class _ComputersState extends State<_Computers> {
  final _link = TextEditingController();
  String? _wrong;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final s = widget.vm.settings;
    var p = Pairing.parse(_link.text);
    if (p == null) {
      setState(() => _wrong = "That isn't a Helmy pairing link.");
      return;
    }
    // A one-time code: used now, for a key of this computer's own.
    if (p.isOffer) {
      setState(() => _wrong = null);
      final got = await RemoteLink.exchange(p);
      if (!mounted) return;
      if (got.pairing == null) {
        setState(() => _wrong = got.trouble);
        return;
      }
      p = got.pairing!;
    }
    await widget.vm.update(
      s.copyWith(
        computers: [
          for (final c in s.computers)
            if (Pairing.parse(c)?.name != p.name) c,
          p.link,
        ],
      ),
    );
    _link.clear();
    setState(() => _wrong = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    final s = widget.vm.settings;
    final paired = [for (final c in s.computers) (link: c, pairing: Pairing.parse(c))];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        Text(
          'A background agent can work on another of your computers with Helmy: say so in a chat '
          '("check the Windows build on my PC"). On that computer, open Settings, then Phone, turn it '
          'on, and copy its link; paste it here. What goes between them is sealed with that '
          "link's key.",
          style: muted,
        ),
        for (final c in paired)
          _Row(
            title: c.pairing?.name ?? 'A computer',
            description: c.pairing == null ? 'Its link no longer reads.' : 'Paired.',
            control: Button(
              variant: .ghost,
              size: .sm,
              semanticLabel: 'Remove ${c.pairing?.name ?? 'this computer'}',
              onPressed: () => widget.vm.update(
                s.copyWith(
                  computers: [
                    for (final x in s.computers)
                      if (x != c.link) x,
                  ],
                ),
              ),
              child: const Text('Remove'),
            ),
          ),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Input(
                controller: _link,
                placeholder: 'helmy-pair:v3?...',
                semanticLabel: "Another computer's pairing link",
                onSubmitted: (_) => unawaited(_add()),
              ),
            ),
            Button(
              variant: .outline,
              size: .sm,
              onPressed: () => unawaited(_add()),
              child: const Text('Add'),
            ),
          ],
        ),
        if (_wrong case final w?) Text(w, style: t.text.sm.copyWith(color: t.colors.destructive)),
      ],
    );
  }
}
