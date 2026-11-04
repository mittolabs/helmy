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
                          value: chosen?.executable,
                          semanticLabel: 'Chromium browser',
                          options: [for (final b in browsers) SelectOption(b.executable, b.label)],
                          onChanged: (exe) => vm.update(s.copyWith(chromiumBrowser: exe)),
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
          ],
        );
      },
    );
  }
}
