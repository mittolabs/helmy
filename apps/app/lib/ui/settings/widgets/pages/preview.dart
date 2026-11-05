part of '../settings_screen.dart';

/// What draws pages in the Preview panel, and which Chromium browser.
class _Preview extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    final t = AshlarTheme.of(context);
    return FutureBuilder(
      future: vm.chromiumBrowsers(),
      builder: (context, snap) {
        final browsers = snap.data ?? const <ChromiumBrowser>[];
        final chosen =
            browsers.where((b) => b.executable == s.chromiumBrowser).firstOrNull ??
            browsers.firstOrNull;
        return _Page(
          children: [
            const _Heading('Pages in the Preview panel', first: true),
            _Row(
              title: 'Show pages with',
              description: s.previewWith == .system
                  ? 'The built-in browser: screen readers, typing in any language and '
                        "zoom all work as in the system's apps."
                  : 'A Chromium browser on ${Desktop.current.thisComputer}, for Chrome\'s developer '
                        'tools on the live page. Pages show as a picture, so a screen reader '
                        'cannot read them.',
              control: _Choice<PreviewEngine>(
                value: s.previewWith,
                label: 'Show pages with',
                options: const {
                  PreviewEngine.system: 'Built-in browser',
                  PreviewEngine.chromium: 'Chromium',
                },
                onChanged: (v) => vm.update(s.copyWith(previewWith: v)),
              ),
            ),
            if (s.previewWith == .chromium)
              _Row(
                title: 'Chromium browser',
                description: snap.connectionState != .done
                    ? 'Looking for Chromium-based browsers...'
                    : browsers.isEmpty
                    ? 'None installed. The first time a page opens, Helmy offers to download '
                          "Chrome for Testing, Google's build of Chrome for apps to drive."
                    : 'It runs hidden, with a profile of its own: your own browsing, tabs and '
                          'logins are never touched.',
                control: browsers.isEmpty
                    ? const SizedBox.shrink()
                    : SizedBox(
                        width: 240,
                        child: Select<String>(
                          size: .sm,
                          value: chosen?.executable,
                          semanticLabel: 'Chromium browser',
                          options: [for (final b in browsers) SelectOption(b.executable, b.label)],
                          onChanged: (exe) => vm.update(s.copyWith(chromiumBrowser: exe)),
                        ),
                      ),
              ),
            if (s.previewWith == .chromium)
              _Row(
                title: 'Profile',
                description:
                    'Each keeps its own sign-ins, cookies and history: a work account in one, '
                    'a personal one in another. Pages open in the one chosen.',
                control: SizedBox(
                  width: 250,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Select<String>(
                          size: .sm,
                          value: s.browserProfile,
                          semanticLabel: 'Profile',
                          options: [
                            const SelectOption('', 'Main'),
                            for (final p in s.browserProfiles) SelectOption(p, p),
                          ],
                          onChanged: (p) async {
                            await vm.chromium?.stop();
                            await vm.update(s.copyWith(browserProfile: p));
                          },
                        ),
                      ),
                      Button(
                        variant: .outline,
                        size: .sm,
                        onPressed: () async {
                          final name = (await askText(
                            context,
                            title: 'A new profile',
                            action: 'Add',
                            body: 'Its own sign-ins, apart from the others.',
                          ))?.trim();
                          if (name == null || name.isEmpty || s.browserProfiles.contains(name)) {
                            return;
                          }
                          await vm.chromium?.stop();
                          await vm.update(
                            s.copyWith(
                              browserProfiles: [...s.browserProfiles, name],
                              browserProfile: name,
                            ),
                          );
                        },
                        child: const Text('New...'),
                      ),
                      Button(
                        variant: .ghost,
                        size: .sm,
                        onPressed: () async {
                          final name = s.browserProfile.isEmpty ? 'Main' : s.browserProfile;
                          final sure = await confirm(
                            context,
                            title: 'Clear $name?',
                            body: 'Its sign-ins, cookies and history go. Pages open signed out.',
                            action: 'Clear',
                            destructive: true,
                          );
                          if (sure) await vm.chromium?.clearProfile(s.browserProfile);
                        },
                        child: const Text('Clear'),
                      ),
                      if (s.browserProfile.isNotEmpty)
                        Button(
                          variant: .ghost,
                          size: .sm,
                          onPressed: () async {
                            final gone = s.browserProfile;
                            await vm.chromium?.clearProfile(gone);
                            await vm.update(
                              s.copyWith(
                                browserProfiles: [...s.browserProfiles]..remove(gone),
                                browserProfile: '',
                              ),
                            );
                          },
                          child: const Text('Remove'),
                        ),
                    ],
                  ),
                ),
              ),
            if (s.previewWith == .chromium && browsers.any((b) => b.helmys))
              Padding(
                padding: const .only(top: 8),
                child: Text(
                  'Chrome for Testing is kept in Helmy\'s own folder; Data and storage can '
                  'clear it.',
                  style: t.text.xs.copyWith(color: t.colors.mutedForeground),
                ),
              ),
            const _Heading('As it opens'),
            _Row(
              title: 'Zoom',
              control: SizedBox(
                width: 110,
                child: Select<double>(
                  size: .sm,
                  value: s.previewZoom,
                  semanticLabel: 'Zoom',
                  options: [
                    for (final z in {
                      .5,
                      .67,
                      .75,
                      .8,
                      .9,
                      1.0,
                      1.1,
                      1.25,
                      1.5,
                      2.0,
                      s.previewZoom,
                    }.toList()..sort())
                      SelectOption(z, '${(z * 100).round()}%'),
                  ],
                  onChanged: (z) => vm.update(s.copyWith(previewZoom: z)),
                ),
              ),
            ),
            _Row(
              title: 'Pages appear',
              description: 'Light or dark, for pages that offer both.',
              control: _Choice<String>(
                value: s.previewAppearance,
                label: 'Pages appear',
                options: const {'system': 'As the system', 'light': 'Light', 'dark': 'Dark'},
                onChanged: (v) => vm.update(s.copyWith(previewAppearance: v)),
              ),
            ),
            _Row(
              title: 'Search with',
              description: 'Words typed in the address that are not an address.',
              control: SizedBox(
                width: 170,
                child: Select<SearchEngine>(
                  size: .sm,
                  value: s.searchEngine,
                  semanticLabel: 'Search with',
                  options: [for (final e in SearchEngine.values) SelectOption(e, e.label)],
                  onChanged: (e) => vm.update(s.copyWith(searchEngine: e)),
                ),
              ),
            ),
            _Row(
              title: 'Open links in answers',
              description: 'Web links in what Helmy says. Other links open as they always do.',
              control: SizedBox(
                width: 190,
                child: Select<bool>(
                  size: .sm,
                  value: s.linksInHelmy,
                  semanticLabel: 'Open links in answers',
                  options: const [
                    SelectOption(false, 'Your browser'),
                    SelectOption(true, 'The Preview panel'),
                  ],
                  onChanged: (v) => vm.update(s.copyWith(linksInHelmy: v)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
