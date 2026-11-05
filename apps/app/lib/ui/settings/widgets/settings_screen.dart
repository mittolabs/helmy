import 'package:ashlar_icons/ashlar_icons.dart';

import '../../core/qr_view.dart';
import '../../core/tinted_icon.dart';
import '../../../data/services/remote/remote_host.dart';

import 'package:file_selector/file_selector.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/settings_repository.dart';
import '../../../data/services/connections_setup.dart';
import '../../../data/services/window_snapshots.dart';

import 'package:go_router/go_router.dart';

import '../../../domain/models/engine.dart';
import '../../../domain/models/memory.dart';
import '../../../data/services/chromium/chromium_service.dart';
import '../../../domain/models/settings.dart';
import '../../../utils/format.dart';
import '../../core/ashlar/app_theme.dart';
import '../../../routing/settings_route.dart';
import '../../core/ashlar/button.dart';
import '../../core/ashlar/input.dart';
import '../../core/ashlar/kbd.dart';
import '../../core/ashlar/pressable.dart';
import '../../core/ashlar/scroll_area.dart';
import '../../core/ashlar/select.dart';
import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/toast.dart';
import '../../import/history_import_view_model.dart';
import '../../import/import_list.dart';
import '../../core/ashlar/switch.dart';
import '../../core/ashlar/textarea.dart';
import '../../../data/services/chat_export.dart';
import '../../chat/widgets/saved_toast.dart';
import '../../core/helmy_dialog.dart';
import '../../core/markdown_preview.dart';
import '../../core/ashlar/theme.dart';
import '../../core/ashlar/tooltip.dart';
import '../view_models/settings_view_model.dart';
import '../../../utils/platform.dart';
import '../../../data/services/error_reports.dart';

part 'pages/appearance.dart';
part 'pages/connections.dart';
part 'pages/data.dart';
part 'pages/general.dart';
part 'pages/keyboard.dart';
part 'pages/memory.dart';
part 'pages/phone.dart';
part 'pages/preview.dart';
part 'pages/projects.dart';
part 'pages/tools.dart';

/// Settings, a sheet over the app: the sections down the side
/// in groups, with a search at the top, and the page beside them under a
/// breadcrumb. Esc clears the search, then closes it.
class SettingsScreen extends StatefulWidget {
  const new({super.key, required this.viewModel});
  final SettingsViewModel viewModel;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsViewModel get vm => widget.viewModel;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _escape() {
    if (vm.query.isNotEmpty) {
      _search.clear();
      vm.search('');
    } else {
      closeSettings(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final window = MediaQuery.sizeOf(context);
    // Room around the sheet, and none on a small window.
    final margin = window.width < 720 ? 8.0 : 40.0;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _escape,
        const SingleActivator(LogicalKeyboardKey.slash): _searchFocus.requestFocus,
        Desktop.current.shortcut(LogicalKeyboardKey.keyF): _searchFocus.requestFocus,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: .fromLTRB(margin, margin + (window.width < 720 ? 24 : 0), margin, margin),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 900),
              child: Container(
                decoration: BoxDecoration(
                  color: c.background,
                  border: Border.all(color: c.border),
                  borderRadius: .circular(16),
                  boxShadow: t.shadowLg,
                ),
                clipBehavior: .antiAlias,
                child: ListenableBuilder(
                  listenable: vm,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, box) {
                      final across = box.maxWidth < _Nav.besideFrom;
                      final page = vm.query.trim().isNotEmpty
                          ? _Results(vm: vm)
                          : switch (vm.section) {
                              .general => _General(vm: vm),
                              .appearance => _Appearance(vm: vm),
                              .preview => _Preview(vm: vm),
                              .projects => _Projects(vm: vm),
                              .agents => _Agents(vm: vm),
                              .tools => _Tools(vm: vm),
                              .memory => _Memory(vm: vm),
                              .data => _Data(vm: vm),
                              .keyboard => const _Keyboard(),
                              .phone => _Phone(vm: vm),
                            };
                      final search = _SearchBox(
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: vm.search,
                      );
                      final content = Column(
                        crossAxisAlignment: .stretch,
                        children: [
                          _Crumb(vm: vm, onClose: () => closeSettings(context)),
                          if (across) ...[
                            Padding(padding: const .fromLTRB(16, 12, 16, 8), child: search),
                            _Nav(vm: vm, across: true),
                          ],
                          Expanded(
                            child: Padding(
                              padding: .only(left: across ? 16 : 32, top: across ? 0 : 24),
                              child: page,
                            ),
                          ),
                        ],
                      );
                      if (across) return content;
                      return Row(
                        crossAxisAlignment: .stretch,
                        children: [
                          Container(
                            width: 264,
                            decoration: BoxDecoration(
                              color: c.card,
                              border: Border(right: BorderSide(color: c.border)),
                            ),
                            child: Column(
                              crossAxisAlignment: .stretch,
                              children: [
                                Padding(padding: const .fromLTRB(12, 12, 12, 8), child: search),
                                Expanded(
                                  child: ScrollArea(child: _Nav(vm: vm)),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: content),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const new({required this.controller, required this.focusNode, required this.onChanged});
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Input(
    controller: controller,
    focusNode: focusNode,
    placeholder: 'Search',
    semanticLabel: 'Search settings',
    leading: const AshlarIcon(AshlarIconsRoundedStroke.search, size: 14),
    trailing: const Kbd(child: Text('/')),
    onChanged: onChanged,
  );
}

/// "Settings / General", and the way out.
class _Crumb extends StatelessWidget {
  const new({required this.vm, required this.onClose});
  final SettingsViewModel vm;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    return Container(
      height: 52,
      padding: const .only(left: 24, right: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colors.border)),
      ),
      child: Row(
        spacing: 10,
        children: [
          Text('Settings', style: muted),
          Text('/', style: muted),
          Expanded(
            child: Text(
              vm.query.trim().isNotEmpty ? 'Search' : _sections[vm.section]!.label,
              maxLines: 1,
              overflow: .ellipsis,
              style: t.text.sm.copyWith(fontWeight: .w500),
            ),
          ),
          _RestoreDefaults(vm: vm),
          Tooltip(
            message: 'Close (Esc)',
            child: Button(
              variant: .ghost,
              size: .iconSm,
              semanticLabel: 'Close settings',
              onPressed: onClose,
              child: const AshlarIcon(AshlarIconsRoundedStroke.x, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

/// Each section's name, icon, and the group it sits in (null: the first,
/// unlabelled one).
const _sections = <SettingsSection, ({String label, IconData icon, double hue, String? group})>{
  .general: (label: 'General', icon: AshlarIconsRoundedDuotone.settings, hue: 210.0, group: null),
  .appearance: (
    label: 'Appearance',
    icon: AshlarIconsRoundedDuotone.palette,
    hue: 330.0,
    group: null,
  ),
  .preview: (
    label: 'Preview panel',
    icon: AshlarIconsRoundedDuotone.appWindow,
    hue: 190.0,
    group: null,
  ),
  .keyboard: (label: 'Keyboard', icon: AshlarIconsRoundedDuotone.keyboard, hue: 250.0, group: null),
  .agents: (
    label: 'Connections and usage',
    icon: AshlarIconsRoundedDuotone.bot,
    hue: 280.0,
    group: 'Assistant',
  ),
  .tools: (
    label: 'Skills and tools',
    icon: AshlarIconsRoundedDuotone.wrench,
    hue: 25.0,
    group: 'Assistant',
  ),
  .memory: (label: 'Memory', icon: AshlarIconsRoundedDuotone.brain, hue: 100.0, group: 'Assistant'),
  .projects: (
    label: 'Projects',
    icon: AshlarIconsRoundedDuotone.gitBranch,
    hue: 160.0,
    group: 'Your work',
  ),
  .phone: (
    label: 'Phone',
    icon: AshlarIconsRoundedDuotone.smartphone,
    hue: 140.0,
    group: 'Your work',
  ),
  .data: (
    label: 'Data and storage',
    icon: AshlarIconsRoundedDuotone.database,
    hue: 45.0,
    group: 'Your work',
  ),
};

/// The sections, in their groups: a list beside the page, or a row of tabs
/// above it when [across] (a narrow window).
class _Nav extends StatelessWidget {
  const new({required this.vm, this.across = false});
  final SettingsViewModel vm;
  final bool across;

  /// Below this width the list moves above the page.
  static const besideFrom = 640.0;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final searching = vm.query.trim().isNotEmpty;
    Widget item(SettingsSection s) {
      final (:label, :icon, :hue, group: _) = _sections[s]!;
      final on = !searching && vm.section == s;
      return Pressable(
        onPressed: () => vm.show(s),
        selected: on,
        semanticLabel: label,
        builder: (context, state) => Container(
          padding: const .symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: on
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
              // Found by sight, as in the system's own settings.
              TintedIcon(icon, hue: hue, size: 20),
              if (across)
                Text(label, style: t.text.sm)
              else
                Flexible(
                  child: Text(
                    label,
                    style: t.text.sm.copyWith(
                      color: on ? t.colors.foreground : t.colors.foreground.withValues(alpha: .85),
                    ),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (across) {
      return Padding(
        padding: const .only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: .horizontal,
          padding: const .symmetric(horizontal: 16),
          child: Row(spacing: 4, children: [for (final s in _sections.keys) item(s)]),
        ),
      );
    }
    final out = <Widget>[];
    String? group;
    for (final s in _sections.keys) {
      final g = _sections[s]!.group;
      if (g != group) {
        group = g;
        out.add(
          Padding(
            padding: const .fromLTRB(10, 16, 10, 4),
            child: Text(g!, style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
          ),
        );
      }
      out.add(item(s));
    }
    return Padding(
      padding: const .fromLTRB(12, 0, 12, 12),
      child: Column(spacing: 2, crossAxisAlignment: .stretch, children: out),
    );
  }
}

/// Every setting that matches the search, under its section; and the
/// sections whose name matches, to open.
class _Results extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final q = vm.query.trim().toLowerCase();
    bool matches(String s) => s.toLowerCase().contains(q);
    final out = <Widget>[];
    // Pages that are a plain list of settings give their rows; the others
    // (lists of files, of projects) are found by their name.
    final pages = <SettingsSection, Widget>{
      .general: _General(vm: vm),
      .appearance: _Appearance(vm: vm),
      .agents: _Agents(vm: vm),
      .keyboard: const _Keyboard(),
    };
    for (final s in _sections.keys) {
      final label = _sections[s]!.label;
      final page = pages[s];
      final built = page is StatelessWidget ? page.build(context) : null;
      final rows = built is _Page
          ? [
              for (final r in built.children.whereType<_Row>())
                if (matches('${r.title} ${r.description ?? ''}')) r,
            ]
          : const <_Row>[];
      if (rows.isEmpty && !matches(label)) continue;
      out.add(
        Padding(
          padding: .only(top: out.isEmpty ? 0 : 28, bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: t.text.base.copyWith(fontWeight: .w600)),
              ),
              Button(
                variant: .ghost,
                size: .sm,
                onPressed: () => vm.show(s),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      out.addAll(rows);
    }
    if (out.isEmpty) {
      return _Page(
        children: [
          Text(
            'No setting matches "${vm.query.trim()}".',
            style: t.text.sm.copyWith(color: t.colors.mutedForeground),
          ),
        ],
      );
    }
    return _Page(children: out);
  }
}

/// A setting: what it is and what it does on the left, its control on the right.
/// A setting, shown in a card with the settings next to it. A row that is
/// more than [_Row] (one that checks what macOS allows, say) says so too, or
/// it breaks its group's card in two.
mixin _Setting on Widget {}

/// A part of a card that is not a setting to change: a list, say. Spaced
/// as a [_Row] is, under a [title].
class _Block extends StatelessWidget with _Setting {
  const new({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: const .symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 8,
        children: [
          Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
          child,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget with _Setting {
  const new({required this.title, this.description, required this.control});
  final String title;
  final String? description;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final settings = context.watch<SettingsRepository>();
    // Changed from Helmy's own: a quiet way back beside its name.
    final changed = changedSettings(settings.settings).contains(title);
    return Padding(
      padding: const .symmetric(horizontal: 18, vertical: 14),
      child: LayoutBuilder(
        builder: (context, box) {
          final words = Column(
            crossAxisAlignment: .start,
            spacing: 2,
            children: [
              Row(
                spacing: 4,
                children: [
                  Flexible(
                    child: Text(title, style: t.text.sm.copyWith(fontWeight: .w500)),
                  ),
                  if (changed)
                    Tooltip(
                      message: 'Back to how Helmy has it',
                      child: Button(
                        variant: .ghost,
                        size: .iconXs,
                        semanticLabel: 'Put $title back to how Helmy has it',
                        onPressed: () => settings.save(withDefaults(settings.settings, [title])),
                        child: AshlarIcon(
                          AshlarIconsRoundedStroke.undo2,
                          size: 12,
                          color: t.colors.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
              if (description != null)
                Text(
                  description!,
                  style: t.text.xs.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    color: t.colors.mutedForeground,
                  ),
                ),
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
      if (c is _Setting) {
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
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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

/// Every setting chosen put back to how Helmy has it, after saying which:
/// connections, projects, rules and the window's layout stay. Pressable
/// only when something has been changed.
class _RestoreDefaults extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final changed = changedSettings(vm.settings);
    // Narrow: the icon alone, its words in the tooltip.
    final compact = MediaQuery.sizeOf(context).width < 640;
    return Tooltip(
      message: changed.isEmpty
          ? 'Everything is as Helmy has it'
          : 'Put what you changed back to how Helmy has it',
      child: Button(
        variant: .ghost,
        size: compact ? .iconSm : .xs,
        semanticLabel: 'Restore defaults',
        onPressed: changed.isEmpty
            ? null
            : () async {
                final sure = await confirm(
                  context,
                  title: 'Restore the defaults?',
                  body:
                      'This puts back: ${changed.join(', ')}. Connections, projects and '
                      'permission rules stay as they are.',
                  action: 'Restore',
                  icon: AshlarIconsRoundedStroke.rotateCcw,
                );
                if (sure) await vm.update(withDefaults(vm.settings));
              },
        leading: compact ? null : const AshlarIcon(AshlarIconsRoundedStroke.rotateCcw, size: 14),
        child: compact
            ? const AshlarIcon(AshlarIconsRoundedStroke.rotateCcw, size: 14)
            : const Text('Restore defaults'),
      ),
    );
  }
}
