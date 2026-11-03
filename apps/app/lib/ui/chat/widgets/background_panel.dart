import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/widgets.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/chat_view_model.dart';
import 'chat_items.dart';

/// Beside the conversation: the work agents left running in the background,
/// each with how it stands, what it printed, and Stop while it runs.
class BackgroundPanel extends StatelessWidget {
  const new({super.key, required this.vm});
  final ChatViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final steps = vm.backgroundSteps;
    return ColoredBox(
      color: c.background,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('In the background', style: t.text.sm.copyWith(fontWeight: .w600)),
                ),
                Tooltip(
                  message: 'Close',
                  child: Button(
                    variant: .ghost,
                    size: .iconSm,
                    semanticLabel: 'Close the background panel',
                    onPressed: () => vm.toggle(.background),
                    child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 14),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: steps.isEmpty
                ? Center(
                    child: Text(
                      'Nothing is running in the background.',
                      style: t.text.xs.copyWith(color: c.mutedForeground),
                    ),
                  )
                : ScrollArea(
                    child: Padding(
                      padding: const .fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: .stretch,
                        spacing: 18,
                        children: [
                          for (final s in steps)
                            Column(
                              crossAxisAlignment: .stretch,
                              spacing: 8,
                              children: [
                                Row(
                                  spacing: 8,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.summary.isEmpty ? s.name : s.summary,
                                        maxLines: 2,
                                        overflow: .ellipsis,
                                        style: t.text.sm,
                                      ),
                                    ),
                                    BackgroundBadge(s.background!),
                                  ],
                                ),
                                BackgroundOutput(task: s.background!, call: s, vm: vm),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
