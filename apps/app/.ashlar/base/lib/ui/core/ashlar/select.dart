// Ashlar UI: Select. Copied into your app by `ashlar add select`; it is yours to change.

import 'dart:async';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'popover.dart';
import 'pressable.dart';
import 'theme.dart';

/// One choice in a [Select]. Options with the same [group] are listed together under it.
@immutable
class SelectOption<T> {
  const SelectOption(
    this.value,
    this.label, {
    this.enabled = true,
    this.icon,
    this.group,
  });

  /// The value it stands for.
  final T value;

  /// What the option says.
  final String label;

  /// False fades it and stops it being chosen.
  final bool enabled;

  /// A 16px icon before the label, in the list and in the trigger.
  final Widget? icon;

  /// The heading it is listed under; a line separates groups.
  final String? group;
}

enum SelectSize {
  /// 32 tall.
  sm,

  /// 36 tall.
  md,

  /// 40 tall.
  lg,

  /// 48 tall, for forms on a phone beside an xl button.
  xl,
}

/// Picks one value from a list that opens under it. It opens on a tap, Enter, Space or the
/// down arrow, on the chosen option. In the list the arrow keys, Home, End, Page Up and
/// Page Down move, typing jumps to the option that starts with what was typed, and Enter
/// picks. Only the rows on screen are built, so a list of thousands is as quick as ten.
///
/// ```dart
/// Select<String>(
///   value: city,
///   placeholder: 'Choose a city',
///   options: [SelectOption('lis', 'Lisbon', group: 'Cities'), SelectOption('kyo', 'Kyoto', group: 'Cities')],
///   onChanged: (v) => setState(() => city = v),
/// )
/// ```
class Select<T> extends StatefulWidget {
  const Select({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.placeholder,
    this.error = false,
    this.size = SelectSize.md,
    this.focusNode,
    this.semanticLabel,
  });

  /// The value chosen, or null.
  final T? value;

  /// What can be chosen, in order.
  final List<SelectOption<T>> options;

  /// Null disables it.
  final ValueChanged<T>? onChanged;

  /// Faint text shown while it is empty.
  final String? placeholder;

  /// Draws it as invalid.
  final bool error;

  /// As tall as the button of the same name beside it: small to extra large.
  final SelectSize size;

  /// Its focus node, to move focus to it or follow it from outside; one is made when not
  /// given.
  final FocusNode? focusNode;

  /// What it chooses, for screen readers: 'County'. The chosen option is read after it.
  final String? semanticLabel;

  @override
  State<Select<T>> createState() => _SelectState<T>();
}

class _SelectState<T> extends State<Select<T>> {
  final _menu = MenuController();
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final chosen = widget.options
        .where((o) => o.value == widget.value)
        .firstOrNull;
    final enabled = widget.onChanged != null;
    return RawMenuAnchor(
      controller: _menu,
      childFocusNode: _focus,
      // Focus goes back to the trigger when the list closes.
      onClose: () => _focus.requestFocus(),
      overlayBuilder: (context, info) => PopoverPanel(
        info: info,
        matchWidth: true,
        child: _SelectList<T>(
          options: widget.options,
          value: widget.value,
          onPicked: (v) {
            _menu.close();
            widget.onChanged?.call(v);
          },
        ),
      ),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
        },
        child: Pressable(
          onPressed: enabled ? _toggle : null,
          focusNode: _focus,
          semanticLabel: widget.semanticLabel,
          semanticValue: widget.semanticLabel == null
              ? null
              : (chosen?.label ?? widget.placeholder),
          builder: (context, state) {
            final ring = widget.error ? c.destructive : c.ring;
            final large = widget.size == SelectSize.xl;
            return Opacity(
              opacity: state.enabled ? 1 : .5,
              child: AnimatedContainer(
                duration: t.duration,
                // A height at least: larger text makes it taller rather than being cut off.
                constraints: BoxConstraints(
                  minHeight: t.control(switch (widget.size) {
                    SelectSize.sm => 32,
                    SelectSize.md => 36,
                    SelectSize.lg => 40,
                    SelectSize.xl => 48,
                  }),
                ),
                padding: EdgeInsetsDirectional.only(
                  start: large ? 16 : 12,
                  end: large ? 14 : 10,
                ),
                decoration: BoxDecoration(
                  color: t.brightness == Brightness.dark
                      ? Color.alphaBlend(
                          c.input.withValues(
                            alpha: c.input.a * (state.hovered ? .5 : .3),
                          ),
                          c.background,
                        )
                      : c.background,
                  borderRadius: BorderRadius.circular(
                    large ? t.radiusLg : t.radiusMd,
                  ),
                  border: Border.all(
                    color: widget.error
                        ? c.destructive
                        : (state.focused ? c.ring : c.input),
                  ),
                  boxShadow: [
                    if (state.focused)
                      BoxShadow(
                        color: ring.withValues(alpha: widget.error ? .2 : .5),
                        spreadRadius: 3,
                      ),
                    ...t.shadowXs,
                  ],
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: c.mutedForeground, size: 16),
                  child: Row(
                    children: [
                      if (chosen?.icon != null) ...[
                        chosen!.icon!,
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          chosen?.label ?? widget.placeholder ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (large ? t.text.base : t.text.sm).copyWith(
                            color: chosen == null
                                ? c.mutedForeground
                                : c.foreground,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AshlarIcon(
                        AshlarIconsRoundedStroke.chevronDown,
                        size: large ? 20 : 16,
                        color: c.mutedForeground.withValues(alpha: .5),
                      ),
                    ],
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

/// A row of the open list: a group's heading, a line between groups, or an option.
class _Line<T> {
  const _Line.heading(String this.heading) : option = null;
  const _Line.gap() : heading = null, option = null;
  const _Line.option(SelectOption<T> this.option) : heading = null;

  final String? heading;
  final SelectOption<T>? option;
}

/// The open list: a highlight that keys and the pointer move, built a screenful at a time.
class _SelectList<T> extends StatefulWidget {
  const _SelectList({
    required this.options,
    required this.value,
    required this.onPicked,
  });

  final List<SelectOption<T>> options;
  final T? value;
  final ValueChanged<T> onPicked;

  @override
  State<_SelectList<T>> createState() => _SelectListState<T>();
}

class _SelectListState<T> extends State<_SelectList<T>> {
  static const _row = 32.0,
      _heading = 28.0,
      _gap = 9.0,
      _pad = 4.0,
      _most = 320.0;

  late final List<_Line<T>> _lines = _layout();

  /// Where each option sits among the lines.
  late final List<int> _optionLines = [
    for (final (i, l) in _lines.indexed)
      if (l.option != null) i,
  ];
  late int _at = _start();
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: _offsetFor(_at),
  );
  String _typed = '';
  Timer? _typing;
  final _focus = FocusNode(debugLabel: 'Select list');

  @override
  void initState() {
    super.initState();
    // Take the keys from the trigger as the list opens: autofocus would leave them there.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => mounted ? _focus.requestFocus() : null,
    );
  }

  List<_Line<T>> _layout() {
    final lines = <_Line<T>>[];
    String? group;
    for (final (i, o) in widget.options.indexed) {
      if (i == 0 || o.group != group) {
        if (i > 0) lines.add(const _Line.gap());
        if (o.group != null) lines.add(_Line.heading(o.group!));
        group = o.group;
      }
      lines.add(_Line.option(o));
    }
    return lines;
  }

  int _start() {
    final i = widget.options.indexWhere((o) => o.value == widget.value);
    if (i >= 0) return i;
    return widget.options
        .indexWhere((o) => o.enabled)
        .clamp(0, widget.options.length);
  }

  double _extent(_Line<T> l) =>
      l.option != null ? _row : (l.heading != null ? _heading : _gap);

  double _top(int line) {
    var y = _pad;
    for (var i = 0; i < line; i++) {
      y += _extent(_lines[i]);
    }
    return y;
  }

  double get _height => _lines.fold<double>(_pad * 2, (h, l) => h + _extent(l));

  /// Opens with the chosen option in the middle of the list, where it can be seen.
  double _offsetFor(int option) {
    if (_lines.isEmpty || option >= _optionLines.length) return 0;
    final view = _height < _most ? _height : _most;
    return (_top(_optionLines[option]) - view / 2 + _row / 2).clamp(
      0,
      (_height - view).clamp(0, double.infinity),
    );
  }

  @override
  void dispose() {
    _typing?.cancel();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(int to, {int step = 1}) {
    final n = widget.options.length;
    if (n == 0) return;
    // Skip what cannot be picked, in the direction of travel.
    var i = to.clamp(0, n - 1);
    while (!widget.options[i].enabled) {
      i += step;
      if (i < 0 || i >= n) return;
    }
    setState(() => _at = i);
    if (!_scroll.hasClients) return;
    final top = _top(_optionLines[i]), view = _scroll.position;
    if (top - _pad < view.pixels) {
      _scroll.jumpTo((top - _pad).clamp(0, view.maxScrollExtent));
    } else if (top + _row + _pad > view.pixels + view.viewportDimension) {
      _scroll.jumpTo(
        (top + _row + _pad - view.viewportDimension).clamp(
          0,
          view.maxScrollExtent,
        ),
      );
    }
  }

  void _pick() {
    if (_at < widget.options.length && widget.options[_at].enabled) {
      widget.onPicked(widget.options[_at].value);
    }
  }

  /// Typing jumps to the next option starting with what was typed in the last moment.
  void _type(String ch) {
    _typing?.cancel();
    _typed += ch.toLowerCase();
    _typing = Timer(const Duration(milliseconds: 600), () => _typed = '');
    final n = widget.options.length;
    for (var k = _typed.length == 1 ? 1 : 0; k <= n; k++) {
      final i = (_at + k) % n;
      final o = widget.options[i];
      if (o.enabled && o.label.toLowerCase().startsWith(_typed)) return _go(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final perPage = (_most / _row).floor();
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = e.logicalKey;
        if (k == LogicalKeyboardKey.arrowDown) {
          _go(_at + 1);
        } else if (k == LogicalKeyboardKey.arrowUp) {
          _go(_at - 1, step: -1);
        } else if (k == LogicalKeyboardKey.home) {
          _go(0);
        } else if (k == LogicalKeyboardKey.end) {
          _go(widget.options.length - 1, step: -1);
        } else if (k == LogicalKeyboardKey.pageDown) {
          _go(_at + perPage);
        } else if (k == LogicalKeyboardKey.pageUp) {
          _go(_at - perPage, step: -1);
        } else if (k == LogicalKeyboardKey.enter ||
            k == LogicalKeyboardKey.space) {
          _pick();
        } else if (e.character != null && e.character!.trim().isNotEmpty) {
          _type(e.character!);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The highlighted option, read out as it changes.
            Semantics(
              liveRegion: true,
              label: widget.options.isEmpty
                  ? ''
                  : widget
                        .options[_at.clamp(0, widget.options.length - 1)]
                        .label,
              child: const SizedBox(),
            ),
            // Gives way when the room beside the trigger is shorter than the list.
            Flexible(
              child: SizedBox(
                height: _height < _most ? _height : _most,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(_pad),
                  itemCount: _lines.length,
                  itemExtentBuilder: (i, _) =>
                      i < _lines.length ? _extent(_lines[i]) : null,
                  itemBuilder: (context, i) {
                    final line = _lines[i];
                    if (line.option case final o?) {
                      final index = _optionLines.indexOf(i);
                      return _Option(
                        option: o,
                        lit: index == _at,
                        chosen: o.value == widget.value,
                        onHover: () => o.enabled && index != _at
                            ? setState(() => _at = index)
                            : null,
                        onTap: () => widget.onPicked(o.value),
                      );
                    }
                    if (line.heading case final h?) {
                      return Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          8,
                          6,
                          8,
                          6,
                        ),
                        child: Semantics(
                          header: true,
                          child: Text(
                            h,
                            style: t.text.xs.copyWith(color: c.mutedForeground),
                          ),
                        ),
                      );
                    }
                    return Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: c.border,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option<T> extends StatelessWidget {
  const _Option({
    required this.option,
    required this.lit,
    required this.chosen,
    required this.onHover,
    required this.onTap,
  });

  final SelectOption<T> option;
  final bool lit, chosen;
  final VoidCallback onHover, onTap;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final fg = lit ? c.accentForeground : c.popoverForeground;
    return MouseRegion(
      cursor: option.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => onHover(),
      child: Semantics(
        button: true,
        selected: chosen,
        enabled: option.enabled,
        onTap: option.enabled ? onTap : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: option.enabled ? onTap : null,
          child: Opacity(
            opacity: option.enabled ? 1 : .5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: lit && option.enabled
                    ? c.accent
                    : c.accent.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(t.radiusSm),
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: c.mutedForeground, size: 16),
                child: Row(
                  children: [
                    if (option.icon != null) ...[
                      option.icon!,
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.sm.copyWith(color: fg),
                      ),
                    ),
                    SizedBox(
                      width: 16,
                      child: chosen
                          ? AshlarIcon(
                              AshlarIconsRoundedStroke.check,
                              size: 16,
                              color: fg,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
