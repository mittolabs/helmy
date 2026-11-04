import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/helmy_tools.dart' show imageSize;
import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/spinner.dart';
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
  Offset? _down;
  Offset? _last;

  @override
  void initState() {
    super.initState();
    unawaited(d.open());
  }

  @override
  void dispose() {
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
                                group: x.booted ? 'Running' : (x.ios ? 'iOS' : 'Android'),
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
              child: ClipRRect(
                // The rounded corners of a phone's screen.
                borderRadius: .circular(w * .13),
                child: MouseRegion(
                  cursor: d.canTouch ? SystemMouseCursors.click : MouseCursor.defer,
                  child: GestureDetector(
                    onTapUp: (e) {
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
            );
          },
        ),
      ),
    );
  }
}
