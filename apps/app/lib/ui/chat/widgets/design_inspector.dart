import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/color_picker.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/textarea.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toggle_group.dart';
import '../../core/ashlar/tooltip.dart';

/// One element of a screen, as the layer list shows it.
class DesignLayer {
  DesignLayer(this.id, this.name, this.tag, this.children);

  /// Where it is in its page: the child at each level below the body, `0.3.1`.
  final String id;
  final String name;
  final String tag;
  final List<DesignLayer> children;

  static List<DesignLayer> listFrom(Object? json) => [
    for (final n in (json as List? ?? const []).whereType<Map>())
      DesignLayer('${n['id']}', '${n['name']}', '${n['tag']}', listFrom(n['n'])),
  ];
}

/// What the canvas has picked: a screen, or an element in one, with its
/// styles as the page computes them and as they are written on it.
class DesignPick {
  DesignPick.from(Map<dynamic, dynamic> m)
    : file = '${m['file']}',
      screen = m['screen'] == true,
      scripted = m['scripted'] == true,
      id = m['id'] as String?,
      tag = '${m['tag'] ?? ''}',
      name = '${m['name'] ?? ''}',
      text = m['text'] as String?,
      html = m['html'] as String?,
      width = (m['size'] as Map?)?['w'] as num? ?? 0,
      height = (m['size'] as Map?)?['h'] as num? ?? 0,
      sizingW = '${(m['sizing'] as Map?)?['width'] ?? 'hug'}',
      sizingH = '${(m['sizing'] as Map?)?['height'] ?? 'hug'}',
      styles = (m['styles'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      inline = (m['inline'] as Map? ?? const {}).map((k, v) => MapEntry('$k', '$v')),
      parents = [
        for (final p in (m['parents'] as List? ?? const []).whereType<Map>())
          (id: '${p['id']}', name: '${p['name']}'),
      ],
      issues = [
        for (final i in (m['issues'] as List? ?? const []).whereType<Map>())
          (what: '${i['what']}', why: '${i['why']}'),
      ];

  final String file;

  /// The screen itself, not an element in it.
  final bool screen;

  /// Its page is made by a script, so changes go to Helmy as a request.
  final bool scripted;
  final String? id;
  final String tag, name;

  /// Its words, where it holds nothing else.
  final String? text;

  /// Its HTML, when not too long to edit here.
  final String? html;
  final num width, height;

  /// How it is sized: `hug`, `fixed` or `fill`.
  final String sizingW, sizingH;
  final Map<String, String> styles, inline;
  final List<({String id, String name})> parents;

  /// What of it won't convert to Flutter.
  final List<({String what, String why})> issues;

  String style(String p) => styles[p] ?? '';

  /// [p] as written on the element (`clamp(44px, 5.4vw, 76px)`), else as the page computes it.
  String written(String p) => inline[p] ?? style(p);

  /// The CSS property an issue is about (`display: grid` is `display`), or null.
  String? issueFor(String property) {
    for (final i in issues) {
      if (i.what.split(':').first.trim() == property) return i.why;
    }
    return null;
  }
}

/// What the inspector asks of the canvas.
class InspectorActions {
  const InspectorActions({
    required this.select,
    required this.point,
    required this.up,
    required this.style,
    required this.sizing,
    required this.text,
    required this.html,
  });

  final void Function(String id) select;

  /// A layer under the pointer, outlined on the canvas; null for none.
  final void Function(String? id) point;
  final VoidCallback up;
  final void Function(Map<String, String?> styles) style;
  final void Function(String axis, String mode, num? px) sizing;
  final void Function(String text) text;
  final void Function(String html) html;
}

/// How much of the inspector shows.
enum InspectorLevel { simple, pro, code }

/// The layers of the picked screen, and what is picked, to change: the
/// design canvas's Edit side, beside it.
class DesignInspector extends StatefulWidget {
  const DesignInspector({
    super.key,
    required this.layers,
    required this.screen,
    required this.pick,
    required this.actions,
  });

  final List<DesignLayer> layers;

  /// The screen the layers are of.
  final String? screen;
  final DesignPick? pick;
  final InspectorActions actions;

  @override
  State<DesignInspector> createState() => _DesignInspectorState();
}

class _DesignInspectorState extends State<DesignInspector> {
  var _level = InspectorLevel.simple;
  final _open = <String>{};

  @override
  void didUpdateWidget(DesignInspector old) {
    super.didUpdateWidget(old);
    // What is picked shows in its layers: each level above it opened.
    if (widget.pick?.id case final id? when id != old.pick?.id) {
      final parts = id.split('.');
      for (var i = 1; i < parts.length; i++) {
        _open.add(parts.sublist(0, i).join('.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.border)),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          _heading(context, 'Layers', widget.screen),
          Flexible(flex: 2, child: _layerList(context)),
          Container(height: 1, color: c.border),
          Expanded(flex: 3, child: _properties(context)),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String title, String? detail) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          Text(title, style: t.text.xs.copyWith(fontWeight: .w600)),
          if (detail != null) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: .ellipsis,
                style: t.text.xs.copyWith(color: t.colors.mutedForeground),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- Layers --------------------------------------------------------------

  List<(DesignLayer, int)> _rows() {
    final out = <(DesignLayer, int)>[];
    void walk(List<DesignLayer> layers, int depth) {
      for (final l in layers) {
        out.add((l, depth));
        if (l.children.isNotEmpty && _open.contains(l.id)) walk(l.children, depth + 1);
      }
    }

    walk(widget.layers, 0);
    return out;
  }

  Widget _layerList(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    if (widget.layers.isEmpty) {
      return Padding(
        padding: const .fromLTRB(12, 0, 12, 12),
        child: Text(
          'Pick a screen to see what is in it.',
          style: t.text.xs.copyWith(color: c.mutedForeground),
        ),
      );
    }
    final rows = _rows();
    return ScrollArea.builder(
      itemCount: rows.length,
      itemExtent: 26,
      itemBuilder: (context, i) {
        final (layer, depth) = rows[i];
        final picked = layer.id == widget.pick?.id;
        final open = _open.contains(layer.id);
        return MouseRegion(
          onEnter: (_) => widget.actions.point(layer.id),
          onExit: (_) => widget.actions.point(null),
          child: Pressable(
            onPressed: () => widget.actions.select(layer.id),
            semanticLabel: layer.name,
            builder: (context, states) => Container(
              color: picked
                  ? c.accent
                  : states.hovered
                  ? c.muted
                  : const Color(0x00000000),
              padding: EdgeInsets.only(left: 8.0 + depth * 12, right: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: layer.children.isEmpty
                        ? null
                        : Pressable(
                            onPressed: () => setState(() {
                              if (!_open.remove(layer.id)) _open.add(layer.id);
                            }),
                            semanticLabel: open ? 'Close' : 'Open',
                            builder: (context, _) => AshlarIcon(
                              open
                                  ? AshlarIconsRoundedStroke.chevronDown
                                  : AshlarIconsRoundedStroke.chevronRight,
                              size: 12,
                              color: c.mutedForeground,
                            ),
                          ),
                  ),
                  Expanded(
                    child: Text(
                      layer.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: t.text.xs.copyWith(fontWeight: picked ? .w600 : null),
                    ),
                  ),
                  Text(layer.tag, style: t.text.xs.copyWith(color: c.mutedForeground)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- What is picked ----------------------------------------------------

  Widget _properties(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final p = widget.pick;
    if (p == null || p.screen) {
      return Padding(
        padding: const .all(12),
        child: Text(
          p == null
              ? 'Pick something on a screen, or in the layers above, to change it here.'
              : 'Pick something on this screen to change it.',
          style: t.text.xs.copyWith(color: c.mutedForeground),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(12, 10, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: t.text.sm.copyWith(fontWeight: .w600),
                ),
              ),
              if (p.parents.isNotEmpty)
                Tooltip(
                  message: 'Pick what holds it (Esc): ${p.parents.last.name}',
                  child: Button(
                    variant: .ghost,
                    size: .iconXs,
                    semanticLabel: 'Pick what holds it',
                    onPressed: widget.actions.up,
                    child: const AshlarIcon(AshlarIconsRoundedStroke.cornerLeftUp, size: 14),
                  ),
                ),
            ],
          ),
        ),
        if (p.scripted)
          _notice(
            context,
            'A script builds this screen, so Helmy makes these changes for you: '
            'they go to the chat as a request.',
          ),
        for (final i in p.issues.where((i) => !_shown.contains(i.what.split(':').first.trim())))
          _notice(context, "Won't convert to Flutter: ${i.what}. ${i.why}", warn: true),
        Padding(
          padding: const .fromLTRB(12, 6, 12, 6),
          child: ToggleGroup<InspectorLevel>(
            values: {_level},
            size: .sm,
            semanticLabel: 'How much to show',
            onChanged: (v) {
              if (v.isNotEmpty) setState(() => _level = v.first);
            },
            items: const [
              ToggleGroupItem(InspectorLevel.simple, Text('Simple')),
              ToggleGroupItem(InspectorLevel.pro, Text('Pro')),
              ToggleGroupItem(InspectorLevel.code, Text('Code')),
            ],
          ),
        ),
        Expanded(
          child: ScrollArea(
            padding: const .fromLTRB(12, 4, 12, 16),
            child: _level == InspectorLevel.code ? _code(p) : _fields(context, p),
          ),
        ),
      ],
    );
  }

  /// Properties with a field of their own here: their issue shows on the field.
  static const _shown = {
    'display', 'flex-wrap', 'position', 'filter', 'transform', 'box-shadow', 'overflow', //
    'font-family', 'letter-spacing', 'text-transform', 'opacity',
  };

  Widget _notice(BuildContext context, String text, {bool warn = false}) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Container(
      margin: const .fromLTRB(12, 4, 12, 4),
      padding: const .all(8),
      decoration: BoxDecoration(color: c.muted, borderRadius: .circular(6)),
      child: Row(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          AshlarIcon(
            warn ? AshlarIconsRoundedStroke.triangleAlert : AshlarIconsRoundedStroke.sparkles,
            size: 14,
            color: c.mutedForeground,
          ),
          Expanded(child: Text(text, style: t.text.xs)),
        ],
      ),
    );
  }

  Widget _code(DesignPick p) =>
      _HtmlEditor(key: ValueKey('${p.file}#${p.id}'), html: p.html, onApply: widget.actions.html);

  Widget _fields(BuildContext context, DesignPick p) {
    final pro = _level == InspectorLevel.pro;
    final s = widget.actions.style;
    Widget len(String label, String prop, {String unit = 'px'}) => _CssField(
      key: ValueKey('${p.file}#${p.id}#$prop'),
      label: label,
      value: p.written(prop),
      unit: unit,
      issue: p.issueFor(prop),
      onSubmitted: (v) => s({prop: v}),
    );
    Widget four(String label, String prop) => _Group(
      label: label,
      child: Row(
        spacing: 4,
        children: [
          for (final (side, short) in [
            ('top', 'T'),
            ('right', 'R'),
            ('bottom', 'B'),
            ('left', 'L'),
          ])
            Expanded(child: len(short, '$prop-$side')),
        ],
      ),
    );
    // Type settings where there are words: every element has a font size, a box of others has no words of its own.
    final hasText = p.text != null || ['Text', 'Button', 'Link', 'Field'].any(p.name.startsWith);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 10,
      children: [
        if (hasText)
          _Section(
            title: 'Text',
            children: [
              if (p.text != null)
                _TextField(
                  key: ValueKey('${p.file}#${p.id}#text'),
                  value: p.text!,
                  onSubmitted: widget.actions.text,
                ),
              _CssField(
                key: ValueKey('${p.file}#${p.id}#font-family'),
                label: 'Font',
                value: p.style('font-family'),
                unit: '',
                issue: p.issueFor('font-family'),
                onSubmitted: (v) => s({'font-family': v}),
              ),
              Row(
                spacing: 6,
                children: [
                  Expanded(child: len('Size', 'font-size')),
                  Expanded(
                    child: Select<String>(
                      value: _weight(p.style('font-weight')),
                      size: .sm,
                      semanticLabel: 'Weight',
                      options: [for (final (w, name) in _weights) SelectOption(w, name)],
                      onChanged: (w) => s({'font-weight': w}),
                    ),
                  ),
                ],
              ),
              _ColorField(
                label: 'Color',
                value: p.style('color'),
                onChanged: (v) => s({'color': v}),
              ),
              Row(
                spacing: 6,
                children: [
                  ToggleGroup<String>(
                    values: {_align(p.style('text-align'))},
                    size: .sm,
                    semanticLabel: 'Alignment',
                    onChanged: (v) {
                      if (v.isNotEmpty) s({'text-align': v.first});
                    },
                    items: const [
                      ToggleGroupItem(
                        'left',
                        AshlarIcon(AshlarIconsRoundedStroke.textAlignStart, size: 14),
                        semanticLabel: 'Left',
                      ),
                      ToggleGroupItem(
                        'center',
                        AshlarIcon(AshlarIconsRoundedStroke.textAlignCenter, size: 14),
                        semanticLabel: 'Center',
                      ),
                      ToggleGroupItem(
                        'right',
                        AshlarIcon(AshlarIconsRoundedStroke.textAlignEnd, size: 14),
                        semanticLabel: 'Right',
                      ),
                      ToggleGroupItem(
                        'justify',
                        AshlarIcon(AshlarIconsRoundedStroke.textAlignJustify, size: 14),
                        semanticLabel: 'Justify',
                      ),
                    ],
                  ),
                  ToggleGroup<String>(
                    multiple: true,
                    size: .sm,
                    semanticLabel: 'Style',
                    values: {
                      if (p.style('font-style') == 'italic') 'italic',
                      if (p.style('text-decoration-line').contains('underline')) 'underline',
                      if (p.style('text-decoration-line').contains('line-through')) 'strike',
                    },
                    onChanged: (v) => s({
                      'font-style': v.contains('italic') ? 'italic' : 'normal',
                      'text-decoration-line': [
                        if (v.contains('underline')) 'underline',
                        if (v.contains('strike')) 'line-through',
                      ].join(' ').ifEmpty('none'),
                    }),
                    items: const [
                      ToggleGroupItem(
                        'italic',
                        AshlarIcon(AshlarIconsRoundedStroke.italic, size: 14),
                        semanticLabel: 'Italic',
                      ),
                      ToggleGroupItem(
                        'underline',
                        AshlarIcon(AshlarIconsRoundedStroke.underline, size: 14),
                        semanticLabel: 'Underline',
                      ),
                      ToggleGroupItem(
                        'strike',
                        AshlarIcon(AshlarIconsRoundedStroke.strikethrough, size: 14),
                        semanticLabel: 'Strikethrough',
                      ),
                    ],
                  ),
                ],
              ),
              if (pro)
                Row(
                  spacing: 6,
                  children: [
                    Expanded(child: len('Leading', 'line-height', unit: '')),
                    Expanded(child: len('Tracking', 'letter-spacing')),
                  ],
                ),
              if (pro)
                Select<String>(
                  value: p.style('text-transform').ifEmpty('none'),
                  size: .sm,
                  semanticLabel: 'Case',
                  options: const [
                    SelectOption('none', 'Case as written'),
                    SelectOption('uppercase', 'UPPERCASE'),
                    SelectOption('lowercase', 'lowercase'),
                    SelectOption('capitalize', 'Capitalized'),
                  ],
                  onChanged: (v) => s({'text-transform': v}),
                ),
            ],
          ),
        _Section(
          title: 'Size',
          children: [
            for (final (axis, label, mode, px) in [
              ('width', 'Width', p.sizingW, p.width),
              ('height', 'Height', p.sizingH, p.height),
            ])
              Row(
                spacing: 6,
                children: [
                  Expanded(
                    child: _CssField(
                      key: ValueKey('${p.file}#${p.id}#$axis#$px'),
                      label: label,
                      value: '${px}px',
                      unit: 'px',
                      onSubmitted: (v) => widget.actions.sizing(
                        axis,
                        'fixed',
                        num.tryParse(v.replaceAll('px', '')),
                      ),
                    ),
                  ),
                  ToggleGroup<String>(
                    values: {mode},
                    size: .sm,
                    semanticLabel: '$label sizing',
                    onChanged: (v) {
                      if (v.isNotEmpty) widget.actions.sizing(axis, v.first, null);
                    },
                    items: const [
                      ToggleGroupItem('hug', Text('Hug')),
                      ToggleGroupItem('fixed', Text('Fixed')),
                      ToggleGroupItem('fill', Text('Fill')),
                    ],
                  ),
                ],
              ),
            if (pro)
              Row(
                spacing: 6,
                children: [
                  Expanded(child: len('Min W', 'min-width')),
                  Expanded(child: len('Max W', 'max-width')),
                ],
              ),
            if (pro)
              Row(
                spacing: 6,
                children: [
                  Expanded(child: len('Min H', 'min-height')),
                  Expanded(child: len('Max H', 'max-height')),
                ],
              ),
          ],
        ),
        _Section(
          title: 'Spacing',
          children: [
            four('Padding', 'padding'),
            len('Gap', 'gap'),
            if (pro) four('Margin', 'margin'),
          ],
        ),
        if (pro)
          _Section(
            title: 'Layout',
            children: [
              _SelectField(
                label: 'Display',
                value: p.style('display'),
                issue: p.issueFor('display'),
                options: const [
                  'block',
                  'flex',
                  'inline-flex',
                  'inline',
                  'inline-block',
                  'grid',
                  'none',
                ],
                onChanged: (v) => s({'display': v}),
              ),
              if (p.style('display').contains('flex')) ...[
                ToggleGroup<String>(
                  values: {p.style('flex-direction').startsWith('column') ? 'column' : 'row'},
                  size: .sm,
                  semanticLabel: 'Direction',
                  onChanged: (v) {
                    if (v.isNotEmpty) s({'flex-direction': v.first});
                  },
                  items: const [
                    ToggleGroupItem('row', Text('Across')),
                    ToggleGroupItem('column', Text('Down')),
                  ],
                ),
                _SelectField(
                  label: 'Justify',
                  value: p.style('justify-content'),
                  options: const [
                    'flex-start',
                    'center',
                    'flex-end',
                    'space-between',
                    'space-around',
                    'space-evenly',
                  ],
                  onChanged: (v) => s({'justify-content': v}),
                ),
                _SelectField(
                  label: 'Align',
                  value: p.style('align-items'),
                  options: const ['stretch', 'flex-start', 'center', 'flex-end', 'baseline'],
                  onChanged: (v) => s({'align-items': v}),
                ),
                _SelectField(
                  label: 'Wrap',
                  value: p.style('flex-wrap'),
                  issue: p.issueFor('flex-wrap'),
                  options: const ['nowrap', 'wrap'],
                  onChanged: (v) => s({'flex-wrap': v}),
                ),
              ],
            ],
          ),
        if (pro)
          _Section(
            title: 'Position',
            children: [
              _SelectField(
                label: 'Position',
                value: p.style('position'),
                issue: p.issueFor('position'),
                options: const ['static', 'relative', 'absolute', 'fixed', 'sticky'],
                onChanged: (v) => s({'position': v}),
              ),
              if (p.style('position') != 'static')
                Row(
                  spacing: 4,
                  children: [
                    for (final (side, short) in [
                      ('top', 'T'),
                      ('right', 'R'),
                      ('bottom', 'B'),
                      ('left', 'L'),
                    ])
                      Expanded(child: len(short, side)),
                  ],
                ),
              len('Z-index', 'z-index', unit: ''),
            ],
          ),
        _Section(
          title: 'Appearance',
          children: [
            _ColorField(
              label: 'Fill',
              value: p.style('background-color'),
              onChanged: (v) => s({'background-color': v}),
              none: () => s({'background-color': 'transparent'}),
            ),
            Row(
              spacing: 6,
              children: [
                Expanded(
                  child: _CssField(
                    key: ValueKey('${p.file}#${p.id}#radius'),
                    label: 'Radius',
                    value: p.style('border-top-left-radius'),
                    unit: 'px',
                    onSubmitted: (v) => s({'border-radius': v}),
                  ),
                ),
                if (pro) Expanded(child: len('Opacity', 'opacity', unit: '')),
              ],
            ),
            if (pro)
              _SelectField(
                label: 'Overflow',
                value: p.style('overflow'),
                issue: p.issueFor('overflow'),
                options: const ['visible', 'hidden', 'clip', 'auto', 'scroll'],
                onChanged: (v) => s({'overflow': v}),
              ),
            if (pro) len('Shadow', 'box-shadow', unit: ''),
            if (pro) len('Transform', 'transform', unit: ''),
            if (pro) len('Filter', 'filter', unit: ''),
          ],
        ),
        _Section(
          title: 'Border',
          children: [
            Row(
              spacing: 6,
              children: [
                Expanded(
                  child: _CssField(
                    key: ValueKey('${p.file}#${p.id}#border-width'),
                    label: 'Width',
                    value: p.style('border-top-width'),
                    unit: 'px',
                    onSubmitted: (v) => s({
                      'border-width': v,
                      if (p.style('border-top-style') == 'none') 'border-style': 'solid',
                    }),
                  ),
                ),
                Expanded(
                  child: Select<String>(
                    value: p.style('border-top-style').ifEmpty('none'),
                    size: .sm,
                    semanticLabel: 'Border style',
                    options: const [
                      SelectOption('none', 'None'),
                      SelectOption('solid', 'Solid'),
                      SelectOption('dashed', 'Dashed'),
                      SelectOption('dotted', 'Dotted'),
                    ],
                    onChanged: (v) => s({'border-style': v}),
                  ),
                ),
              ],
            ),
            _ColorField(
              label: 'Color',
              value: p.style('border-top-color'),
              onChanged: (v) => s({'border-color': v}),
            ),
          ],
        ),
      ],
    );
  }

  static const _weights = [
    ('100', 'Thin'),
    ('200', 'Extra light'),
    ('300', 'Light'),
    ('400', 'Regular'),
    ('500', 'Medium'),
    ('600', 'Semibold'),
    ('700', 'Bold'),
    ('800', 'Extra bold'),
    ('900', 'Black'),
  ];

  static String _weight(String w) => switch (w) {
    'normal' => '400',
    'bold' => '700',
    _ => _weights.any((x) => x.$1 == w) ? w : '400',
  };

  static String _align(String a) => switch (a) {
    'start' || '-webkit-auto' || 'auto' || '' => 'left',
    'end' => 'right',
    _ => a,
  };
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// A titled run of fields.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 6,
      children: [
        Text(
          title,
          style: t.text.xs.copyWith(fontWeight: .w600, color: t.colors.mutedForeground),
        ),
        ...children,
      ],
    );
  }
}

/// A label over a row of fields.
class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        Text(label, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
        child,
      ],
    );
  }
}

/// What won't convert, on the field that sets it.
Widget _issueMark(BuildContext context, String? why) => why == null
    ? const SizedBox.shrink()
    : Tooltip(
        message: "Won't convert to Flutter. $why",
        child: AshlarIcon(
          AshlarIconsRoundedStroke.triangleAlert,
          size: 13,
          color: AshlarTheme.of(context).colors.mutedForeground,
        ),
      );

/// A CSS value to type: a bare number takes [unit]; Enter or leaving sets it.
class _CssField extends StatefulWidget {
  const _CssField({
    super.key,
    required this.label,
    required this.value,
    required this.onSubmitted,
    this.unit = 'px',
    this.issue,
  });

  final String label, value, unit;
  final ValueChanged<String> onSubmitted;
  final String? issue;

  @override
  State<_CssField> createState() => _CssFieldState();
}

class _CssFieldState extends State<_CssField> {
  late final _text = TextEditingController(text: _shown(widget.value));
  final _focus = FocusNode();

  /// 16px shows as 16, rounded to two places; anything else as it is.
  static String _shown(String v) {
    final m = RegExp(r'^(-?[\d.]+)px$').firstMatch(v.trim());
    if (m == null) return v;
    final n = double.parse(m[1]!);
    return n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // After the click has put the caret down.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focus.hasFocus) {
            _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
          }
        });
      } else {
        _submit();
      }
    });
  }

  @override
  void didUpdateWidget(_CssField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _text.text = _shown(widget.value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    if (v == _shown(widget.value)) return;
    widget.onSubmitted(
      RegExp(r'^-?[\d.]+$').hasMatch(v) && widget.unit.isNotEmpty ? '$v${widget.unit}' : v,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Input(
      controller: _text,
      focusNode: _focus,
      size: .sm,
      semanticLabel: widget.label,
      autocorrect: false,
      enableSuggestions: false,
      leading: Text(widget.label, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
      trailing: _issueMark(context, widget.issue),
      onSubmitted: (_) => _submit(),
    );
  }
}

/// An element's words, set on Enter or on leaving.
class _TextField extends StatefulWidget {
  const _TextField({super.key, required this.value, required this.onSubmitted});
  final String value;
  final ValueChanged<String> onSubmitted;

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // After the click has put the caret down.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focus.hasFocus) {
            _text.selection = TextSelection(baseOffset: 0, extentOffset: _text.text.length);
          }
        });
      } else if (_text.text != widget.value) {
        widget.onSubmitted(_text.text);
      }
    });
  }

  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && old.value != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Input(
    controller: _text,
    focusNode: _focus,
    size: .sm,
    semanticLabel: 'Words',
    placeholder: 'Words',
    onSubmitted: (v) {
      if (v != widget.value) widget.onSubmitted(v);
    },
  );
}

/// A choice of CSS keywords; the value now is listed even when not one of them.
class _SelectField extends StatelessWidget {
  const _SelectField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.issue,
  });

  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? issue;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final all = [...options, if (value.isNotEmpty && !options.contains(value)) value];
    return Row(
      spacing: 6,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
        ),
        Expanded(
          child: Select<String>(
            value: value.isEmpty ? null : value,
            size: .sm,
            semanticLabel: label,
            options: [for (final o in all) SelectOption(o, o)],
            onChanged: onChanged,
          ),
        ),
        _issueMark(context, issue),
      ],
    );
  }
}

/// A colour, as CSS computes it, picked in Ashlar's picker.
class _ColorField extends StatelessWidget {
  const _ColorField({required this.label, required this.value, required this.onChanged, this.none});

  final String label, value;
  final ValueChanged<String> onChanged;

  /// Takes the colour away (a fill), where that makes sense.
  final VoidCallback? none;

  @override
  Widget build(BuildContext context) {
    final color = cssColor(value) ?? const Color(0x00000000);
    return Row(
      spacing: 6,
      children: [
        Expanded(
          child: ColorPickerButton(
            label: label,
            alpha: true,
            value: color,
            onChanged: (c) => onChanged(colorCss(c)),
          ),
        ),
        if (none != null && color.a > 0)
          Tooltip(
            message: 'No $label',
            child: Button(
              variant: .ghost,
              size: .iconXs,
              semanticLabel: 'No ${label.toLowerCase()}',
              onPressed: none,
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
            ),
          ),
      ],
    );
  }
}

/// A colour as the page computes it (`rgb(24, 24, 20)`, `rgba(0, 0, 0, 0.5)`,
/// `rgb(24 24 20 / 50%)`, or hex), or null.
Color? cssColor(String css) {
  final s = css.trim();
  if (s.startsWith('#')) return parseColorHex(s.substring(1));
  final m = RegExp(r'^rgba?\(([^)]*)\)$').firstMatch(s);
  if (m == null) return null;
  final parts = m[1]!.split(RegExp(r'[\s,/]+')).where((p) => p.isNotEmpty).toList();
  if (parts.length < 3) return null;
  int ch(String p) =>
      (p.endsWith('%') ? double.parse(p.replaceAll('%', '')) * 2.55 : double.parse(p))
          .round()
          .clamp(0, 255);
  final a = parts.length > 3
      ? (parts[3].endsWith('%')
            ? double.parse(parts[3].replaceAll('%', '')) / 100
            : double.parse(parts[3]))
      : 1.0;
  return Color.fromARGB((a * 255).round().clamp(0, 255), ch(parts[0]), ch(parts[1]), ch(parts[2]));
}

/// [c] as CSS: hex when opaque, else rgba.
String colorCss(Color c) {
  int ch(double v) => (v * 255).round().clamp(0, 255);
  final (r, g, b) = (ch(c.r), ch(c.g), ch(c.b));
  if (c.a >= 1) return '#${[r, g, b].map((v) => v.toRadixString(16).padLeft(2, '0')).join()}';
  return 'rgba($r, $g, $b, ${(c.a * 100).round() / 100})';
}

/// The picked element's HTML, to change and apply.
class _HtmlEditor extends StatefulWidget {
  const _HtmlEditor({super.key, required this.html, required this.onApply});
  final String? html;
  final ValueChanged<String> onApply;

  @override
  State<_HtmlEditor> createState() => _HtmlEditorState();
}

class _HtmlEditorState extends State<_HtmlEditor> {
  late final _text = TextEditingController(text: widget.html ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (widget.html == null) {
      return Text(
        'This element is too large to edit here. Pick something inside it.',
        style: t.text.xs.copyWith(color: t.colors.mutedForeground),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        Textarea(controller: _text, minLines: 8, maxLines: 24, resizable: false),
        Align(
          alignment: .centerRight,
          child: Button(
            size: .sm,
            onPressed: () => widget.onApply(_text.text),
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}
