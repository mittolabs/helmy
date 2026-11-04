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
                          device?.ios == true ? d.toggleAppearance : null,
                        ),
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
            final w = box.maxWidth / box.maxHeight > ratio ? box.maxHeight * ratio : box.maxWidth;
            final h = w / ratio;
            (double, double) share(Offset p) =>
                ((p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0));
            return SizedBox(
              width: w,
              height: h,
              child: Container(
                foregroundDecoration: _typing
                    ? BoxDecoration(
                        border: Border.all(color: t.colors.ring, width: 2),
                        borderRadius: .circular(w * .13),
                      )
                    : null,
                child: ClipRRect(
                  // The rounded corners of a phone's screen.
                  borderRadius: .circular(w * .13),
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
