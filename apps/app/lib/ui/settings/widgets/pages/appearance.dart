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
          description: imported != null && s.palette == .imported
              ? '${imported.name}, from VS Code, when ${imported.dark ? 'dark' : 'light'}; '
                    "Helmy's own otherwise."
              : 'For light and dark alike. Helmy\'s own is pure black when dark.',
          control: SizedBox(
            // Named, as greys this close tell apart only in use.
            width: 300,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in Palette.values)
                  if (p != .imported || imported != null)
                    _PaletteChip(
                      label: p == .imported ? imported!.name : p.label,
                      selected: s.palette == p,
                      onPressed: () => vm.update(s.copyWith(palette: p)),
                      colors: (b) =>
                          themeFor(b, palette: p, accent: s.accent, imported: imported).colors,
                    ),
              ],
            ),
          ),
        ),
        _Row(
          title: 'A theme from VS Code',
          description:
              'A color theme file (.json), as VS Code themes are made: its colors become '
              "Helmy's, for light or dark as the theme is.",
          control: Row(
            mainAxisSize: .min,
            spacing: 6,
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
            ],
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
              constraints: const BoxConstraints(maxHeight: 300),
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
