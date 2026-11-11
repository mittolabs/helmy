part of '../settings_screen.dart';

/// How Helmy looks: its theme, the size of its text, how wide a
/// conversation reads.
class _Appearance extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    final imported = importedThemeFromJson(s.themeImport);
    return _Page(
      children: [
        const _Heading('Theme and text', first: true),
        // As T3 Code shows its color scheme: three cards, each a picture of
        // the app in it, in the palette and accent chosen below.
        _Block(
          title: 'Theme',
          child: LayoutBuilder(
            builder: (context, box) {
              final across = box.maxWidth >= 420 ? 3 : 1;
              final width = (box.maxWidth - 10 * (across - 1)) / across;
              AshlarColors look(Brightness b) =>
                  themeFor(b, palette: s.palette, accent: s.accent, imported: imported).colors;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final choice in ThemeChoice.values)
                    SizedBox(
                      width: width,
                      child: _SchemeCard(
                        choice: choice,
                        selected: s.theme == choice,
                        onPressed: () => vm.update(s.copyWith(theme: choice)),
                        light: look(Brightness.light),
                        dark: look(Brightness.dark),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // As T3 Code shows its themes: a card each, its light and dark side
        // by side, the one in use ringed.
        _Block(
          title: 'Colors',
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Text(
                imported != null && s.palette == .imported
                    ? '${imported.name}, from VS Code, when ${imported.dark ? 'dark' : 'light'}; '
                          "Helmy's own otherwise."
                    : "For light and dark alike. Helmy's own is pure black when dark.",
                style: AshlarTheme.of(context).text.xs
                    .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
              ),
              LayoutBuilder(
                builder: (context, box) {
                  // A card needs room for its two orbs: as many across as fit, at most 3.
                  final across = (box.maxWidth / 150).floor().clamp(1, 3);
                  final width = (box.maxWidth - 10 * (across - 1)) / across;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final p in Palette.values)
                        if (p != .imported || imported != null)
                          SizedBox(
                            width: width,
                            child: _PaletteCard(
                              label: p == .imported ? imported!.name : p.label,
                              selected: s.palette == p,
                              onPressed: () => vm.update(s.copyWith(palette: p)),
                              colors: (b) => themeFor(
                                b,
                                palette: p,
                                accent: s.accent,
                                imported: imported,
                              ).colors,
                            ),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        // Right after the colors it tints: each accent a lit orb, named.
        _Block(
          title: 'Accent',
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Text(
                'A color for the main buttons and what is chosen.',
                style: AshlarTheme.of(context).text.xs
                    .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 10,
                children: [
                  for (final a in AccentChoice.values)
                    _AccentChoice(
                      label: a == .none
                          ? 'None'
                          : '${a.name[0].toUpperCase()}${a.name.substring(1)}',
                      selected: s.accent == a,
                      onPressed: () => vm.update(s.copyWith(accent: a)),
                      color: a == .none
                          ? null
                          : themeFor(
                              AshlarTheme.of(context).brightness,
                              palette: s.palette,
                              accent: a,
                            ).colors.primary,
                    ),
                ],
              ),
            ],
          ),
        ),
        _Row(
          title: 'A theme from VS Code',
          description:
              'A color theme file (.json), as VS Code themes are made: its colors become '
              "Helmy's, for light or dark as the theme is.",
          control: SizedBox(
            width: 200,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (imported != null)
                  Button(
                    variant: .ghost,
                    size: .sm,
                    onPressed: () => vm.update(
                      AppSettings.fromJson({
                        ...s.toJson(),
                        'themeImport': null,
                        'palette': s.palette == .imported ? 'helmy' : s.palette.name,
                      }),
                    ),
                    child: const Text('Remove'),
                  ),
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: () async {
                    final file = await openFile(
                      acceptedTypeGroups: const [
                        XTypeGroup(label: 'VS Code theme', extensions: ['json', 'jsonc']),
                      ],
                      confirmButtonText: 'Use this theme',
                    );
                    if (file == null) return;
                    final theme = readVsCodeTheme(
                      await file.readAsString(),
                      fallbackName: file.name.replaceAll(RegExp(r'\.jsonc?$'), ''),
                    );
                    if (!context.mounted) return;
                    if (theme == null) {
                      showToast(
                        context,
                        title: "That file isn't a color theme Helmy can read",
                        description: 'A VS Code color theme has editor colors in a "colors" list.',
                        type: .error,
                      );
                      return;
                    }
                    await vm.update(
                      s.copyWith(palette: .imported, themeImport: importedThemeToJson(theme)),
                    );
                    if (!context.mounted) return;
                    showToast(
                      context,
                      title: '${theme.name} in use',
                      description: 'For ${theme.dark ? 'dark' : 'light'}; pick Theme to see it.',
                    );
                  },
                  child: Text(imported == null ? 'Import...' : 'Another...'),
                ),
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: () => _findTheme(context, vm),
                  child: const Text('Find one...'),
                ),
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: () => _editTheme(context, vm),
                  child: Text(imported == null ? 'Make one...' : 'Edit...'),
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
/// One accent: a lit orb of its color (none: the palette's own, plain),
/// its name under it; ringed, with a check, when it is the one in use.
class _AccentChoice extends StatelessWidget {
  const _AccentChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  /// Null for none.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final hue = color;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '$label accent',
      builder: (context, state) => SizedBox(
        width: 58,
        child: Column(
          spacing: 6,
          children: [
            Container(
              padding: const .all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? c.ring : (state.hovered ? c.border : const Color(0x00000000)),
                  width: 1.5,
                ),
              ),
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.border),
                  gradient: RadialGradient(
                    center: const Alignment(-.35, -.45),
                    radius: .95,
                    colors: hue == null
                        ? [c.mutedForeground.withValues(alpha: .5), c.muted, c.background]
                        : [
                            Color.lerp(hue, const Color(0xFFFFFFFF), .35)!,
                            hue,
                            Color.lerp(hue, const Color(0xFF000000), .45)!,
                          ],
                    stops: const [0, .55, 1],
                  ),
                ),
                child: selected
                    ? AshlarIcon(
                        AshlarIconsRoundedStroke.check,
                        size: 15,
                        color: hue == null || hue.computeLuminance() > .5
                            ? c.foreground
                            : const Color(0xFFFFFFFF),
                      )
                    : null,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: t.text.xs.copyWith(
                color: selected ? c.foreground : c.mutedForeground,
                fontWeight: selected ? .w500 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A palette by name, drawn in its own colors: its raised surface, its
/// words, and the tint of its quieter words.
/// A color scheme as T3 Code shows one: a card with a picture of the app in
/// it (light, dark, or half of each for following the system), its name
/// under it, ringed when it is the one in use.
class _SchemeCard extends StatelessWidget {
  const _SchemeCard({
    required this.choice,
    required this.selected,
    required this.onPressed,
    required this.light,
    required this.dark,
  });
  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onPressed;
  final AshlarColors light, dark;

  /// The app in [c]: the sidebar's rows, a conversation, a panel beside it,
  /// and the composer with its send button in the accent.
  static Widget _app(AshlarColors c) => Container(
    color: c.background,
    child: Row(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          width: 34,
          padding: const .fromLTRB(5, 8, 5, 8),
          decoration: BoxDecoration(
            color: c.sidebar,
            border: Border(right: BorderSide(color: c.border)),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 4,
            children: [
              Container(height: 5, width: 14, color: c.mutedForeground.withValues(alpha: .6)),
              for (final on in const [true, false, false, false])
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: on ? c.accent : c.muted,
                    borderRadius: .circular(2),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const .fromLTRB(8, 9, 8, 7),
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 4,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Container(
                    height: 7,
                    width: 30,
                    decoration: BoxDecoration(color: c.muted, borderRadius: .circular(4)),
                  ),
                ),
                for (final w in const [.95, .7, .85])
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: w,
                    child: Container(
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: c.mutedForeground.withValues(alpha: .55),
                        borderRadius: .circular(2),
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  height: 13,
                  padding: const .symmetric(horizontal: 3),
                  alignment: AlignmentDirectional.centerEnd,
                  decoration: BoxDecoration(
                    color: c.card,
                    border: Border.all(color: c.border),
                    borderRadius: .circular(7),
                  ),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          width: 26,
          margin: const .fromLTRB(0, 8, 6, 8),
          padding: const .all(4),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: .circular(4),
          ),
          child: Column(
            spacing: 4,
            children: [
              for (var n = 0; n < 3; n++)
                Container(height: 3, color: c.mutedForeground.withValues(alpha: .45)),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final label = switch (choice) {
      .light => 'Light',
      .dark => 'Dark',
      .system => 'System',
    };
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '$label theme',
      builder: (context, state) => Container(
        // The ring's border is a point wider: as much less padding inside.
        padding: selected ? const .fromLTRB(9, 9, 9, 8) : const .fromLTRB(10, 10, 10, 9),
        decoration: BoxDecoration(
          color: state.hovered ? c.accent.withValues(alpha: .4) : c.card,
          borderRadius: .circular(t.radiusLg),
          border: Border.all(color: selected ? c.ring : c.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 9,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: .circular(t.radiusMd),
                  border: Border.all(color: c.border),
                ),
                child: switch (choice) {
                  .light => _app(light),
                  .dark => _app(dark),
                  // Half of each, split down the middle.
                  .system => Stack(
                    fit: StackFit.expand,
                    children: [
                      _app(dark),
                      ClipRect(clipper: const _EndHalf(), child: _app(light)),
                    ],
                  ),
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(label, style: t.text.sm.copyWith(fontWeight: .w500)),
                ),
                if (selected)
                  AshlarIcon(AshlarIconsRoundedStroke.check, size: 14, color: c.foreground),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The end half of what it clips: System's light side.
class _EndHalf extends CustomClipper<Rect> {
  const _EndHalf();
  @override
  Rect getClip(Size size) => Rect.fromLTWH(size.width / 2, 0, size.width / 2, size.height);
  @override
  bool shouldReclip(_EndHalf oldClipper) => false;
}

/// A palette, as T3 Code shows a theme: an orb of its light look and one of
/// its dark, side by side, and its name; ringed when it is the one in use.
class _PaletteCard extends StatelessWidget {
  const _PaletteCard({
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
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: label,
      builder: (context, state) => Container(
        // The ring's border is a point wider: as much less padding inside.
        padding: selected ? const .fromLTRB(11, 15, 11, 9) : const .fromLTRB(12, 16, 12, 10),
        decoration: BoxDecoration(
          color: state.hovered ? c.accent.withValues(alpha: .4) : c.card,
          borderRadius: .circular(t.radiusLg),
          border: Border.all(color: selected ? c.ring : c.border, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              mainAxisAlignment: .center,
              spacing: 10,
              children: [
                _Orb(colors(Brightness.light), ring: selected ? c.ring : null),
                _Orb(colors(Brightness.dark), ring: selected ? c.ring : null),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: t.text.sm.copyWith(fontWeight: .w500),
                  ),
                ),
                if (selected)
                  AshlarIcon(AshlarIconsRoundedStroke.check, size: 14, color: c.foreground),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One side of a palette as a soft lit sphere: its ground, its muted
/// surface and its border, so a tint shows as it does in use.
class _Orb extends StatelessWidget {
  const _Orb(this.c, {this.ring});
  final AshlarColors c;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final dark = c.background.computeLuminance() < .2;
    final orb = Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
        gradient: RadialGradient(
          center: const Alignment(-.35, -.45),
          radius: .95,
          colors: dark
              ? [c.mutedForeground.withValues(alpha: .55), c.muted, c.background]
              // Lit from its muted surface into its border and muted text,
              // where a light palette's tint lives.
              : [c.muted, c.border, c.mutedForeground.withValues(alpha: .75)],
          stops: const [0, .55, 1],
        ),
      ),
    );
    // As much room unringed as the ring takes, so names line up.
    if (ring == null) return Padding(padding: const .all(3.5), child: orb);
    return Container(
      padding: const .all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring!, width: 1.5),
      ),
      child: orb,
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

/// Finds a color theme on Open VSX, the open registry of VS Code
/// extensions, and uses the one picked.
Future<void> _findTheme(BuildContext context, SettingsViewModel vm) async {
  final picked = await showAshlarDialog<ImportedTheme>(
    context: context,
    builder: (context) => const _FindTheme(),
  );
  if (picked == null) return;
  await vm.update(
    vm.settings.copyWith(palette: .imported, themeImport: importedThemeToJson(picked)),
  );
  if (!context.mounted) return;
  showToast(
    context,
    title: '${picked.name} in use',
    description: 'For ${picked.dark ? 'dark' : 'light'}; pick Theme to see it.',
  );
}

class _FindTheme extends StatefulWidget {
  const _FindTheme();

  @override
  State<_FindTheme> createState() => _FindThemeState();
}

class _FindThemeState extends State<_FindTheme> {
  final _market = ThemeMarket();
  final _query = TextEditingController();
  List<ThemeListing>? _found;
  List<ImportedTheme>? _themes;
  String? _busy, _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _busy = 'Looking on Open VSX...');
    final found = await _market.search(q.isEmpty ? 'theme' : q);
    if (!mounted) return;
    setState(() {
      _busy = null;
      _found = found;
      _error = found == null ? "Open VSX couldn't be reached. Check the connection." : null;
    });
  }

  Future<void> _open(ThemeListing l) async {
    setState(() => _busy = 'Reading ${l.name}...');
    try {
      final themes = await _market.themesIn(l.download);
      if (!mounted) return;
      if (themes.length == 1) {
        Navigator.pop(context, themes.single);
        return;
      }
      setState(() {
        _busy = null;
        _themes = themes;
        _error = themes.isEmpty ? '${l.name} has no color theme Helmy can read.' : null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground, height: 1.4);
    final themes = _themes;
    Widget row(String title, String sub, VoidCallback onPressed, String action) => Padding(
      padding: const .symmetric(vertical: 6),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
                if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: .ellipsis, style: muted),
              ],
            ),
          ),
          Button(variant: .outline, size: .sm, onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: 'Find a theme',
        body: 'Color themes from Open VSX, the open registry of VS Code extensions.',
        icon: AshlarIconsRoundedStroke.palette,
        maxWidth: 520,
        content: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          spacing: 8,
          children: [
            if (themes == null)
              Input(
                controller: _query,
                autofocus: true,
                placeholder: 'Dracula, Nord, Solarized...',
                semanticLabel: 'Search themes',
                onChanged: (q) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
                },
              ),
            if (_busy case final busy?)
              Row(
                spacing: 8,
                children: [
                  const Spinner(size: 14),
                  Text(busy, style: muted),
                ],
              ),
            if (_error case final e?) Text(e, style: muted.copyWith(color: t.colors.destructive)),
            ConstrainedBox(
              // As tall as half the window allows: a fixed box was cramped on a big screen.
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(context).height * .5).clamp(240.0, 480.0),
              ),
              child: ScrollArea(
                child: Column(
                  crossAxisAlignment: .stretch,
                  children: [
                    if (themes != null)
                      for (final th in themes)
                        row(
                          th.name,
                          th.dark ? 'Dark' : 'Light',
                          () => Navigator.pop(context, th),
                          'Use',
                        )
                    else
                      for (final l in _found ?? const <ThemeListing>[])
                        row(l.name, l.description, () => _open(l), 'Open'),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (themes != null) DialogButton('Back', onPressed: () => setState(() => _themes = null)),
          DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}

/// The colors a theme of Helmy's own sets, by name, with what each is for.
const _themeColors = [
  ('background', 'Page'),
  ('foreground', 'Text'),
  ('card', 'Cards and panels'),
  ('popover', 'Menus and dialogs'),
  ('sidebar', 'The list of chats'),
  ('muted', 'Fields and quiet fills'),
  ('mutedForeground', 'Quiet text'),
  ('border', 'Lines and borders'),
  ('primary', 'Main buttons'),
  ('primaryForeground', 'Text on main buttons'),
  ('accent', 'Hover and chosen'),
  ('ring', 'Focus'),
  ('destructive', 'Warnings and removing'),
];

/// Edits the imported theme's colors, or makes one from Helmy's own, by
/// hex: each color with a swatch, as it would look.
Future<void> _editTheme(BuildContext context, SettingsViewModel vm) async {
  final now = importedThemeFromJson(vm.settings.themeImport);
  final dark = now?.dark ?? AshlarTheme.of(context).brightness == Brightness.dark;
  final base = themeFor(dark ? Brightness.dark : Brightness.light).colors;
  final start = <String, int>{
    for (final (k, _) in _themeColors) k: now?.colors[k] ?? _colorOf(base, k).toARGB32(),
  };
  final edited = await showAshlarDialog<ImportedTheme>(
    context: context,
    builder: (context) => _EditTheme(name: now?.name ?? 'Mine', dark: dark, colors: start),
  );
  if (edited == null) return;
  await vm.update(
    vm.settings.copyWith(palette: .imported, themeImport: importedThemeToJson(edited)),
  );
}

Color _colorOf(AshlarColors c, String k) => switch (k) {
  'background' => c.background,
  'foreground' => c.foreground,
  'card' => c.card,
  'popover' => c.popover,
  'sidebar' => c.sidebar,
  'muted' => c.muted,
  'mutedForeground' => c.mutedForeground,
  'border' => c.border,
  'primary' => c.primary,
  'primaryForeground' => c.primaryForeground,
  'accent' => c.accent,
  'ring' => c.ring,
  _ => c.destructive,
};

class _EditTheme extends StatefulWidget {
  const _EditTheme({required this.name, required this.dark, required this.colors});
  final String name;
  final bool dark;
  final Map<String, int> colors;

  @override
  State<_EditTheme> createState() => _EditThemeState();
}

class _EditThemeState extends State<_EditTheme> {
  late final _name = TextEditingController(text: widget.name);
  late final Map<String, int> _colors = {...widget.colors};
  late bool _dark = widget.dark;
  late final _fields = {
    for (final (k, _) in _themeColors) k: TextEditingController(text: _hex(_colors[k]!)),
  };

  static String _hex(int argb) {
    final rgb = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
    final a = (argb >> 24) & 0xff;
    return '#$rgb${a == 0xff ? '' : a.toRadixString(16).padLeft(2, '0')}';
  }

  static int? _parse(String text) {
    final h = text.trim().replaceFirst('#', '');
    if (!RegExp(r'^([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(h)) return null;
    final v = int.parse(h, radix: 16);
    return h.length == 6 ? 0xFF000000 | v : ((v & 0xff) << 24) | (v >> 8);
  }

  @override
  void dispose() {
    _name.dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context)},
      child: HelmyDialog(
        title: 'Theme colors',
        body: 'Each as a hex value, #RRGGBB, with an alpha after it if wanted.',
        icon: AshlarIconsRoundedStroke.palette,
        maxWidth: 520,
        content: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          spacing: 8,
          children: [
            Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Input(controller: _name, size: .sm, semanticLabel: 'Theme name'),
                ),
                _Choice<bool>(
                  value: _dark,
                  label: 'For',
                  options: const {true: 'Dark', false: 'Light'},
                  onChanged: (v) => setState(() => _dark = v),
                ),
              ],
            ),
            ConstrainedBox(
              // As tall as half the window allows: a fixed box was cramped on a big screen.
              constraints: BoxConstraints(
                maxHeight: (MediaQuery.sizeOf(context).height * .5).clamp(240.0, 480.0),
              ),
              child: ScrollArea(
                child: Column(
                  spacing: 6,
                  children: [
                    for (final (k, what) in _themeColors)
                      Row(
                        spacing: 10,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Color(_colors[k]!),
                              borderRadius: .circular(5),
                              border: Border.all(color: t.colors.border),
                            ),
                          ),
                          Expanded(child: Text(what, style: t.text.sm)),
                          SizedBox(
                            width: 120,
                            child: Input(
                              controller: _fields[k],
                              size: .sm,
                              semanticLabel: '$what color',
                              onChanged: (v) {
                                final c = _parse(v);
                                if (c != null) setState(() => _colors[k] = c);
                              },
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            Text(
              'Saved, it is used for ${_dark ? 'dark' : 'light'}; Helmy\'s own for the other.',
              style: muted,
            ),
          ],
        ),
        actions: [
          DialogButton('Cancel', onPressed: () => Navigator.pop(context)),
          DialogButton(
            'Save',
            main: true,
            onPressed: () => Navigator.pop(context, (
              name: _name.text.trim().isEmpty ? 'Mine' : _name.text.trim(),
              dark: _dark,
              colors: _colors,
            )),
          ),
        ],
      ),
    );
  }
}
