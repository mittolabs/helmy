import 'phone_shell.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/services/remote/remote_crypto.dart';
import '../../data/services/remote/remote_link.dart';
import '../core/ashlar/app.dart';
import '../core/ashlar/app_theme.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/input.dart';
import '../core/ashlar/theme.dart';

/// Helmy on a phone: a remote for Helmy on a Mac. The chats there, each
/// conversation as it goes, and sending, approving and stopping. The work
/// stays on the Mac; nothing runs here but this window onto it.
Future<void> runPhone() async {
  WidgetsFlutterBinding.ensureInitialized();
  final saved = await _PairingFile.read();
  final look = await _PairingFile.look();
  runApp(_PhoneApp(saved: saved, look: look));
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

  static Future<File> _lookFile() async =>
      File('${(await getApplicationSupportDirectory()).path}/look.txt');

  /// How the phone looks, as chosen in its settings.
  static Future<PhoneLook> look() async {
    try {
      return PhoneLook.values.byName((await (await _lookFile()).readAsString()).trim());
    } on Object {
      return PhoneLook.system;
    }
  }

  static Future<void> keepLook(PhoneLook l) async {
    final f = await _lookFile();
    await f.create(recursive: true);
    await f.writeAsString(l.name);
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
  const _PhoneApp({required this.saved, required this.look});
  final Pairing? saved;
  final PhoneLook look;

  @override
  State<_PhoneApp> createState() => _PhoneAppState();
}

class _PhoneAppState extends State<_PhoneApp> {
  RemoteLink? _link;
  late PhoneLook _look = widget.look;

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
    // The Mac's own theme, so the phone looks like Helmy there.
    theme: themeFor(Brightness.light),
    darkTheme: themeFor(Brightness.dark),
    // Wherever the keyboard is up, a tap on empty space puts it away: on
    // every screen and sheet, since this wraps them all. A tap on a button
    // or a text box is theirs, as the innermost tap wins.
    builder: (context, child) => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    ),
    themeMode: switch (_look) {
      PhoneLook.system => AshlarThemeMode.system,
      PhoneLook.light => AshlarThemeMode.light,
      PhoneLook.dark => AshlarThemeMode.dark,
    },
    home: _link == null
        ? _PairScreen(onPaired: _paired)
        : PhoneShell(
            link: _link!,
            onUnpair: _unpair,
            look: _look,
            onLook: (l) {
              setState(() => _look = l);
              unawaited(_PairingFile.keepLook(l));
            },
          ),
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
      child: PhoneSafeArea(
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

/// A phone screen's safe area that also rises above the keyboard: with no
/// Material scaffold, nothing else makes room for it.
class PhoneSafeArea extends StatelessWidget {
  const PhoneSafeArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      // With the keyboard up, it covers the home indicator: no gap for it.
      child: SafeArea(bottom: keyboard == 0, child: child),
    );
  }
}
