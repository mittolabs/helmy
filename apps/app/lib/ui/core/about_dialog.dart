import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../config/open_source.dart';
import 'ashlar/button.dart';
import 'ashlar/dialog.dart';
import 'ashlar/scroll_area.dart';
import 'ashlar/theme.dart';

/// The credits as plain text, for the Mac's own About window.
String openSourceCredits() => [
  'Built with open-source software',
  '',
  for (final p in openSource) '${p.name}${p.version.isEmpty ? '' : ' ${p.version}'} · ${p.license}',
  '',
  for (final p in openSourceTools) '${p.name} · ${p.license} · ${p.use}',
].join('\n');

/// About Helmy: its name and version, who makes it, and the open-source
/// software it is built with, each with its license.
Future<void> showAbout(BuildContext context, {required String version}) => showAshlarDialog<void>(
  context: context,
  builder: (context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
    child: Focus(autofocus: true, child: _About(version: version)),
  ),
);

class _About extends StatelessWidget {
  const _About({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final muted = t.text.xs.copyWith(color: c.mutedForeground);
    return Center(
      child: Container(
        width: 420,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const .all(24),
        decoration: BoxDecoration(
          color: c.popover,
          border: Border.all(color: c.border),
          borderRadius: .circular(16),
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            Center(child: Image.asset('assets/helmy/hello.png', width: 72, height: 72)),
            const SizedBox(height: 12),
            Text(
              'Helmy',
              textAlign: .center,
              style: t.text.xl.copyWith(fontWeight: .w600),
            ),
            Text('Version $version', textAlign: .center, style: muted),
            const SizedBox(height: 4),
            Text(
              '© ${DateTime.now().year} Mittolabs · BSD license',
              textAlign: .center,
              style: muted,
            ),
            const SizedBox(height: 20),
            Text('Built with open-source software', style: t.text.sm.copyWith(fontWeight: .w600)),
            const SizedBox(height: 8),
            Flexible(
              child: ScrollArea(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    for (final p in openSource)
                      _Line(
                        name: p.name,
                        detail: p.version.isEmpty ? p.license : '${p.version} · ${p.license}',
                      ),
                    for (final p in openSourceTools)
                      _Line(name: p.name, detail: '${p.license} · ${p.use}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Button(
                size: .sm,
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.name, required this.detail});
  final String name, detail;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .symmetric(vertical: 4),
      child: Row(
        spacing: 12,
        children: [
          Expanded(child: Text(name, style: t.text.sm)),
          Flexible(
            child: Text(
              detail,
              textAlign: .end,
              maxLines: 1,
              overflow: .ellipsis,
              style: t.text.xs.copyWith(color: t.colors.mutedForeground),
            ),
          ),
        ],
      ),
    );
  }
}
