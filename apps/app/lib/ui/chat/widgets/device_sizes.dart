import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';

/// A screen size the page can be shown at, in the page's own points.
typedef DeviceSize = ({String name, int width, int height, bool mobile});

/// The sizes offered, as browsers' developer tools list them.
const deviceSizes = <DeviceSize>[
  (name: 'iPhone SE', width: 375, height: 667, mobile: true),
  (name: 'iPhone XR', width: 414, height: 896, mobile: true),
  (name: 'iPhone 12 Pro', width: 390, height: 844, mobile: true),
  (name: 'iPhone 14 Pro Max', width: 430, height: 932, mobile: true),
  (name: 'Pixel 7', width: 412, height: 915, mobile: true),
  (name: 'Samsung Galaxy S8+', width: 360, height: 740, mobile: true),
  (name: 'Samsung Galaxy S20 Ultra', width: 412, height: 915, mobile: true),
  (name: 'Samsung Galaxy A51/71', width: 412, height: 914, mobile: true),
  (name: 'Galaxy Z Fold 5', width: 344, height: 882, mobile: true),
  (name: 'Surface Duo', width: 540, height: 720, mobile: true),
  (name: 'iPad Mini', width: 768, height: 1024, mobile: true),
  (name: 'iPad Air', width: 820, height: 1180, mobile: true),
  (name: 'iPad Pro', width: 1024, height: 1366, mobile: true),
  (name: 'Surface Pro 7', width: 912, height: 1368, mobile: true),
  (name: 'Asus Zenbook Fold', width: 853, height: 1280, mobile: true),
  (name: 'Nest Hub', width: 1024, height: 600, mobile: true),
  (name: 'Nest Hub Max', width: 1280, height: 800, mobile: true),
];

/// Under the page's toolbar: the size the page is shown at. Responsive fills
/// the panel; a device, or a size typed in, shows the page at that size,
/// shrunk to fit the panel when bigger, laid out at its own width.
class DeviceSizeBar extends StatefulWidget {
  const DeviceSizeBar({
    super.key,
    required this.size,
    required this.fills,
    required this.onSize,
    required this.onClose,
  });

  /// The size chosen; null for Responsive.
  final DeviceSize? size;

  /// What Responsive fills now, to show in the boxes.
  final Size fills;
  final ValueChanged<DeviceSize?> onSize;
  final VoidCallback onClose;

  @override
  State<DeviceSizeBar> createState() => _DeviceSizeBarState();
}

class _DeviceSizeBarState extends State<DeviceSizeBar> {
  final _w = TextEditingController();
  final _h = TextEditingController();
  final _wFocus = FocusNode();
  final _hFocus = FocusNode();

  void _show() {
    final s = widget.size;
    final w = s?.width ?? widget.fills.width.round();
    final h = s?.height ?? widget.fills.height.round();
    if (!_wFocus.hasFocus) _w.text = '$w';
    if (!_hFocus.hasFocus) _h.text = '$h';
  }

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void didUpdateWidget(DeviceSizeBar old) {
    super.didUpdateWidget(old);
    _show();
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _wFocus.dispose();
    _hFocus.dispose();
    super.dispose();
  }

  /// A size typed in: shown as it is, named for itself.
  void _typed() {
    final w = int.tryParse(_w.text.trim()), h = int.tryParse(_h.text.trim());
    if (w == null || h == null || w < 100 || h < 100 || w > 4000 || h > 4000) {
      _show();
      return;
    }
    widget.onSize((name: 'Custom', width: w, height: h, mobile: widget.size?.mobile ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final s = widget.size;
    Widget box(TextEditingController c, FocusNode f, String label) => SizedBox(
      width: 64,
      child: Focus(
        onFocusChange: (on) {
          if (!on) _typed();
        },
        child: Input(
          controller: c,
          focusNode: f,
          size: .sm,
          semanticLabel: label,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _typed(),
        ),
      ),
    );
    return Padding(
      padding: const .fromLTRB(8, 0, 8, 6),
      child: Row(
        spacing: 6,
        children: [
          Text('Size', style: muted),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Select<String>(
                value: s == null ? 'Responsive' : (s.name == 'Custom' ? 'Custom' : s.name),
                semanticLabel: 'Device size',
                // Wide enough for each device's name and size in full.
                menuWidth: 300,
                options: [
                  const SelectOption('Responsive', 'Responsive'),
                  if (s?.name == 'Custom') const SelectOption('Custom', 'Custom'),
                  for (final d in deviceSizes)
                    SelectOption(d.name, '${d.name}  ${d.width} × ${d.height}', group: 'Devices'),
                ],
                onChanged: (name) => widget.onSize(
                  name == 'Responsive'
                      ? null
                      : deviceSizes.where((d) => d.name == name).firstOrNull ?? s,
                ),
              ),
            ),
          ),
          box(_w, _wFocus, 'Width'),
          Text('×', style: muted),
          box(_h, _hFocus, 'Height'),
          Tooltip(
            message: 'Turn it sideways',
            child: Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'Turn it sideways',
              onPressed: s == null
                  ? null
                  : () => widget.onSize((
                      name: s.name,
                      width: s.height,
                      height: s.width,
                      mobile: s.mobile,
                    )),
              child: const AshlarIcon(AshlarIconsRoundedStroke.rotateCwSquare, size: 14),
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Hide sizes',
            child: Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'Hide sizes',
              onPressed: widget.onClose,
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}
