part of '../settings_screen.dart';

/// Helmy itself: its version, what leaves this computer, and the open-source
/// work it is built on.
class _About extends StatefulWidget {
  const _About();

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  /// Each package's licenses, by package, once read.
  Future<Map<String, List<String>>>? _licenses;
  String? _open;

  Future<Map<String, List<String>>> _read() async {
    final out = <String, List<String>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final text = [for (final p in entry.paragraphs) p.text].join('\n\n');
      for (final p in entry.packages) {
        (out[p] ??= []).add(text);
      }
    }
    return Map.fromEntries(
      out.entries.toList()..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5);
    return _Page(
      children: [
        _Block(
          title: 'Helmy',
          child: Row(
            spacing: 14,
            children: [
              Image.asset('assets/helmy/hello.png', width: 48, height: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text('Version $shownVersion', style: t.text.sm.copyWith(fontWeight: .w500)),
                    Text(
                      '© ${DateTime.now().year} Mittolabs. Open source, BSD license.',
                      style: muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _Heading('What leaves this computer'),
        _Block(
          title: 'Privacy',
          child: Text(
            "Helmy has no account and keeps your chats on this computer. What leaves it: "
            'each message goes to the connection that answers it, under its maker\'s terms; '
            'error reports, when they are on in General; checks for newer versions of '
            'Claude Code, Codex and Ollama; and the ACP registry\'s list, when you add an agent.',
            style: muted,
          ),
        ),
        const _Heading('Open source'),
        _Block(
          title: 'Licenses',
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 8,
            children: [
              Text(
                'The open-source packages Helmy is built with, and their licenses.',
                style: muted,
              ),
              if (_licenses == null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Button(
                    variant: .outline,
                    size: .sm,
                    onPressed: () => setState(() {
                      _licenses = _read();
                    }),
                    child: const Text('Show licenses'),
                  ),
                )
              else
                FutureBuilder(
                  future: _licenses,
                  builder: (context, snap) {
                    final all = snap.data;
                    if (all == null) return Text('Reading...', style: muted);
                    if (all.isEmpty) {
                      return Text('This build carries no license notices.', style: muted);
                    }
                    return Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        for (final MapEntry(key: name, value: texts) in all.entries) ...[
                          Pressable(
                            onPressed: () => setState(() => _open = _open == name ? null : name),
                            semanticLabel: name,
                            builder: (context, state) => Padding(
                              padding: const .symmetric(vertical: 5),
                              child: Row(
                                spacing: 6,
                                children: [
                                  AshlarIcon(
                                    _open == name
                                        ? AshlarIconsRoundedStroke.chevronDown
                                        : AshlarIconsRoundedStroke.chevronRight,
                                    size: 14,
                                    color: t.colors.mutedForeground,
                                  ),
                                  Expanded(child: Text(name, style: t.text.sm)),
                                  if (texts.length > 1)
                                    Text(
                                      '${texts.length} licenses',
                                      style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_open == name)
                            Padding(
                              padding: const .fromLTRB(20, 4, 0, 12),
                              child: SelectableRegion(
                                selectionControls: emptyTextSelectionControls,
                                child: Text(
                                  texts.join('\n\n---\n\n'),
                                  style: t.text.xs.copyWith(
                                    fontFamily: 'monospace',
                                    fontFamilyFallback: monoFonts,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
