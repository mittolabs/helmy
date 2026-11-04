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
    return Container(
      padding: const .symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colors.border)),
      ),
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
  Widget build(BuildContext context) => ScrollArea(
    child: Padding(
      padding: const .fromLTRB(8, 0, 32, 32),
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(crossAxisAlignment: .stretch, children: children),
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const new(this.text, {this.first = false});
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return Padding(
      padding: .only(top: first ? 0 : 28, bottom: 4),
      child: Text(text, style: t.text.base.copyWith(fontWeight: .w600)),
    );
  }
}

class _General extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Appearance', first: true),
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
        const _Heading('Notifications'),
        _Row(
          title: 'When a session needs you or finishes',
          description:
              'A notification when a session in the background finishes or waits for '
              'your approval, and a count on Helmy\'s icon.',
          control: Switch(
            value: s.notify,
            semanticLabel: 'Notifications',
            onChanged: (v) => vm.update(s.copyWith(notify: v)),
          ),
        ),
        const _Heading('Behavior'),
        _Row(
          title: 'Keep sessions running when the window closes',
          description:
              'Closing the window hides it and sessions keep working. Click Helmy in '
              '${Desktop.current.appBar} to bring it back; Quit (${Desktop.current.keys('⌘Q')}) ends them. Off, '
              'closing the window quits.',
          control: Switch(
            value: s.keepRunning,
            semanticLabel: 'Keep sessions running when the window closes',
            onChanged: (v) => vm.update(s.copyWith(keepRunning: v)),
          ),
        ),
        _Row(
          title: 'Send with',
          description: s.sendWithEnter
              ? 'Enter sends; Shift+Enter starts a new line.'
              : '${Desktop.current.keys('⌘Enter')} sends; Enter starts a new line, for writing long messages.',
          control: _Choice<bool>(
            value: s.sendWithEnter,
            label: 'Send with',
            options: {true: 'Enter', false: Desktop.current.keys('⌘Enter')},
            onChanged: (v) => vm.update(s.copyWith(sendWithEnter: v)),
          ),
        ),
        _Row(
          title: 'Each session on its own branch',
          description:
              'In a git repository, each session works on its own branch in its own copy, '
              'so several can work at once without changing each other\'s files. '
              'Projects can say otherwise.',
          control: Switch(
            value: s.ownCopies,
            semanticLabel: 'Each session on its own branch',
            onChanged: (v) => vm.update(s.copyWith(ownCopies: v)),
          ),
        ),
        _Row(
          title: 'Send error reports',
          description: ErrorReports.configured
              ? "When something in Helmy itself goes wrong, what went wrong in its code goes "
                    "to Mittolabs, to be fixed. Never a conversation, a file, or a path in your home."
              : 'This build sends no reports anywhere.',
          control: Switch(
            value: s.sendErrors,
            semanticLabel: 'Send error reports',
            onChanged: ErrorReports.configured ? (v) => vm.update(s.copyWith(sendErrors: v)) : null,
          ),
        ),
        _Row(
          title: 'Show steps open',
          description: 'Each step starts open, showing what went in and came out.',
          control: Switch(
            value: s.stepsOpen,
            semanticLabel: 'Show steps open',
            onChanged: (v) => vm.update(s.copyWith(stepsOpen: v)),
          ),
        ),
        _Row(
          title: 'Open at login',
          description: vm.openAtLogin == null
              ? 'This system cannot be asked.'
              : 'Helmy opens when you log in, so sessions are there to pick up.',
          control: vm.openAtLogin == null
              ? const SizedBox.shrink()
              : Switch(
                  value: vm.openAtLogin!,
                  semanticLabel: 'Open at login',
                  onChanged: vm.setOpenAtLogin,
                ),
        ),
        _Row(
          title: 'Ask before deleting a session',
          control: Switch(
            value: s.confirmDelete,
            semanticLabel: 'Ask before deleting a session',
            onChanged: (v) => vm.update(s.copyWith(confirmDelete: v)),
          ),
        ),
        const _Heading('New sessions'),
        _Row(
          title: 'Permissions',
          description: 'What the agent may do without asking, until you change it in a session.',
          control: SizedBox(
            width: 180,
            child: Select<PermissionLevel>(
              value: s.defaultLevel,
              semanticLabel: 'Default permissions',
              options: [for (final l in PermissionLevel.values) SelectOption(l, l.label)],
              onChanged: (l) => vm.update(s.copyWith(defaultLevel: l)),
            ),
          ),
        ),
        _Row(
          title: 'Start in',
          description: s.folderMode == .fixed
              ? (s.fixedFolder == null ? 'No folder chosen yet.' : tildePath(s.fixedFolder!))
              : 'Each new session opens in the folder you last worked in.',
          control: Row(
            spacing: 8,
            children: [
              if (s.folderMode == .fixed)
                Button(
                  variant: .outline,
                  size: .sm,
                  onPressed: () async {
                    final dir = await getDirectoryPath(
                      initialDirectory: s.fixedFolder,
                      confirmButtonText: 'Use this folder',
                    );
                    if (dir != null) await vm.update(s.copyWith(fixedFolder: dir));
                  },
                  child: const Text('Choose...'),
                ),
              SizedBox(
                width: 180,
                child: Select<FolderMode>(
                  value: s.folderMode,
                  semanticLabel: 'Where new sessions start',
                  options: const [
                    SelectOption(FolderMode.last, 'Last folder'),
                    SelectOption(FolderMode.fixed, 'The same folder'),
                  ],
                  onChanged: (m) => vm.update(s.copyWith(folderMode: m)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A theme as a small picture of the app in it: light, dark, or half of each
/// for following the system.
class _ThemeCard extends StatelessWidget {
  const new({required this.choice, required this.selected, required this.onPressed});
  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onPressed;

  static Widget _window(AshlarColors c) => Container(
    color: c.background,
    padding: const .all(6),
    child: Row(
      crossAxisAlignment: .stretch,
      spacing: 5,
      children: [
        Container(
          width: 18,
          decoration: BoxDecoration(color: c.muted, borderRadius: .circular(3)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              for (final w in const [.9, .6, .75])
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.mutedForeground.withValues(alpha: .5),
                      borderRadius: .circular(2),
                    ),
                  ),
                ),
              const Spacer(),
              Container(
                height: 9,
                decoration: BoxDecoration(
                  border: Border.all(color: c.border),
                  borderRadius: .circular(5),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final light = _window(appTheme.colors);
    final dark = _window(appDarkTheme.colors);
    final label = switch (choice) {
      .light => 'Light',
      .dark => 'Dark',
      .system => 'System',
    };
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      semanticLabel: '$label theme',
      builder: (context, state) => Column(
        spacing: 6,
        children: [
          // The ring sits a few points outside the picture, the way a
          // selection is drawn on the Mac, rather than as a frame on it.
          AnimatedContainer(
            duration: t.duration,
            padding: const .all(3),
            decoration: BoxDecoration(
              borderRadius: .circular(t.radiusLg + 4),
              border: Border.all(
                color: selected
                    ? t.colors.foreground.withValues(alpha: .9)
                    : state.hovered
                    ? t.colors.border
                    : const Color(0x00000000),
                width: 1.5,
              ),
            ),
            child: Container(
              width: 96,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: .circular(t.radiusLg),
                border: Border.all(color: t.colors.border.withValues(alpha: .7), width: .5),
              ),
              child: switch (choice) {
                .light => light,
                .dark => dark,
                .system => Row(
                  crossAxisAlignment: .stretch,
                  children: [
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(maxWidth: 96, alignment: .centerLeft, child: dark),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: OverflowBox(maxWidth: 96, alignment: .centerRight, child: light),
                      ),
                    ),
                  ],
                ),
              },
            ),
          ),
          Text(
            label,
            style: t.text.xs.copyWith(
              color: selected ? t.colors.foreground : t.colors.mutedForeground,
              fontWeight: selected ? .w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

String _size(int? bytes) {
  if (bytes == null) return 'Nothing yet';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class _Data extends StatefulWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_Data> createState() => _DataState();
}

class _DataState extends State<_Data> {
  SettingsViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    await vm.loadPlaces(dir.path);
  }

  Future<void> _export() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Export here');
    if (dir == null || !mounted) return;
    final n = await context.read<ChatExport>().exportAll(dir);
    if (mounted) {
      showSavedToast(context, dir, title: '$n conversation${n == 1 ? '' : 's'} exported');
    }
  }

  Future<void> _clear(String label, String path) async {
    final ok = await confirm(
      context,
      title: 'Clear ${label.toLowerCase()}?',
      body: '${tildePath(path)} is emptied. This cannot be undone.',
      action: 'Clear',
      destructive: true,
    );
    if (!ok) return;
    final dir = Directory(path);
    if (dir.existsSync()) {
      for (final e in dir.listSync()) {
        e.deleteSync(recursive: true);
      }
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return _Page(
      children: [
        const _Heading('Where things are', first: true),
        if (vm.places.isEmpty) const Padding(padding: .all(16), child: Spinner(size: 16)),
        for (final p in vm.places)
          _Row(
            title: '${p.label}  ·  ${_size(p.bytes)}',
            description: '${p.note}\n${tildePath(p.path)}',
            control: Row(
              spacing: 8,
              children: [
                if (p.label == 'Pasted pictures' && (p.bytes ?? 0) > 0)
                  Button(
                    size: .sm,
                    variant: .ghost,
                    onPressed: () => _clear(p.label, p.path),
                    child: const Text('Clear'),
                  ),
                if (p.bytes != null)
                  Button(
                    size: .sm,
                    variant: .outline,
                    onPressed: () => vm.reveal(p.path),
                    child: Text('Show in ${Desktop.current.fileManager}'),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const .only(top: 8),
          child: Text(
            "Deleting a session in Helmy does not delete the agent's own copy. Those stay in the "
            'folders above until you remove them there.',
            style: muted,
          ),
        ),
        const _Heading('Your conversations'),
        _Row(
          title: 'Export all conversations',
          description: 'Each session as a Markdown file, in a folder you choose.',
          control: Button(
            size: .sm,
            variant: .outline,
            onPressed: _export,
            child: const Text('Export...'),
          ),
        ),
        _Heading('What leaves ${Desktop.current.thisComputer}'),
        Text(
          'Each message goes to the company behind the agent that answers it (Anthropic for '
          'Claude Code, OpenAI for Codex), with the files and command output that agent reads to '
          'answer. With a model on Ollama, nothing leaves. Helmy itself sends nothing anywhere: '
          'its sessions, settings and logs stay in the folders above.',
          style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
        ),
      ],
    );
  }
}

class _Tools extends StatefulWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  State<_Tools> createState() => _ToolsState();
}

class _ToolsState extends State<_Tools> {
  @override
  void initState() {
    super.initState();
    // After this frame: with nothing to ask (no connection online), loading
    // finishes at once, and would tell the page while it is being built.
    if (!widget.vm.toolsLoaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.vm.loadTools());
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    return _Page(
      children: [
        Text(
          "What each agent can run when a message starts with /, and the MCP servers it "
          'reaches. A /command goes to an agent that has it. Add or change them in each '
          "agent's own settings; this page shows them as the agents report.",
          style: t.text.sm.copyWith(color: t.colors.mutedForeground, height: 1.5),
        ),
        for (final a in vm.agents.where((a) => !a.info.localOnly)) ...[
          _Heading(a.info.name),
          if (vm.tools[a.info.id] case final tools?) ...[
            Text('MCP servers', style: t.text.sm.copyWith(fontWeight: .w600)),
            const SizedBox(height: 6),
            if (tools.servers.isEmpty)
              Text('None', style: muted)
            else
              for (final s in tools.servers)
                Padding(
                  padding: const .symmetric(vertical: 3),
                  child: Row(
                    spacing: 8,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: .circle,
                          color: s.status == 'connected'
                              ? t.colors.foreground
                              : t.colors.mutedForeground.withValues(alpha: .4),
                        ),
                      ),
                      Expanded(child: Text(s.name, style: t.text.sm)),
                      Text(switch (s.status) {
                        'connected' => 'Connected',
                        'needs-auth' => 'Needs sign-in',
                        'pending' => 'Connecting',
                        'failed' => 'Failed',
                        final other => other,
                      }, style: muted),
                    ],
                  ),
                ),
            const SizedBox(height: 14),
            Text(
              'Skills and commands (${tools.commands.length})',
              style: t.text.sm.copyWith(fontWeight: .w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in tools.commands)
                  Tooltip(
                    message: c.description.isEmpty ? c.name : c.description,
                    child: Container(
                      padding: const .symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.colors.border),
                        borderRadius: .circular(t.radiusMd),
                      ),
                      child: Text(
                        '/${c.name}',
                        style: t.text.xs.copyWith(
                          fontFamily: 'monospace',
                          fontFamilyFallback: monoFonts,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ] else
            const Padding(padding: .all(8), child: Spinner(size: 14)),
        ],
      ],
    );
  }
}

class _Keyboard extends StatelessWidget {
  const new();

  static const _keys = [
    ('⌘N', 'New session'),
    ('⌘K', 'Search sessions and run actions'),
    ('⌘B', 'Show or hide the sidebar'),
    ('⌘,', 'Settings'),
    ('⌘1 to ⌘9', 'Open the sessions in the order the list shows them'),
    ('⌘[ / ⌘]', 'Back and forward through where you have been'),
    ('⌘F', 'Find in this session; Enter for the next, Shift+Enter the one before'),
    ('⌘Z', 'Undo archiving a session (outside a text box)'),
    ('Enter', 'Send (or ⌘Enter, as set in General)'),
    ('Shift+Enter', 'New line in a message'),
    ('⇧⌘Enter', 'While the agent works: send now, redirecting it'),
    ('/', 'Commands and skills, at the start of a message'),
    ('@', 'Pick a file from the session folder'),
    ('Tab', 'Take the first suggestion'),
    ('↑ / ↓', 'Your earlier messages, from an empty box'),
    ('⌘V', 'Paste a picture as an attachment, or text'),
    ('!', 'Run a command in the folder yourself, at the start of a message'),
    ('Esc', 'Close a dialog or the suggestions'),
    ('⌘Q', 'Quit, ending every session'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    return _Page(
      children: [
        const _Heading('Keyboard', first: true),
        for (final (key, what) in _keys)
          _Row(
            title: Desktop.current.keys(what),
            control: Container(
              padding: const .symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: t.colors.muted,
                borderRadius: .circular(t.radiusMd),
                border: Border.all(color: t.colors.border),
              ),
              child: Text(
                Desktop.current.keys(key),
                style: t.text.xs.copyWith(fontFamily: 'monospace', fontFamilyFallback: monoFonts),
              ),
            ),
          ),
      ],
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

class _Agents extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final s = vm.settings;
    return _Page(
      children: [
        const _Heading('Set up', first: true),
        _Row(
          title: 'Install and sign in',
          description: 'Each connection installed and signed in with one press, no terminal.',
          control: Button(
            variant: .outline,
            size: .sm,
            onPressed: () => context.go('/setup'),
            child: const Text('Open setup'),
          ),
        ),
        const _Heading('Routing'),
        _Row(
          title: 'Move to an agent with more room',
          description:
              'Each message goes to an agent that can do what it asks, then to the one with '
              'the most of its usage limit left. A session stays with its agent unless another '
              'has clearly more room, since each switch hands the conversation across.',
          control: SizedBox(
            width: 150,
            child: Select<Switching>(
              value: s.switching,
              semanticLabel: 'How readily to switch',
              options: [for (final w in Switching.values) SelectOption(w, w.label)],
              onChanged: (w) => vm.update(s.copyWith(switching: w)),
            ),
          ),
        ),
        const _Heading('Agents'),
        for (final a in vm.agents) _AgentCard(row: a, checked: vm.checked, vm: vm),
        const _Heading('Local model'),
        _Row(
          title: 'Ollama model',
          description: vm.localModels == null
              ? 'Ollama is not running on ${Desktop.current.thisComputer}. With it running and a model pulled, '
                    'sessions keep working with no internet, on that model.'
              : vm.localModels!.isEmpty
              ? 'Ollama is running but has no model. Pull one, for example: ollama pull gpt-oss:20b'
              : 'Used only when no online agent can answer: when offline, or out of room.',
          control: vm.localModels == null || vm.localModels!.isEmpty
              ? const SizedBox.shrink()
              : SizedBox(
                  width: 220,
                  child: Select<String>(
                    value: s.ollamaModel != null && vm.localModels!.contains(s.ollamaModel)
                        ? s.ollamaModel
                        : vm.localModels!.first,
                    semanticLabel: 'Ollama model',
                    options: [for (final m in vm.localModels!) SelectOption(m, m)],
                    onChanged: (m) => vm.update(s.copyWith(ollamaModel: m)),
                  ),
                ),
        ),
        const _Heading('Always allowed'),
        if (s.rules.isEmpty)
          const _Row(
            title: 'No rules yet',
            description:
                'Choose "Always allow" on an approval, and steps like it are allowed from then on.',
            control: SizedBox.shrink(),
          )
        else
          for (final r in s.rules)
            _Row(
              title: r.label,
              control: Button(
                size: .sm,
                variant: .ghost,
                onPressed: () => vm.update(s.copyWith(rules: [...s.rules]..remove(r))),
                child: const Text('Remove'),
              ),
            ),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const new({required this.row, required this.checked, required this.vm});
  final AgentRow row;
  final bool checked;
  final SettingsViewModel vm;

  static String _until(DateTime when, DateTime now) {
    final d = when.difference(now);
    if (d.inMinutes < 1) return 'in a moment';
    if (d.inHours < 1) return 'in ${d.inMinutes}m';
    if (d.inDays < 1) return 'in ${d.inHours}h ${d.inMinutes % 60}m';
    return 'in ${d.inDays}d ${d.inHours % 24}h';
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.sm.copyWith(color: t.colors.mutedForeground);
    final now = DateTime.now();
    final usage = row.usage;
    final status = !checked
        ? 'Checking...'
        : row.problem ??
              (row.downUntil != null
                  ? 'Resting after a failure, back ${_until(row.downUntil!, now)}'
                  : row.enabled
                  ? 'Ready'
                  : 'Turned off: no messages go to it');
    final can = [
      for (final c in row.info.capabilities)
        if (c != Capability.tools) c.label,
    ];
    final connections = vm.connectionsOf(row.info.id);
    return Container(
      margin: const .only(top: 12),
      padding: const .all(16),
      decoration: BoxDecoration(
        border: Border.all(color: t.colors.border),
        borderRadius: .circular(t.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(row.info.name, style: t.text.sm.copyWith(fontWeight: .w600)),
                    Text(status, style: muted),
                  ],
                ),
              ),
              Switch(
                value: row.enabled,
                semanticLabel: 'Use ${row.info.name}',
                onChanged: (on) => vm.setEnabled(row.info.id, on),
              ),
            ],
          ),
          if (row.info.localOnly)
            Text('No usage limit: it runs on ${Desktop.current.thisComputer}.', style: muted)
          else if (usage == null)
            Text('No usage reported yet. It reports with its first answer.', style: muted)
          else ...[
            for (final w
                in usage.windows.isEmpty
                    ? [UsageWindow(name: 'Limit', used: usage.used, resetsAt: usage.resetsAt)]
                    : usage.windows)
              _Window(window: w, now: now, until: _until),
            if (usage.reportedAt != null)
              Text(
                'As of ${ago(usage.reportedAt!, now: now)} ago'.replaceAll(
                  'As of now ago',
                  'As of just now',
                ),
                style: muted,
              ),
          ],
          if (can.isNotEmpty) Text('Also can: ${can.join(', ')}', style: muted),
          if (!row.info.localOnly)
            Text(
              connections == null
                  ? 'Checking connections...'
                  : connections.isEmpty
                  ? 'No connected services'
                  : 'Connected: ${[for (final c in connections) c.label].join(', ')}',
              style: muted,
            ),
        ],
      ),
    );
  }
}

class _Memory extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    if (vm.loadingMemory) return const Center(child: Spinner(size: 18));
    return Padding(
      padding: const .fromLTRB(8, 0, 32, 24),
      child: LayoutBuilder(
        builder: (context, box) {
          // Narrow: the list, or the file chosen from it with a way back.
          if (box.maxWidth < 560) {
            if (vm.selected == null) return _MemoryList(vm: vm);
            return Column(
              crossAxisAlignment: .start,
              spacing: 8,
              children: [
                Button(
                  variant: .ghost,
                  size: .sm,
                  onPressed: vm.closeFile,
                  child: const Row(
                    mainAxisSize: .min,
                    spacing: 6,
                    children: [
                      AshlarIcon(AshlarIconsRoundedStroke.arrowLeft, size: 14),
                      Text('All files'),
                    ],
                  ),
                ),
                Expanded(
                  child: _MemoryEditor(key: ValueKey(vm.selected!.path), vm: vm),
                ),
              ],
            );
          }
          return _memoryBeside(t);
        },
      ),
    );
  }

  Widget _memoryBeside(AshlarThemeData t) => Row(
    crossAxisAlignment: .stretch,
    spacing: 20,
    children: [
      SizedBox(width: 300, child: _MemoryList(vm: vm)),
      Expanded(
        child: vm.selected == null
            ? Center(
                child: Text(
                  'Choose a file to read or change it.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              )
            : _MemoryEditor(key: ValueKey(vm.selected!.path), vm: vm),
      ),
    ],
  );
}

class _MemoryList extends StatelessWidget {
  const new({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final muted = t.text.xs.copyWith(color: t.colors.mutedForeground);
    final names = {for (final a in vm.agents) a.info.id: a.info.name};
    final rows = <Widget>[];
    for (final engineId in names.keys) {
      final files = vm.files.where((f) => f.engineId == engineId).toList();
      final notes = vm.notes.where((n) => n.engineId == engineId);
      if (files.isEmpty && notes.isEmpty) continue;
      rows.add(
        Padding(
          padding: const .only(top: 14, bottom: 4),
          child: Text(names[engineId]!, style: t.text.sm.copyWith(fontWeight: .w600)),
        ),
      );
      String? project;
      for (final f in files) {
        if (f.project != null && f.project != project) {
          project = f.project;
          rows.add(
            Padding(
              padding: const .only(top: 8, bottom: 2, left: 8),
              child: Text(tildePath(project!), style: muted, maxLines: 1, overflow: .ellipsis),
            ),
          );
        }
        rows.add(_MemoryRow(file: f, vm: vm));
      }
      for (final n in notes) {
        rows.add(
          Padding(
            padding: const .fromLTRB(8, 8, 8, 0),
            child: Text(n.text, style: muted),
          ),
        );
      }
    }
    return ScrollArea(
      child: Column(crossAxisAlignment: .stretch, children: rows),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const new({required this.file, required this.vm});
  final MemoryFile file;
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final selected = vm.selected?.path == file.path;
    final exists = vm.exists(file);
    final name = file.project == null ? file.kind : file.path.split('/').last;
    return Pressable(
      onPressed: () => vm.open(file),
      selected: selected,
      semanticLabel: name,
      builder: (context, state) => Container(
        padding: .fromLTRB(file.project == null ? 8 : 16, 5, 8, 5),
        decoration: BoxDecoration(
          color: selected
              ? t.colors.accent
              : state.hovered
              ? t.colors.accent.withValues(alpha: .5)
              : null,
          borderRadius: .circular(t.radiusMd),
        ),
        child: Text(
          exists ? name : '$name (not written yet)',
          maxLines: 1,
          overflow: .ellipsis,
          style: t.text.sm.copyWith(color: exists ? t.colors.foreground : t.colors.mutedForeground),
        ),
      ),
    );
  }
}

class _MemoryEditor extends StatefulWidget {
  const new({super.key, required this.vm});
  final SettingsViewModel vm;

  @override
  State<_MemoryEditor> createState() => _MemoryEditorState();
}

class _MemoryEditorState extends State<_MemoryEditor> {
  final _text = TextEditingController();
  bool _filled = false;

  /// Shown formatted until you choose to edit it.
  bool _editing = false;

  SettingsViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Delete this memory?',
      body: '${tildePath(vm.selected!.path)} is removed from disk. The agent no longer reads it.',
      action: 'Delete',
      destructive: true,
    );
    if (ok) await vm.remove.execute();
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final original = vm.original;
    if (original == null) return const Center(child: Spinner(size: 18));
    if (!_filled) {
      _filled = true;
      _text.text = original;
    }
    final file = vm.selected!;
    final dirty = _text.text != original;
    final path = Text(
      tildePath(file.path),
      style: t.text.xs.copyWith(color: t.colors.mutedForeground),
      maxLines: 1,
      overflow: .ellipsis,
    );
    if (!_editing) {
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          path,
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: t.colors.border),
                borderRadius: .circular(t.radiusLg),
              ),
              child: ScrollArea(
                child: Padding(
                  padding: const .all(16),
                  child: original.trim().isEmpty
                      ? Text(
                          'Empty. What you write here is read in every new conversation.',
                          style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                        )
                      : MarkdownPreview(original),
                ),
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Button(
                variant: .outline,
                onPressed: () => setState(() => _editing = true),
                child: const Text('Edit'),
              ),
              const Spacer(),
              if (vm.exists(file))
                Button(variant: .ghost, onPressed: _delete, child: const Text('Delete')),
            ],
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        path,
        Expanded(
          child: Textarea(
            controller: _text,
            autofocus: true,
            minLines: 20,
            maxLines: 40,
            resizable: false,
            placeholder: 'Empty. What you write here is read in every new conversation.',
          ),
        ),
        Row(
          spacing: 8,
          children: [
            Button(
              onPressed: dirty
                  ? () async {
                      await vm.save.execute(_text.text);
                      if (mounted) setState(() => _editing = false);
                    }
                  : null,
              child: const Text('Save'),
            ),
            Button(
              variant: .ghost,
              onPressed: () => setState(() {
                _text.text = original;
                _editing = false;
              }),
              child: Text(dirty ? 'Discard changes' : 'Done'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Each repository sessions work in, with what is set for it alone.
class _Projects extends StatelessWidget {
  const _Projects({required this.vm});
  final SettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final s = vm.settings;
    return FutureBuilder(
      future: vm.projects(),
      builder: (context, snap) {
        final repos = snap.data ?? const <String>[];
        return _Page(
          children: [
            const _Heading('Projects', first: true),
            Text(
              'Every git repository your sessions have worked in. What is set here is for '
              'that project alone; "As everywhere" follows General.',
              style: t.text.sm.copyWith(color: t.colors.mutedForeground),
            ),
            if (snap.connectionState != .done)
              const Padding(
                padding: .all(16),
                child: Center(child: Spinner(size: 16)),
              )
            else if (repos.isEmpty)
              Padding(
                padding: const .symmetric(vertical: 16),
                child: Text(
                  'None yet: start a session in a git repository and it shows here.',
                  style: t.text.sm.copyWith(color: t.colors.mutedForeground),
                ),
              ),
            for (final repo in repos) ...[
              _Heading(folderName(repo)),
              Text(tildePath(repo), style: t.text.xs.copyWith(color: t.colors.mutedForeground)),
              _Row(
                title: 'Each session on its own branch',
                description: 'Its own branch and copy, so sessions here do not collide.',
                control: _Choice<bool?>(
                  value: s.project(repo).ownCopies,
                  label: 'Each session on its own branch in ${folderName(repo)}',
                  options: {
                    null: 'As everywhere (${s.ownCopies ? 'on' : 'off'})',
                    true: 'On',
                    false: 'Off',
                  },
                  onChanged: (v) => vm.setProject(repo, ownCopies: v, clearOwn: v == null),
                ),
              ),
              _Row(
                title: 'What Helmy may do without asking',
                description: 'For new sessions here.',
                control: _Choice<PermissionLevel?>(
                  value: s.project(repo).level,
                  label: 'Permission level in ${folderName(repo)}',
                  options: {
                    null: 'As everywhere (${s.defaultLevel.label})',
                    for (final l in PermissionLevel.values) l: l.label,
                  },
                  onChanged: (v) => vm.setProject(repo, level: v, clearLevel: v == null),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One usage window: how much is left, a bar with a mark where use would be
/// if spread evenly over the window, and when it resets.
class _Window extends StatelessWidget {
  const _Window({required this.window, required this.now, required this.until});
  final UsageWindow window;
  final DateTime now;
  final String Function(DateTime, DateTime) until;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final left = (1 - window.used).clamp(0.0, 1.0);
    final pace = window.paceAt(now);
    final ahead = pace != null && window.used > pace + .05;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 4,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(window.name, style: t.text.xs.copyWith(fontWeight: .w500)),
            ),
            Text(
              [
                '${(left * 100).round()}% left',
                if (window.resetsAt != null && window.resetsAt!.isAfter(now))
                  'resets ${until(window.resetsAt!, now)}',
              ].join('  ·  '),
              style: t.text.xs.copyWith(color: t.colors.mutedForeground),
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) => SizedBox(
            height: 8,
            child: Stack(
              clipBehavior: .none,
              children: [
                Container(
                  decoration: BoxDecoration(color: t.colors.muted, borderRadius: .circular(4)),
                ),
                FractionallySizedBox(
                  widthFactor: window.used.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: ahead ? t.colors.destructive : t.colors.foreground,
                      borderRadius: .circular(4),
                    ),
                  ),
                ),
                if (pace != null)
                  Positioned(
                    left: (box.maxWidth * pace - 1).clamp(0, box.maxWidth - 2),
                    top: -3,
                    bottom: -3,
                    child: Container(width: 2, color: t.colors.mutedForeground),
                  ),
              ],
            ),
          ),
        ),
        // Only worth saying when it matters; Helmy moves work elsewhere then.
        if (ahead)
          Text(
            'Used faster than this window allows; at this rate it runs out before it resets, '
            'and I lean on your other connections.',
            style: t.text.xs.copyWith(color: t.colors.mutedForeground),
          ),
      ],
    );
  }
}
