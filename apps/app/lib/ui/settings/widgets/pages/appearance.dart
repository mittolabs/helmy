part of '../settings_screen.dart';

/// How Helmy looks: its theme, the size of its text, how wide a
/// conversation reads.
class _Appearance extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Theme and text', first: true),
        _Row(
          title: 'Theme',
          control: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final choice in ThemeChoice.values)
                _ThemeCard(
                  choice: choice,
                  selected: s.theme == choice,
                  onPressed: () => vm.update(s.copyWith(theme: choice)),
                ),
            ],
          ),
        ),
        _Row(
          title: 'Colors',
          description: 'For light and dark alike. Helmy\'s own is pure black when dark.',
          control: SizedBox(
            // Named, as greys this close tell apart only in use.
            width: 300,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in Palette.values)
                  _PaletteChip(
                    label: p.label,
                    selected: s.palette == p,
                    onPressed: () => vm.update(s.copyWith(palette: p)),
                    colors: (b) => themeFor(b, palette: p, accent: s.accent).colors,
                  ),
              ],
            ),
          ),
        ),
        _Row(
          title: 'Accent',
          description: 'A color for the main buttons and what is chosen.',
          control: SizedBox(
            // Four to a line: they wrap rather than push past the page.
            width: 4 * 38.0,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in AccentChoice.values)
                  _Swatch(
                    label: a == .none ? 'None' : '${a.name[0].toUpperCase()}${a.name.substring(1)}',
                    selected: s.accent == a,
                    onPressed: () => vm.update(s.copyWith(accent: a)),
                    colors: (b) => themeFor(b, palette: s.palette, accent: a).colors,
                    dot: true,
                  ),
              ],
            ),
          ),
        ),
        _Row(
          title: 'Text size',
          control: _Choice<TextSize>(
            value: s.textSize,
            label: 'Text size',
            options: {for (final v in TextSize.values) v: v.label},
            onChanged: (v) => vm.update(s.copyWith(textSize: v)),
          ),
        ),
        ..._fonts(context, vm),
        _Row(
          title: 'Contrast',
          description: 'Firmer borders and quieter text a little louder, for reading at a glance.',
          control: _Choice<double>(
            value: const [0.0, .5, 1.0].contains(s.contrast) ? s.contrast : 0,
            label: 'Contrast',
            options: {0.0: 'As designed', .5: 'Firmer', 1.0: 'Firmest'},
            onChanged: (v) => vm.update(s.copyWith(contrast: v)),
          ),
        ),
        _Row(
          title: 'Time format',
          description: 'How clock times read: when a message came, a snooze ends, a task runs.',
          control: SizedBox(
            width: 190,
            child: Select<ClockFormat>(
              size: .sm,
              value: s.clock,
              semanticLabel: 'Time format',
              options: [for (final f in ClockFormat.values) SelectOption(f, f.label)],
              onChanged: (f) => vm.update(s.copyWith(clock: f)),
            ),
          ),
        ),
        _Row(
          title: 'Conversation width',
          control: _Choice<Width>(
            value: s.width,
            label: 'Conversation width',
            options: {for (final v in Width.values) v: v.label},
            onChanged: (v) => vm.update(s.copyWith(width: v)),
          ),
        ),
        _Row(
          title: 'Wrap long code blocks',
          description: 'Long lines in code wrap onto the next line, rather than scroll sideways.',
          control: Switch(
            value: s.wrapCode,
            semanticLabel: 'Wrap long code blocks',
            onChanged: (v) => vm.update(s.copyWith(wrapCode: v)),
          ),
        ),
        _Row(
          title: 'Colors for changes',
          description:
              'What a thread added and removed in files. Blue and orange read apart for the '
              'commonest kinds of color blindness.',
          control: SizedBox(
            width: 230,
            child: Select<DiffColors>(
              size: .sm,
              value: s.diffColors,
              semanticLabel: 'Colors for changes',
              options: [for (final d in DiffColors.values) SelectOption(d, d.label)],
              onChanged: (d) => vm.update(s.copyWith(diffColors: d)),
            ),
          ),
        ),
        _Row(
          title: 'Hide changes only in spaces',
          description: 'A line whose only change is its spaces or tabs shows as unchanged.',
          control: Switch(
            value: s.diffHideSpace,
            semanticLabel: 'Hide changes only in spaces',
            onChanged: (v) => vm.update(s.copyWith(diffHideSpace: v)),
          ),
        ),
        _Row(
          title: 'Changes in one column',
          description:
              'Before and after one above the other, always; off, they sit side by side '
              'where there is room.',
          control: Switch(
            value: s.diffStacked,
            semanticLabel: 'Changes in one column',
            onChanged: (v) => vm.update(s.copyWith(diffStacked: v)),
          ),
        ),
        _Row(
          title: "Each file's change open",
          description: 'In a thread\'s changes, every file shows what changed without a click.',
          control: Switch(
            value: s.diffFilesOpen,
            semanticLabel: "Each file's change open",
            onChanged: (v) => vm.update(s.copyWith(diffFilesOpen: v)),
          ),
        ),
      ],
    );
  }
}

/// One choice of colors: a circle drawn in them (the page and its raised
/// parts, or as a [dot] the main color), with its name under the pointer.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.colors,
    this.dot = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final AshlarColors Function(Brightness brightness) colors;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = colors(t.brightness);
    final grey = dot && label == 'None';
    return Tooltip(
      message: label,
      child: Pressable(
        onPressed: onPressed,
        selected: selected,
        semanticLabel: label,
        builder: (context, state) => Container(
          width: 30,
          height: 30,
          padding: const .all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? t.colors.ring
                  : (state.hovered ? t.colors.border : const Color(0x00000000)),
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: t.colors.border),
              color: dot ? (grey ? t.colors.muted : c.primary) : null,
              gradient: dot
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [.5, .5],
                      colors: [c.background, c.muted],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A palette by name, drawn in its own colors: its raised surface, its
/// words, and the tint of its quieter words.
class _PaletteChip extends StatelessWidget {
  const _PaletteChip({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.colors,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final AshlarColors Function(Brightness brightness) colors;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = colors(t.brightness);
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: label,
      builder: (context, state) => Container(
        padding: const .fromLTRB(8, 5, 10, 5),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: .circular(t.radiusMd),
          border: Border.all(
            color: selected ? t.colors.ring : (state.hovered ? c.mutedForeground : c.border),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: .min,
          spacing: 6,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c.mutedForeground, shape: BoxShape.circle),
            ),
            Text(
              label,
              style: t.text.xs.copyWith(color: c.foreground, fontWeight: .w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// The fonts: the interface's, code's, and messages' as typed, each the
/// system's own until another is chosen, with a sample of all three.
List<Widget> _fonts(BuildContext context, SettingsViewModel vm) {
  final s = vm.settings;
  final fonts = vm.fonts;
  if (fonts == null) unawaited(vm.loadFonts());
  Widget pick(String label, String? value, List<String> names, void Function(String?) set) =>
      SizedBox(
        width: 210,
        child: Select<String>(
          size: .sm,
          value: value ?? '',
          semanticLabel: label,
          options: [
            const SelectOption('', 'System'),
            for (final n in {...names, ?value}) SelectOption(n, n),
          ],
          onChanged: (v) => set(v.isEmpty ? '' : v),
        ),
      );
  final t = AshlarTheme.of(context);
  return [
    _Row(
      title: 'Interface font',
      description: fonts == null ? 'Reading the fonts on this computer...' : null,
      control: pick(
        'Interface font',
        s.interfaceFont,
        fonts?.all ?? const [],
        (v) => vm.update(s.copyWith(interfaceFont: v)),
      ),
    ),
    _Row(
      title: 'Code font',
      description: 'For code in answers, changes and the terminal.',
      control: pick(
        'Code font',
        s.codeFont,
        fonts?.fixed ?? const [],
        (v) => vm.update(s.copyWith(codeFont: v)),
      ),
    ),
    _Row(
      title: 'Message font',
      description: 'For what you type, where it differs from the interface.',
      control: pick(
        'Message font',
        s.promptFont,
        fonts?.all ?? const [],
        (v) => vm.update(s.copyWith(promptFont: v)),
      ),
    ),
    _Block(
      title: 'Sample',
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 6,
        children: [
          Text('Plan the trip to the coast for the long weekend.', style: t.text.sm),
          Text(
            'Plan the trip to the coast, and book it.',
            style: t.text.sm.copyWith(fontFamily: s.promptFont ?? t.text.fontFamily),
          ),
          Text(
            'final days = trip.end.difference(trip.start).inDays;',
            style: t.text.xs.copyWith(fontFamily: 'monospace', fontFamilyFallback: monoFonts),
          ),
        ],
      ),
    ),
  ];
}
