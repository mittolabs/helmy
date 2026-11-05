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
