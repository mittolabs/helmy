part of '../chat_items.dart';

/// Copy, and Retry on the latest answer, at the end of each answer: shown
/// while the answer is under the mouse, or one of them has the keyboard, and
/// kept in the layout while hidden so nothing below moves.
class _AnswerActions extends StatefulWidget {
  const new(this.ask, this.latest, this.vm, {this.sentAt, this.endedAt});

  /// When the message went and when the answer finished: how long it took.
  final DateTime? sentAt, endedAt;

  /// The index of the message this answers.
  final int ask;
  final bool latest;
  final ChatViewModel vm;

  @override
  State<_AnswerActions> createState() => _AnswerActionsState();
}

class _AnswerActionsState extends State<_AnswerActions> {
  bool _focused = false;

  int get ask => widget.ask;
  bool get latest => widget.latest;
  ChatViewModel get vm => widget.vm;
  DateTime? get sentAt => widget.sentAt;
  DateTime? get endedAt => widget.endedAt;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _hoveredAnswer,
    builder: (context, hovered, row) => AnimatedOpacity(
      opacity: hovered == ask || _focused ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      // Still there for a screen reader and the keyboard.
      alwaysIncludeSemantics: true,
      child: row,
    ),
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (on) => setState(() => _focused = on),
      child: _row(context),
    ),
  );

  Widget _row(BuildContext context) => Row(
    children: [
      _IconAction(
        icon: AshlarIconsRoundedStroke.copy,
        label: 'Copy answer',
        onPressed: () => copyWithToast(context, vm, vm.answerAfter(ask)),
      ),
      if (latest)
        _IconAction(
          icon: AshlarIconsRoundedStroke.refreshCw,
          label: 'Retry',
          onPressed: vm.busy ? null : vm.retry,
        ),
      if ((sentAt, endedAt) case (final from?, final to?) when !to.isBefore(from))
        Padding(
          padding: const .only(left: 8),
          child: Tooltip(
            message: 'Sent ${fullTime(from)}\nAnswered ${fullTime(to)}',
            child: Text(
              'Took ${tookLabel(to.difference(from))}',
              style: AshlarTheme.of(context).text.xs
                  .copyWith(color: AshlarTheme.of(context).colors.mutedForeground),
            ),
          ),
        ),
    ],
  );
}

/// "4s", "1m 5s", "1h 2m": how long, as a person says it.
String tookLabel(Duration d) {
  final s = d.inSeconds;
  if (s < 1) return 'under a second';
  if (s < 60) return '${s}s';
  if (d.inHours < 1) return '${d.inMinutes}m${s % 60 == 0 ? '' : ' ${s % 60}s'}';
  return '${d.inHours}h${d.inMinutes % 60 == 0 ? '' : ' ${d.inMinutes % 60}m'}';
}

/// "10:42 PM" today, "Oct 12" this year, "Oct 12, 2025" before.
String shortWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  if (t.year == n.year && t.month == n.month && t.day == n.day) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
  return t.year == n.year
      ? '${months[t.month - 1]} ${t.day}'
      : '${months[t.month - 1]} ${t.day}, ${t.year}';
}

/// "Tue, Nov 3, 2026 at 10:42:05 PM".
String fullTime(DateTime t) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${days[t.weekday - 1]}, ${months[t.month - 1]} ${t.day}, ${t.year} at '
      '$h:${two(t.minute)}:${two(t.second)} ${t.hour < 12 ? 'AM' : 'PM'}';
}

class _IconAction extends StatelessWidget {
  const new({required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Button(
      variant: .ghost,
      size: .iconSm,
      semanticLabel: label,
      onPressed: onPressed,
      child: AshlarIcon(icon, size: 14),
    ),
  );
}

class _Notice extends StatelessWidget {
  const new(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Text(text, style: t.text.sm.copyWith(color: t.colors.mutedForeground));
  }
}
