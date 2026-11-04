import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:file_selector/file_selector.dart';

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/engine.dart';
import '../../../domain/models/memory.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/app_theme.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/textarea.dart';
import '../../../data/services/chat_export.dart';
import '../../chat/widgets/saved_toast.dart';
import '../../core/helmy_dialog.dart';
import '../../core/markdown_preview.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/settings_view_model.dart';
import '../../core/window_layout.dart';
import '../../../utils/platform.dart';
import '../../../data/services/error_reports.dart';

part 'pages/connections.dart';
part 'pages/data.dart';
part 'pages/general.dart';
part 'pages/keyboard.dart';
part 'pages/memory.dart';
part 'pages/projects.dart';
part 'pages/tools.dart';

class SettingsScreen extends StatelessWidget {
  const new({super.key, required this.viewModel});
  final SettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return ColoredBox(
      color: t.colors.background,
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) => Column(
          crossAxisAlignment: .stretch,
          children: [
            TitleBar(
              child: Padding(
                // Below the window's buttons, so in line with the page either way.
                padding: const .fromLTRB(32, 40, 32, 16),
                child: Text('Settings', style: t.text.xl.copyWith(fontWeight: .w600)),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final page = switch (viewModel.section) {
                    .general => _General(vm: viewModel),
                    .projects => _Projects(vm: viewModel),
                    .agents => _Agents(vm: viewModel),
                    .tools => _Tools(vm: viewModel),
                    .memory => _Memory(vm: viewModel),
                    .data => _Data(vm: viewModel),
                    .keyboard => const _Keyboard(),
                  };
                  // Narrow: the sections as a row of tabs above the page.
                  if (box.maxWidth < _Nav.besideFrom) {
                    return Column(
                      crossAxisAlignment: .stretch,
                      children: [
                        _Nav(vm: viewModel, across: true),
                        // In line with the tabs.
                        Expanded(
                          child: Padding(padding: const .only(left: 16), child: page),
                        ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: .start,
                    children: [
                      _Nav(vm: viewModel),
                      Expanded(child: page),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The sections: a list beside the page, or a row of tabs above it when
/// [across] (a narrow window).
class _Nav extends StatelessWidget {
  const new({required this.vm, this.across = false});
  final SettingsViewModel vm;
  final bool across;

  /// Below this width the list moves above the page.
  static const besideFrom = 640.0;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    Widget item(SettingsSection s, IconData icon, String label) => Pressable(
      onPressed: () => vm.show(s),
      selected: vm.section == s,
      semanticLabel: label,
      builder: (context, state) => Container(
        padding: const .symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: vm.section == s
              ? t.colors.accent
              : state.hovered
              ? t.colors.accent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Row(
          spacing: 10,
          mainAxisSize: across ? .min : .max,
          children: [
            AshlarIcon(icon, size: 16, color: t.colors.foreground),
            if (across)
              Text(label, style: t.text.sm)
            else
              Flexible(
                child: Text(label, style: t.text.sm, maxLines: 1, overflow: .ellipsis),
              ),
          ],
        ),
      ),
    );
    final items = [
      item(.general, AshlarIconsRoundedStroke.settings, 'General'),
      item(.projects, AshlarIconsRoundedStroke.gitBranch, 'Projects'),
      item(.agents, AshlarIconsRoundedStroke.bot, 'Connections and usage'),
      item(.tools, AshlarIconsRoundedStroke.wrench, 'Skills and tools'),
      item(.memory, AshlarIconsRoundedStroke.brain, 'Memory'),
      item(.data, AshlarIconsRoundedStroke.database, 'Data and storage'),
      item(.keyboard, AshlarIconsRoundedStroke.keyboard, 'Keyboard'),
    ];
    if (across) {
      return Padding(
        padding: const .only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: .horizontal,
          padding: const .symmetric(horizontal: 24),
          child: Row(spacing: 4, children: items),
        ),
      );
    }
    return SizedBox(
      width: 248,
      child: Padding(
        padding: const .fromLTRB(24, 0, 16, 0),
        child: Column(spacing: 2, crossAxisAlignment: .stretch, children: items),
      ),
    );
  }
}

/// A setting: what it is and what it does on the left, its control on the right.
class _Row extends StatelessWidget {
  const new({required this.title, this.description, required this.control});
  final String title;
  final String? description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, box) {
          final words = Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
              if (description != null)
                Text(description!, style: t.text.sm.copyWith(color: t.colors.mutedForeground)),
            ],
          );
          // Narrow: the control under the words, rather than squeezing them.
          if (box.maxWidth < 440) {
            return Column(crossAxisAlignment: .start, spacing: 10, children: [words, control]);
          }
          return Row(
            spacing: 24,
            children: [
              Expanded(child: words),
              control,
            ],
          );
        },
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const new({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    // Settings next to each other share one card, a hairline between each.
    final out = <Widget>[];
    final run = <Widget>[];
    void card() {
      if (run.isEmpty) return;
      out.add(
        Container(
          decoration: BoxDecoration(
            color: t.colors.card,
            border: Border.all(color: t.colors.border),
            borderRadius: .circular(t.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              for (final (i, row) in run.indexed) ...[
                if (i > 0) Container(height: 1, color: t.colors.border),
                row,
              ],
            ],
          ),
        ),
      );
      run.clear();
    }

    for (final c in children) {
      if (c is _Row) {
        run.add(c);
      } else {
        card();
        out.add(c);
      }
    }
    card();
    return ScrollArea(
      child: Padding(
        padding: const .fromLTRB(8, 0, 32, 32),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(crossAxisAlignment: .stretch, children: out),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const new(this.text, {this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .only(top: first ? 0 : 28, bottom: 10),
      child: Text(text, style: t.text.base.copyWith(fontWeight: .w600)),
    );
  }
}

/// A short list of choices as a select.
class _Choice<T> extends StatelessWidget {
  const new({
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
  });
  final T value;
  final String label;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Select<T>(
      value: value,
      semanticLabel: label,
      options: [for (final e in options.entries) SelectOption(e.key, e.value)],
      onChanged: onChanged,
    ),
  );
}
