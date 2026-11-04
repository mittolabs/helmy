import 'dart:async';

import '../../../domain/helmy_voice.dart';
import '../../../domain/folder_move.dart';

import 'dart:io';

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart' show kDoubleTapSlop, kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/chat_item.dart';
import '../../../utils/diffs.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/plan.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/engines/attachments.dart';
import '../../core/ashlar/dialog.dart';
import '../../core/ashlar/dropdown_menu.dart';
import '../../core/ashlar/attachment.dart';
import '../../core/ashlar/bubble.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/collapsible.dart';
import '../../core/ashlar/markdown.dart';
import '../../core/ashlar/message.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/questionnaire.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/toast.dart';
import '../../core/ashlar/tooltip.dart';
import '../../core/helmy_dialog.dart';
import '../../core/markdown_preview.dart';
import '../../../domain/models/permission_rule.dart';
import 'step_input.dart';
import '../../../utils/result.dart';
import '../view_models/chat_view_model.dart';
import 'problem_card.dart';
import 'saved_toast.dart';
import '../../../domain/problem.dart';
import '../../../utils/platform.dart';

part 'rows/answer.dart';
part 'rows/approvals.dart';
part 'rows/background.dart';
part 'rows/image.dart';
part 'rows/steps.dart';
part 'rows/tasks.dart';
part 'rows/user.dart';

typedef ChatRow = ({Object id, bool anchor, Widget child});

/// The conversation as rows. A tool's approval is drawn on the tool's own step,
/// so an approval with a step to go on gets no row of its own.
List<ChatRow> buildRows(ChatViewModel vm) {
  final items = vm.items;
  final promptsByTool = {
    for (final p in items.whereType<PermissionPrompt>())
      if (p.toolUseId != null && !p.isQuestion) p.toolUseId!: p,
  };
  final toolIds = {for (final c in items.whereType<ToolCall>()) c.id};
  final rows = <ChatRow>[];
  final lastAsk = vm.lastAsk;
  int? ask;
  // Steps in a row, held back so two or more fold into one line.
  final run = <(int, ToolCall, PermissionPrompt?)>[];
  void flush() {
    if (run.length == 1) {
      final (i, call, p) = run.single;
      rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
    } else if (run.length > 1) {
      rows.add((id: 'g${run.first.$1}', anchor: false, child: _StepGroup([...run], vm)));
    }
    run.clear();
  }

  for (final (i, item) in items.indexed) {
    final p = item is ToolCall ? promptsByTool[item.id] : null;
    final quiet =
        (item is ToolCall && p?.decision != PermissionDecision.pending) ||
        (item is AssistantText && item.text.isEmpty) ||
        (item is PermissionPrompt &&
            !item.isQuestion &&
            item.toolUseId != null &&
            toolIds.contains(item.toolUseId));
    if (!quiet) flush();
    switch (item) {
      case UserMessage(:final text, :final attachments):
        ask = i;
        rows.add((
          id: i,
          anchor: true,
          child: _User(
            text,
            i,
            vm,
            attachments: attachments,
            sentAt: item.sentAt,
            key: ObjectKey(item),
          ),
        ));
      case AssistantText(:final text):
        final streaming = vm.busy && i == items.length - 1;
        // A folder move is Helmy's to act on, not the user's to read.
        final shown = withoutFolderLines(text, streaming: streaming);
        if (shown.isEmpty) continue;
        rows.add((
          id: i,
          anchor: false,
          child: Builder(
            builder: (context) => Markdown(
              shown,
              streaming: streaming,
              onLink: (url) => openAnswerLink(context, url, vm),
            ),
          ),
        ));
      case ToolCall call when call.name == 'ExitPlanMode':
        rows.add((id: i, anchor: false, child: _PlanApproval(call, p, vm)));
      case ToolCall call:
        if (quiet) {
          run.add((i, call, p));
        } else {
          rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
        }
      case PermissionPrompt p when p.isQuestion:
        rows.add((id: i, anchor: false, child: _Question(p, vm)));
      case PermissionPrompt p:
        if (p.toolUseId != null && toolIds.contains(p.toolUseId)) continue;
        // An approval for something that has no step: draw one from the request.
        final call = ToolCall(id: p.requestId, name: p.toolName, input: p.input);
        rows.add((id: i, anchor: false, child: _Step(call, p, vm)));
      case ImageItem image:
        rows.add((id: i, anchor: false, child: _Image(image, vm)));
      case TaskList list:
        rows.add((id: i, anchor: false, child: _Tasks(list)));
      case TurnSummary s:
        if (!s.ok) {
          rows.add((
            id: i,
            anchor: false,
            child: ProblemCard(
              problem: diagnose(s.error, engineId: s.engineId),
              vm: vm,
              last: i == items.length - 1,
            ),
          ));
        }
        if (ask != null) {
          rows.add((
            id: 'a$i',
            anchor: false,
            child: _AnswerActions(
              ask,
              ask == lastAsk,
              vm,
              sentAt: (items[ask] as UserMessage).sentAt,
              endedAt: s.endedAt,
            ),
          ));
        }
      case Notice(:final text, :final fix?) when Fix.values.any((f) => f.link == fix):
        rows.add((
          id: i,
          anchor: false,
          child: ProblemCard(
            problem: Problem(
              text,
              Fix.values.firstWhere((f) => f.link == fix),
              details: (items[i] as Notice).details,
            ),
            vm: vm,
            last: i == items.length - 1,
          ),
        ));
      case Notice(:final text):
        rows.add((id: i, anchor: false, child: _Notice(text)));
    }
  }
  flush();
  return rows;
}

/// Puts [text] on the clipboard and says so.
Future<void> copyWithToast(BuildContext context, ChatViewModel vm, String text) async {
  await vm.copy(text);
  if (context.mounted) showToast(context, title: 'Copied', duration: const Duration(seconds: 2));
}
