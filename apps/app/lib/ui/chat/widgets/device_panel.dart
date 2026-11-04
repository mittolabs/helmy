import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/helmy_tools.dart' show imageSize;
import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/progress.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/textarea.dart';
import '../../core/ashlar/toast.dart';
import '../../core/helmy_dialog.dart';
import '../../../data/services/devices.dart';
import '../view_models/chat_view_model.dart';
import '../view_models/device_view_model.dart';

/// Beside the conversation: a simulator or emulator, live. Its screen
/// refreshes while the panel shows; a click taps it, a drag swipes it, and
/// what is typed in the box below goes to it. The controls down the side
/// press home, switch light and dark, and attach the screen to the message.
class DevicePanel extends StatefulWidget {
  const DevicePanel({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  State<DevicePanel> createState() => _DevicePanelState();
}

class _DevicePanelState extends State<DevicePanel> {
  DeviceViewModel get d => widget.vm.device!;
  final _typed = TextEditingController();

  /// The logs follow the newest line, as a terminal does, unless scrolled up
  /// to read.
  final _logScroll = ScrollController();
  int _logCount = 0;

  void _followLogs(int count) {
    if (count == _logCount) return;
    final atEnd =
        !_logScroll.hasClients ||
        _logScroll.position.pixels >= _logScroll.position.maxScrollExtent - 24;
    _logCount = count;
    if (!atEnd) return;
    // Twice: lines of different heights are measured as they are laid out,
    // so the end is known for sure only a frame after the first jump.
    void end() {
      if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      end();
      WidgetsBinding.instance.addPostFrameCallback((_) => end());
    });
  }

  Offset? _down;
  Offset? _last;

  /// The phone's screen, once clicked: keys typed go to the phone.
  final _screenFocus = FocusNode();
  bool _typing = false;

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.handled;
    // The app's shortcuts stay its own.
    final k = HardwareKeyboard.instance;
    if (k.isMetaPressed || k.isControlPressed) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter) {
      unawaited(d.press('Enter'));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      unawaited(d.press('Backspace'));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _screenFocus.unfocus();
      return KeyEventResult.handled;
    }
    final text = e.character;
    if (text != null && text.isNotEmpty && !text.codeUnits.any((u) => u < 32)) {
      d.key(text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    unawaited(d.open());
  }

  @override
  void dispose() {
    _logScroll.dispose();
    _screenFocus.dispose();
    d.pause();
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final device = d.device;
        if (d.logLines case final lines? when d.logsOpen) _followLogs(lines.length);
        Widget tool(String label, IconData icon, VoidCallback? onPressed) => Tooltip(
          message: label,
          child: Button(
            variant: .ghost,
            size: .iconSm,
            semanticLabel: label,
            onPressed: onPressed,
            child: AshlarIcon(icon, size: 16),
          ),
        );
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            Padding(
              padding: const .fromLTRB(10, 8, 10, 8),
              child: d.devices.isEmpty
                  ? Text(d.trouble ?? 'Looking for devices…', style: muted)
                  : Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Select<String>(
                          value: device?.id,
                          options: [
                            for (final x in d.devices)
                              SelectOption(
                                x.id,
                                '${x.name}${x.runtime.isEmpty ? '' : ' · ${x.runtime}'}',
                                // Phones on the cable first, then what is running, then the rest.
                                group: x.runtime == 'Android phone'
                                    ? 'Connected phones'
                                    : x.booted
                                    ? 'Running'
                                    : (x.ios ? 'iOS simulators' : 'Android emulators'),
                              ),
                          ],
                          onChanged: (id) => d.choose(d.devices.firstWhere((x) => x.id == id)),
                        ),
                      ),
                    ),
            ),
            if (!d.canTouch && device != null)
              Padding(
                padding: const .fromLTRB(12, 0, 12, 8),
                child: Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        'You can watch it. To tap and type on iOS simulators, I need AXe, '
                        'a small open-source tool.',
                        style: muted,
                      ),
                    ),
                    Button(
                      variant: .outline,
                      size: .xs,
                      onPressed: d.doing == null ? d.installTouch : null,
                      child: const Text('Install'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _screen(t, muted)),
                  Padding(
                    padding: const .symmetric(horizontal: 6, vertical: 8),
                    child: Column(
                      spacing: 4,
                      children: [
                        tool('Home', AshlarIconsRoundedStroke.house, d.canTouch ? d.home : null),
                        tool(
                          d.dark ? 'Light appearance' : 'Dark appearance',
                          d.dark ? AshlarIconsRoundedStroke.sun : AshlarIconsRoundedStroke.moon,
                          device == null ? null : d.toggleAppearance,
                        ),
                        if (device != null) _DeviceSettings(d: d, device: device),
                        tool(
                          d.logsOpen ? 'Hide its logs' : 'Its logs',
                          AshlarIconsRoundedStroke.scrollText,
                          device == null ? null : d.toggleLogs,
                        ),
                        tool(
                          'Attach the screen to your message',
                          AshlarIconsRoundedStroke.camera,
                          d.screen == null ? null : () => widget.vm.attachScreen(d.screen!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Its logs, the agent's same lines, while asked for.
            if (d.logsOpen && device != null)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.colors.border)),
                ),
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    Padding(
                      padding: const .fromLTRB(10, 8, 6, 6),
                      child: Row(
                        spacing: 6,
                        children: [
                          Expanded(
                            child: Input(
                              size: .sm,
                              placeholder: 'Only lines holding…',
                              leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 13),
                              onChanged: d.findInLogs,
                            ),
                          ),
                          tool('Hide the logs', AshlarIconsRoundedStroke.x, d.toggleLogs),
                        ],
                      ),
                    ),
                    Expanded(
                      child: switch (d.logLines) {
                        null => const Center(child: Spinner(size: 14)),
                        [] => Center(
                          child: Padding(
                            padding: const .symmetric(horizontal: 16),
                            child: Text(
                              device.ios
                                  ? 'Nothing from the apps on it in the last 2 minutes. Apps you '
                                        'build show here; the system\'s own lines are left out.'
                                  : 'No warnings or errors in the last 2 minutes.',
                              textAlign: .center,
                              style: muted,
                            ),
                          ),
                        ),
                        final lines => ScrollArea.builder(
                          controller: _logScroll,
                          padding: const .fromLTRB(10, 0, 10, 8),
                          itemCount: lines.length,
                          itemBuilder: (context, i) => Text(
                            lines[i],
                            style: t.text.xs.copyWith(
                              fontFamily: 'Menlo',
                              fontSize: 11,
                              height: 1.45,
                              color: RegExp(r'\b(E|F|Error|Fault)\b|\sE/|\sF/').hasMatch(lines[i])
                                  ? t.colors.destructive
                                  : t.colors.foreground.withValues(alpha: .85),
                            ),
                          ),
                        ),
                      },
                    ),
                  ],
                ),
              ),
            if (d.canTouch && device != null)
              Padding(
                padding: const .fromLTRB(10, 0, 10, 10),
                child: Input(
                  controller: _typed,
                  placeholder: 'Type into ${device.name}',
                  leading: const AshlarIcon(AshlarIconsRoundedStroke.keyboard, size: 14),
                  onSubmitted: (text) {
                    unawaited(d.type(text));
                    _typed.clear();
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _screen(AshlarThemeData t, TextStyle muted) {
    final bytes = d.screen;
    if (d.doing != null) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          spacing: 8,
          children: [
            if (d.installShare case final share?)
              // Homebrew's own figure, as a bar.
              SizedBox(width: 160, child: Progress(value: share))
            else
              const Spinner(size: 16),
            Text(d.doing!, style: muted),
          ],
        ),
      );
    }
    if (bytes == null) {
      return Center(
        child: Padding(
          padding: const .all(16),
          child: d.trouble == null
              ? const Spinner(size: 16)
              : Text(d.trouble!, textAlign: .center, style: muted),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const .all(12),
        child: LayoutBuilder(
          builder: (context, box) {
            final image = Image.memory(bytes, gaplessPlayback: true, fit: .contain);
            final size = imageSize(bytes);
            if (size == null) return image;
            final picture = Size(size.$1.toDouble(), size.$2.toDouble());
            final ratio = picture.width / picture.height;
            // The picture's rectangle within the space, to turn a click
            // into a share of the device's screen.
            // Room for the phone's body around its screen: a bezel a twenty-fifth
            // of its width, and its side buttons beyond.
            final room = Size(box.maxWidth / 1.12, box.maxHeight / 1.09);
            final w = room.width / room.height > ratio ? room.height * ratio : room.width;
            final h = w / ratio;
            final bezel = w * .04;
            final corner = w * (d.device?.ios == true ? .13 : .09);
            (double, double) share(Offset p) =>
                ((p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0));
            return _Body(
              screen: Size(w, h),
              bezel: bezel,
              corner: corner,
              child: Container(
                foregroundDecoration: _typing
                    ? BoxDecoration(
                        border: Border.all(color: t.colors.ring, width: 2),
                        borderRadius: .circular(corner),
                      )
                    : null,
                child: ClipRRect(
                  // The rounded corners of a phone's screen.
                  borderRadius: .circular(corner),
                  child: MouseRegion(
                    cursor: d.canTouch ? SystemMouseCursors.click : MouseCursor.defer,
                    child: Focus(
                      focusNode: _screenFocus,
                      onKeyEvent: _key,
                      onFocusChange: (on) => setState(() => _typing = on),
                      child: GestureDetector(
                        onTapUp: (e) {
                          // Clicked, the screen takes the keyboard.
                          if (d.canTouch) _screenFocus.requestFocus();
                          final (x, y) = share(e.localPosition);
                          unawaited(d.tap(x, y, picture));
                        },
                        onPanStart: (e) => _down = _last = e.localPosition,
                        onPanUpdate: (e) => _last = e.localPosition,
                        onPanEnd: (_) {
                          final (from, to) = (_down, _last);
                          _down = _last = null;
                          if (from == null || to == null) return;
                          unawaited(d.swipe(share(from), share(to), picture));
                        },
                        child: image,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The device's own settings, as T3 Code's device tools: what an app is
/// checked against. Only what this device can do is offered; what did not
/// take is said.
class _DeviceSettings extends StatelessWidget {
  const _DeviceSettings({required this.d, required this.device});
  final DeviceViewModel d;
  final Device device;

  /// Places to try an app in: a few cities across the world.
  static const places = [
    ('San Francisco', 37.7749, -122.4194),
    ('New York', 40.7128, -74.0060),
    ('London', 51.5074, -0.1278),
    ('Tokyo', 35.6762, 139.6503),
    ('Sydney', -33.8688, 151.2093),
  ];

  Future<void> _did(BuildContext context, Future<bool> act, String what) async {
    final ok = await act;
    if (ok || !context.mounted) return;
    showToast(
      context,
      title: "$what didn't take",
      description: "${device.name} didn't accept it.",
      type: .error,
    );
  }

  Future<void> _push(BuildContext context) async {
    final bundle = TextEditingController();
    final payload = TextEditingController(
      text: '{\n  "aps": {\n    "alert": { "title": "Hello", "body": "A push from Helmy" },\n    "sound": "default"\n  }\n}',
    );
    final send = await showAshlarDialog<bool>(
      context: context,
      builder: (context) => HelmyDialog(
        title: 'Send a push notification',
        body: 'To an app on ${device.name}, by its bundle id, as an APNs payload.',
        icon: AshlarIconsRoundedStroke.bell,
        content: Column(
          crossAxisAlignment: .stretch,
          spacing: 10,
          children: [
            Input(controller: bundle, autofocus: true, placeholder: 'com.example.app'),
            Textarea(controller: payload, minLines: 6, maxLines: 10),
          ],
        ),
        actions: [
          DialogButton('Cancel', onPressed: () => Navigator.pop(context, false)),
          DialogButton('Send', main: true, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
    if (send == true && context.mounted) {
      final ok = await d.push(bundle.text.trim(), payload.text);
      if (context.mounted) {
        showToast(
          context,
          title: ok ? 'Sent' : "The push didn't go",
          description: ok
              ? 'It shows on ${device.name} as it would from the app\'s server.'
              : 'Check the bundle id is an app on it, and the payload is JSON.',
          type: ok ? .success : .error,
        );
      }
    }
    bundle.dispose();
    payload.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ios = device.ios;
    return DropdownMenu(
      align: .end,
      side: .left,
      items: [
        MenuSub(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.type, size: 16),
          items: [
            for (final size in DeviceText.values)
              MenuItem(
                leading: d.textSize == size
                    ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 14)
                    : const SizedBox(width: 14),
                onPressed: () => _did(context, d.setTextSize(size), 'The text size'),
                child: Text(size.label),
              ),
          ],
          child: const Text('Text size'),
        ),
        if (ios || DeviceService.emulatorOf(device))
          MenuSub(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.mapPin, size: 16),
            items: [
              for (final (name, lat, lon) in places)
                MenuItem(
                  onPressed: () => _did(context, d.setLocation(lat, lon), 'The place'),
                  child: Text(name),
                ),
              if (ios) ...[
                const MenuSeparator(),
                MenuItem(
                  onPressed: () => _did(context, d.setLocation(null, null), 'Its own place'),
                  child: const Text('Its own'),
                ),
              ],
            ],
            child: const Text('Location'),
          ),
        MenuItem(
          leading: const AshlarIcon(AshlarIconsRoundedStroke.link, size: 16),
          onPressed: () async {
            final url = await askText(
              context,
              title: 'Open a link on ${device.name}',
              action: 'Open',
              body: 'A web address, or an app\'s own link (myapp://...), opened as a tap on it would.',
              icon: AshlarIconsRoundedStroke.link,
            );
            if (url != null && url.trim().isNotEmpty && context.mounted) {
              await _did(context, d.openLink(url.trim()), 'The link');
            }
          },
          child: const Text('Open a link...'),
        ),
        if (ios) ...[
          const MenuSeparator(),
          MenuItem(
            leading: d.cleanStatusBar
                ? const AshlarIcon(AshlarIconsRoundedStroke.check, size: 16)
                : const AshlarIcon(AshlarIconsRoundedStroke.smartphone, size: 16),
            onPressed: () => _did(context, d.toggleStatusBar(), 'The status bar'),
            child: const Text('Status bar for screenshots'),
          ),
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.shieldCheck, size: 16),
            onPressed: () async {
              final ok = await d.resetPermissions();
              if (!context.mounted) return;
              showToast(
                context,
                title: ok ? 'Permissions asked for again' : "Permissions weren't reset",
                description: ok ? 'Every app asks afresh, as on a new phone.' : null,
                type: ok ? .success : .error,
              );
            },
            child: const Text('Ask for permissions again'),
          ),
          MenuItem(
            leading: const AshlarIcon(AshlarIconsRoundedStroke.bell, size: 16),
            onPressed: () => _push(context),
            child: const Text('Send a push...'),
          ),
        ],
      ],
      builder: (context, menu) => Tooltip(
        message: 'Device settings',
        child: Button(
          variant: .ghost,
          size: .iconSm,
          semanticLabel: 'Device settings',
          onPressed: () {
            unawaited(d.readSettings());
            menu.open();
          },
          child: const AshlarIcon(AshlarIconsRoundedStroke.slidersHorizontal, size: 16),
        ),
      ),
    );
  }
}

/// A phone's body around its screen: a dark bezel with a faint edge, the
/// screen's own rounded corners inside, and its side buttons. Taps go to the
/// screen within it, measured as before.
class _Body extends StatelessWidget {
  const _Body({
    required this.screen,
    required this.bezel,
    required this.corner,
    required this.child,
  });
  final Size screen;
  final double bezel, corner;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const body = Color(0xFF0D0D0F), edge = Color(0xFF3A3A3E);
    Widget button(double top, double height, {required bool left}) => Positioned(
      top: top,
      left: left ? -2.5 : null,
      right: left ? null : -2.5,
      child: Container(
        width: 3,
        height: height,
        decoration: BoxDecoration(color: edge, borderRadius: BorderRadius.circular(1.5)),
      ),
    );
    final outer = Size(screen.width + bezel * 2, screen.height + bezel * 2);
    return SizedBox(
      width: outer.width,
      height: outer.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Volume and side buttons, by the share of the body's height.
          button(outer.height * .17, outer.height * .06, left: true),
          button(outer.height * .25, outer.height * .09, left: true),
          button(outer.height * .36, outer.height * .09, left: true),
          button(outer.height * .25, outer.height * .13, left: false),
          Container(
            padding: EdgeInsets.all(bezel),
            decoration: BoxDecoration(
              color: body,
              borderRadius: BorderRadius.circular(corner + bezel),
              border: Border.all(color: edge, width: 1.2),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
              ],
            ),
            child: SizedBox(width: screen.width, height: screen.height, child: child),
          ),
        ],
      ),
    );
  }
}
