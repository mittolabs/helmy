part of '../chat_items.dart';

/// A picture the agent made, from the file it saved: click it to see it whole,
/// and copy, save, open or find it.
class _Image extends StatelessWidget {
  const new(this.image, this.vm);
  final ImageItem image;
  final ChatViewModel vm;

  Future<void> _copy(BuildContext context) async {
    final ok = await vm.copyImage(image.path);
    if (context.mounted) {
      showToast(
        context,
        title: ok ? 'Image copied' : 'Could not copy the image',
        type: ok ? .normal : .error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _save(BuildContext context) async {
    final name = image.path.split('/').last;
    final where = await getSaveLocation(suggestedName: name, confirmButtonText: 'Save');
    if (where == null) return;
    try {
      await File(image.path).copy(where.path);
      if (context.mounted) showSavedToast(context, where.path, files: vm);
    } on FileSystemException catch (e) {
      if (context.mounted) {
        showToast(context, title: 'Could not save', description: e.message, type: .error);
      }
    }
  }

  void _view(BuildContext context) => showAshlarDialog<void>(
    context: context,
    builder: (context) => GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Padding(
        padding: const .all(40),
        child: Center(
          child: Image.file(
            File(image.path),
            fit: BoxFit.contain,
            semanticLabel: image.prompt ?? 'Generated image',
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final file = File(image.path);
    if (!file.existsSync()) {
      return Container(
        padding: const .all(16),
        decoration: BoxDecoration(color: t.colors.muted, borderRadius: .circular(t.radiusLg)),
        child: Text('The image is no longer at ${tildePath(image.path)}', style: muted),
      );
    }
    final desktop = vm;
    return Column(
      crossAxisAlignment: .start,
      spacing: 4,
      children: [
        Pressable(
          onPressed: () => _view(context),
          semanticLabel: 'View ${image.prompt ?? 'the image'} full size',
          builder: (context, state) => ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 420),
            child: ClipRRect(
              borderRadius: .circular(t.radiusLg),
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        ),
        Row(
          mainAxisSize: .min,
          children: [
            _IconAction(
              icon: AshlarIconsRoundedStroke.wandSparkles,
              label: 'Refine: describe a change to this image',
              onPressed: vm.busy ? null : () => vm.refine(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.shuffle,
              label: 'Variation: another take on this image',
              onPressed: vm.busy ? null : () => vm.variation(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.copy,
              label: 'Copy image',
              onPressed: () => _copy(context),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.download,
              label: 'Save as...',
              onPressed: () => _save(context),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.externalLink,
              label: 'Open',
              onPressed: () => desktop.open(image.path),
            ),
            _IconAction(
              icon: AshlarIconsRoundedStroke.folderOpen,
              label: 'Show in ${Desktop.current.fileManager}: ${tildePath(image.path)}',
              onPressed: () => desktop.reveal(image.path),
            ),
          ],
        ),
      ],
    );
  }
}
