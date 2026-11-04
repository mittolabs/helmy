import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'ashlar/button.dart';
import 'ashlar/dialog.dart';
import 'ashlar/theme.dart';

/// About Helmy, where the system has no About window of its own (Windows,
/// Linux): its name, version and notice. The open-source credits live on
/// the site, not in the app.
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
        width: 320,
        padding: const .all(24),
        decoration: BoxDecoration(
          color: c.popover,
          border: Border.all(color: c.border),
          borderRadius: .circular(16),
          boxShadow: t.shadowLg,
        ),
        child: Column(
          mainAxisSize: .min,
          children: [
            Image.asset('assets/helmy/hello.png', width: 72, height: 72),
            const SizedBox(height: 12),
            Text('Helmy', style: t.text.xl.copyWith(fontWeight: .w600)),
            Text('Version $version', style: muted),
            const SizedBox(height: 4),
            Text('© ${DateTime.now().year} Mittolabs · BSD license', style: muted),
            const SizedBox(height: 20),
            Button(size: .sm, onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
