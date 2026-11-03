// Ashlar UI: Tool Call. Copied into your app by `ashlar add tool-call`; it is yours to change.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'badge.dart';
import 'button.dart';
import 'collapsible.dart';
import 'pressable.dart';
import 'shimmer.dart';
import 'spinner.dart';
import 'theme.dart';

/// Where a tool call has got to.
enum ToolCallStatus {
  /// Asked for, not yet started.
  pending,

  /// Running now.
  running,

  /// Waiting for the person to allow it or not.
  approval,

  /// Finished.
  done,

  /// Failed, or was not allowed.
  error,
}

/// What an assistant did, or asks to do, with one of your tools: its name and where it has
/// got to on one line, what it was given and what came back folded under it. When it needs
/// the person's say ([ToolCallStatus.approval]) it opens, says what it will do, and offers
/// [onApprove] and [onDeny].
///
/// ```dart
/// ToolCall(
///   title: 'Refund order 1042',
///   name: 'refund_order',
///   status: ToolCallStatus.approval,
///   input: '{"order": 1042, "amount": 2500}',
///   onApprove: () => run(call),
///   onDeny: () => refuse(call),
/// )
/// ```
class ToolCall extends StatefulWidget {
  const ToolCall({
    super.key,
    required this.name,
    this.title,
    this.status = ToolCallStatus.done,
    this.input,
    this.output,
    this.error,
    this.approval,
    this.onApprove,
    this.onDeny,
    this.icon = AshlarIconsRoundedStroke.wrench,
    this.initiallyOpen = false,
  });

  /// The tool's own name, as the model called it: `refund_order`.
  final String name;

  /// What it does, in words a person reads: "Refund order 1042". The name shows alone
  /// without it.
  final String? title;
  final ToolCallStatus status;

  /// What it was given and what came back, as text (JSON, say), drawn as code.
  final String? input, output;

  /// What went wrong, when it failed.
  final String? error;

  /// What the person is asked to allow, in place of "Allow this to run?".
  final String? approval;
  final VoidCallback? onApprove, onDeny;
  final IconData icon;

  /// Starts with what it was given and what came back showing. It always starts open
  /// when it is waiting for the person.
  final bool initiallyOpen;

  @override
  State<ToolCall> createState() => _ToolCallState();
}

class _ToolCallState extends State<ToolCall> {
  late bool _open =
      widget.initiallyOpen || widget.status == ToolCallStatus.approval;

  @override
  void didUpdateWidget(ToolCall old) {
    super.didUpdateWidget(old);
    if (widget.status == ToolCallStatus.approval &&
        old.status != ToolCallStatus.approval) {
      _open = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final title = widget.title ?? widget.name;
    final (
      String said,
      Widget? mark,
      BadgeVariant variant,
    ) = switch (widget.status) {
      ToolCallStatus.pending => ('Waiting', null, BadgeVariant.outline),
      ToolCallStatus.running => (
        'Running',
        Spinner(size: 12, color: c.mutedForeground, semanticLabel: ''),
        BadgeVariant.outline,
      ),
      ToolCallStatus.approval => (
        'Needs approval',
        const AshlarIcon(AshlarIconsRoundedStroke.shieldAlert, size: 12),
        BadgeVariant.secondary,
      ),
      ToolCallStatus.done => (
        'Done',
        const AshlarIcon(AshlarIconsRoundedStroke.check, size: 12),
        BadgeVariant.outline,
      ),
      ToolCallStatus.error => (
        'Failed',
        const AshlarIcon(AshlarIconsRoundedStroke.circleX, size: 12),
        BadgeVariant.destructive,
      ),
    };
    final hasBody =
        widget.input != null ||
        widget.output != null ||
        widget.error != null ||
        widget.status == ToolCallStatus.approval;
    final heading = Text(
      title,
      style: t.text.sm.copyWith(
        color: c.foreground,
        fontWeight: FontWeight.w500,
      ),
      overflow: TextOverflow.ellipsis,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(t.radiusLg),
        border: Border.all(color: c.border),
      ),
      child: Collapsible(
        open: _open,
        onChanged: (open) => setState(() => _open = open),
        builder: (context, open, toggle) => Pressable(
          onPressed: hasBody ? toggle : null,
          expanded: hasBody ? open : null,
          semanticLabel: '$title, $said',
          builder: (context, state) => AnimatedContainer(
            duration: t.duration,
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: state.hovered && hasBody
                  ? c.accent.withValues(alpha: .5)
                  : c.accent.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(t.radiusLg),
              border: Border.all(
                color: state.focused ? c.ring : c.ring.withValues(alpha: 0),
              ),
            ),
            child: Row(
              children: [
                AshlarIcon(widget.icon, size: 16, color: c.mutedForeground),
                const SizedBox(width: 10),
                // The title first, the tool name after it in what room is left.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: widget.status == ToolCallStatus.running
                            ? Shimmer(child: heading)
                            : heading,
                      ),
                      if (widget.title != null)
                        Flexible(
                          flex: 2,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(start: 8),
                            child: Text(
                              widget.name,
                              style: _mono(t)
                                  .copyWith(color: c.mutedForeground),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ExcludeSemantics(
                  child: Badge(
                    variant: variant,
                    leading: mark,
                    child: Text(said),
                  ),
                ),
                if (hasBody) ...[
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: open ? 0 : -.25,
                    duration: t.duration,
                    child: AshlarIcon(
                      AshlarIconsRoundedStroke.chevronDown,
                      size: 16,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.input != null)
                _Part(label: 'Input', text: widget.input!),
              if (widget.output != null)
                _Part(label: 'Output', text: widget.output!),
              if (widget.error != null)
                _Part(label: 'Error', text: widget.error!, error: true),
              if (widget.status == ToolCallStatus.approval) ...[
                const SizedBox(height: 12),
                Text(
                  widget.approval ?? 'Allow this to run?',
                  style: t.text.sm.copyWith(color: c.foreground),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Button(
                      variant: ButtonVariant.outline,
                      size: ButtonSize.sm,
                      onPressed: widget.onDeny,
                      child: const Text('Deny'),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      size: ButtonSize.sm,
                      onPressed: widget.onApprove,
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _mono(AshlarThemeData t) => t.text.xs.copyWith(
  fontFamily: 'monospace',
  fontFamilyFallback: const ['Menlo', 'Consolas', 'Roboto Mono', 'monospace'],
);

/// What a call was given, or what came back: a label, the text as code, and a copy button.
class _Part extends StatelessWidget {
  const _Part({required this.label, required this.text, this.error = false});

  final String label, text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: t.text.xs.copyWith(
                    color: c.mutedForeground,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Pressable(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                semanticLabel: 'Copy the ${label.toLowerCase()}',
                builder: (context, state) => Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: state.hovered
                        ? c.accent
                        : c.accent.withValues(alpha: 0),
                    borderRadius: BorderRadius.circular(t.radiusSm),
                    border: Border.all(
                      color: state.focused
                          ? c.ring
                          : c.ring.withValues(alpha: 0),
                    ),
                  ),
                  child: AshlarIcon(
                    AshlarIconsRoundedStroke.copy,
                    size: 13,
                    color: c.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: error
                  ? c.destructive.withValues(alpha: .08)
                  : c.muted.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(t.radiusMd),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Text(
                text,
                style: _mono(t).copyWith(
                  color: error ? c.destructive : c.foreground,
                  height: 1.5,
                ),
                textDirection: TextDirection.ltr,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
