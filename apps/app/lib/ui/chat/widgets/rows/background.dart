part of '../chat_items.dart';

/// How a step moved to the background stands, beside its title.
class BackgroundBadge extends StatelessWidget {
  const new(this.task, {super.key});
  final BackgroundTask task;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final label = switch (task.status) {
      .running => 'Running in the background',
      .completed => 'Finished in the background',
      .failed => 'Failed in the background',
      .stopped => 'Stopped',
      .unknown => 'Ran in the background, end not seen',
    };
    return Container(
      padding: const .symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusMd),
      ),
      child: Row(
        mainAxisSize: .min,
        spacing: 5,
        children: [
          if (task.status == .running) const Spinner(size: 9),
          Text(label, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
        ],
      ),
    );
  }
}

/// What a background step has printed so far, read from where the agent
/// writes it and read again while it runs; Stop while it does.
class BackgroundOutput extends StatefulWidget {
  const new({super.key, required this.task, required this.call, required this.vm});
  final BackgroundTask task;
  final ToolCall call;
  final ChatViewModel vm;

  /// Where the output is: as the agent last said, or as the step's result put it.
  String? get file =>
      task.outputFile ??
      RegExp(r'written to: (\S+\.output)').firstMatch(call.result ?? '')?.group(1);

  @override
  State<BackgroundOutput> createState() => BackgroundOutputState();
}

class BackgroundOutputState extends State<BackgroundOutput> {
  String? _text;
  Timer? _timer;

  static const _maxChars = 6000;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (widget.task.status == .running) _read();
    });
  }

  @override
  void didUpdateWidget(BackgroundOutput oldWidget) {
    super.didUpdateWidget(oldWidget);
    _read();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    final path = widget.file;
    if (path == null) return;
    try {
      final all = await File(path).readAsString();
      final text = all.length > _maxChars ? '...\n${all.substring(all.length - _maxChars)}' : all;
      if (mounted && text != _text) setState(() => _text = text);
    } on FileSystemException {
      // Not written yet, or cleared away since: nothing to show.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final task = widget.task;
    final text = _text?.trimRight() ?? '';
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        if (text.isNotEmpty)
          _Code(text, error: task.status == .failed)
        else
          Text(
            task.status == .running
                ? 'Nothing printed yet.'
                : widget.file == null
                ? 'Where its output went is not known.'
                : 'No output to show. It may have been cleared away.',
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
        if (task.status == .running)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Button(
              size: .sm,
              variant: .outline,
              onPressed: () => widget.vm.stopTask(task.id),
              child: const Text('Stop'),
            ),
          ),
      ],
    );
  }
}
