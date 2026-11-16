import 'phone_shell.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/services/remote/remote_crypto.dart';
import '../../data/services/remote/remote_link.dart';
import '../../data/services/remote/served.dart';
import '../core/ashlar/app.dart';
import '../core/ashlar/app_theme.dart';
import '../core/ashlar/button.dart';
import '../core/ashlar/input.dart';
import '../core/ashlar/theme.dart';
import 'store/kept.dart';

/// Helmy on a phone: a remote for Helmy on a Mac. The chats there, each
/// conversation as it goes, and sending, approving and stopping. The work
/// stays on the Mac; nothing runs here but this window onto it.
Future<void> runPhone() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Opened from the code a computer shows: paired by the link it carries,
  // kept, and taken out of the address.
  var saved = await _PairingFile.read();
  Pairing? offer;
  if (linkInAddress() case final l?) {
    clearAddress();
    if (Pairing.parse(l) case final p?) {
      // A one-time code: used on the pairing screen, which says how it went.
      if (p.isOffer) {
        offer = p;
      } else {
        await _PairingFile.write(p);
        saved = p;
      }
    }
  }
  final look = await _PairingFile.look();
  runApp(_PhoneApp(saved: offer == null ? saved : null, offer: offer, look: look));
}

/// The pairing and the look, kept so the remote stays paired.
abstract final class _PairingFile {
  static Future<Pairing?> read() async => Pairing.parse(await keptRead('pairing') ?? '');

  /// How the phone looks, as chosen in its settings.
  static Future<PhoneLook> look() async {
    try {
      return PhoneLook.values.byName((await keptRead('look') ?? '').trim());
    } on Object {
      return PhoneLook.system;
    }
  }

  static Future<void> keepLook(PhoneLook l) => keptWrite('look', l.name);

  static Future<void> write(Pairing? p) => keptWrite('pairing', p?.link);
}

class _PhoneApp extends StatefulWidget {
  const _PhoneApp({required this.saved, required this.look, this.offer});
  final Pairing? saved;

  /// A one-time code the page was opened with, to use at once.
  final Pairing? offer;
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

  /// Pairs with [p]: a one-time code is used first, to agree on this
  /// phone's key. Why not, in words, when it could not be.
  Future<String?> _paired(Pairing p) async {
    if (p.isOffer) {
      final got = await RemoteLink.exchange(p);
      if (got.pairing == null) return got.trouble;
      p = got.pairing!;
    }
    await _PairingFile.write(p);
    if (mounted) setState(() => _use(p));
    return null;
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
        ? _PairScreen(onPaired: _paired, offer: widget.offer)
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
  const _PairScreen({required this.onPaired, this.offer});
  final Future<String?> Function(Pairing) onPaired;

  /// A code to use as soon as the screen shows.
  final Pairing? offer;

  @override
  State<_PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<_PairScreen> {
  final _pasted = TextEditingController();
  String? _wrong;
  bool _scanning = false;
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    if (widget.offer case final p?) unawaited(_pair(p));
  }

  void _try(String text) {
    final p = Pairing.parse(text);
    if (p == null) {
      setState(() => _wrong = "That isn't a Helmy pairing code.");
      return;
    }
    unawaited(_pair(p));
  }

  Future<void> _pair(Pairing p) async {
    if (_pairing) return;
    setState(() {
      _pairing = true;
      _scanning = false;
      _wrong = null;
    });
    final trouble = await widget.onPaired(p);
    if (!mounted) return;
    setState(() {
      _pairing = false;
      _wrong = trouble;
    });
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
                kIsWeb ? 'Pair with Helmy' : 'Pair with Helmy on your computer',
                style: t.text.xl.copyWith(fontWeight: .w600),
                textAlign: .center,
              ),
              Text(
                switch ((kIsWeb, inExtension)) {
                  (true, true) =>
                    'On the computer Helmy runs on, open Settings, then Phone, and turn it on. '
                        'Copy the link under the code it shows and paste it here.',
                  (true, false) =>
                    'On the computer Helmy runs on, open Settings, then Phone. Scan the code it '
                        "shows with this phone's camera, and open the link.",
                  _ => 'On the computer Helmy runs on, open Settings, then Phone, and turn it on. Scan the code it shows.',
                },
                style: muted,
                textAlign: .center,
              ),
              if (_pairing)
                Text(
                  'Pairing with the computer…',
                  style: t.text.sm.copyWith(fontWeight: .w600),
                  textAlign: .center,
                )
              else if (_scanning)
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
              else if (kIsWeb) ...[
                Input(
                  controller: _pasted,
                  placeholder: inExtension ? 'helmy-pair:v3?…' : 'Or paste the link here',
                ),
                Button(onPressed: () => _try(_pasted.text), child: const Text('Pair')),
              ] else ...[
                Button(
                  onPressed: () => setState(() => _scanning = true),
                  child: const Text('Scan the code'),
                ),
                Text('Or paste the link under the code:', style: muted),
                Input(controller: _pasted, placeholder: 'helmy-pair:v3?…'),
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
