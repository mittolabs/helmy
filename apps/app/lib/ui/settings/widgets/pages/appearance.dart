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
