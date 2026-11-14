part of '../chat_screen.dart';

/// The strip under the message box: what this chat is, where it stands,
/// and whether the person is away. Its project (choose one, or none); then,
/// only while there is something to show, its branch, the lines it changed
/// and what waits for the person; then Away. The chat's files are in the
/// panel's +, and skills a / away.
class _Tray extends StatelessWidget {
  const _Tray({required this.vm, required this.session, required this.onWaiting});
  final ChatViewModel vm;
  final Session session;

  /// Goes to the first thing waiting for the person.
  final VoidCallback onWaiting;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final style = t.text.xs.copyWith(color: c.mutedForeground, height: 1);
    // Narrow (a phone's width), the buttons keep their icons and lose their words.
    return LayoutBuilder(
      builder: (context, box) {
        final words = box.maxWidth >= 380;
        return Row(
          spacing: 2,
          children: [
            Flexible(
              child: Padding(
                padding: const .symmetric(horizontal: 6, vertical: 4),
                child: TourTarget(
                  stop: .folder,
                  child: _FolderButton(
                    vm: vm,
                    cwd: session.ownCopy ? session.repo! : session.cwd,
                    style: style,
                  ),
                ),
              ),
            ),
            if (vm.branch case final branch?)
              Flexible(
                child: Tooltip(
                  message: session.ownCopy
                      ? 'On $branch, its own branch, in its own copy: other threads here are '
                            'not disturbed'
                      : 'On $branch. Press for its pull request.',
                  child: _TrayButton(
                    icon: AshlarIconsRoundedStroke.gitBranch,
                    label: branch,
                    words: words,
                    shrinks: true,
                    onPressed: () => vm.show(.ship),
                  ),
                ),
              ),
            if (vm.changedLines case (:final added, :final removed)
                when added + removed > 0 || (vm.changedFiles ?? 0) > 0)
              Tooltip(
                message: 'What this chat changed. Press to review or undo.',
                child: added + removed > 0
                    ? _TrayButton(
                        label: '+$added −$removed',
                        semanticLabel: '$added lines added, $removed removed. Review changes',
                        mono: true,
                        onPressed: vm.showChanges,
                      )
                    // Only files whose lines are not counted (pictures, moves).
                    : _TrayButton(
                        icon: AshlarIconsRoundedStroke.fileDiff,
                        label: '${vm.changedFiles} changed',
                        words: words,
                        onPressed: vm.showChanges,
                      ),
              ),
            if (vm.waiting.length case final n when n > 0)
              Tooltip(
                message: n == 1
                    ? 'Something is waiting for your answer. Press to go to it.'
                    : '$n things are waiting for your answer. Press to go to the first.',
                child: _TrayButton(
                  icon: AshlarIconsRoundedStroke.messageCircleQuestionMark,
                  // Narrow, the count alone.
                  label: words ? '$n waiting' : '$n',
                  semanticLabel: '$n waiting for you. Go to it',
                  on: true,
                  onPressed: onWaiting,
                ),
              ),
            Tooltip(
              message: vm.away
                  ? "Away: I decide what I'd ask you, and keep what I still must ask "
                        'for when you are back. Press when you are back.'
                  : "Going away? I'll decide what I'd ask you and keep working.",
              child: _TrayButton(
                icon: AshlarIconsRoundedStroke.moon,
                label: 'Away',
                words: words,
                on: vm.away,
                onPressed: () => unawaited(vm.setAway(!vm.away)),
              ),
            ),
            if (vm.developerMode) _ModelPicker(vm: vm, words: words),
          ],
        );
      },
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    this.icon,
    required this.label,
    required this.onPressed,
    this.words = true,
    this.on,
    this.mono = false,
    this.semanticLabel,
    this.shrinks = false,
  });

  /// Its label gives way, ending in an ellipsis, when the tray runs short:
  /// only for a button in a [Flexible].
  final bool shrinks;
  final IconData? icon;
  final String label;
  final bool words;
  final VoidCallback onPressed;

  /// The label in the code font: figures that line up.
  final bool mono;

  /// What a screen reader says, when [label] alone does not.
  final String? semanticLabel;

  /// A switch's state; null for a plain button.
  final bool? on;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final lit = on ?? false;
    Widget caption(Color ink) => Text(
      label,
      maxLines: 1,
      overflow: .ellipsis,
      style: t.text.xs.copyWith(
        color: ink,
        height: 1,
        fontFamily: mono ? 'monospace' : null,
        fontFamilyFallback: mono ? monoFonts : null,
      ),
    );
    return Semantics(
      toggled: on,
      child: Pressable(
        onPressed: onPressed,
        semanticLabel: semanticLabel ?? label,
        builder: (context, state) {
          final ink = state.hovered || lit ? c.foreground : c.mutedForeground;
          final text = caption(ink);
          return Container(
            padding: const .symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: lit
                  ? c.foreground.withValues(alpha: state.hovered ? .14 : .1)
                  : state.hovered
                  ? c.foreground.withValues(alpha: .06)
                  : null,
              borderRadius: .circular(t.radiusMd),
            ),
            child: Row(
              mainAxisSize: .min,
              spacing: 5,
              children: [
                if (icon case final icon?) AshlarIcon(icon, size: 13, color: ink),
                if (words || icon == null)
                  if (shrinks) Flexible(child: text) else text,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Developer mode's picker, under the message box: Helmy choosing, or a
/// connection and one of its models, with its effort and its faster tier.
/// The choice is the chat's, kept with it.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.vm, required this.words});
  final ChatViewModel vm;
  final bool words;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final pin = vm.pin;
    return FutureBuilder(
      future: vm.pinChoices(),
      builder: (context, snap) {
        final choices = snap.data ?? const [];
        final connection = pin == null
            ? null
            : choices.where((x) => x.id == pin.engineId).firstOrNull;
        final model = pin?.model == null
            ? null
            : connection?.models.where((m) => m.id == pin!.model).firstOrNull;
        final label = pin == null
            ? 'Helmy chooses'
            : [
                vm.connectionName(pin.engineId) ?? pin.engineId,
                if (pin.model case final id?) model?.name ?? modelLabel(id),
                ?pin.effort,
                if (pin.fast) 'Fast',
              ].join(' · ');
        return DropdownMenu(
          side: .top,
          items: [
            MenuItem(
              selected: pin == null,
              leading: const AshlarIcon(AshlarIconsRoundedStroke.sparkles, size: 16),
              onPressed: () => unawaited(vm.setPin(null)),
              child: const Text('Let Helmy choose'),
            ),
            const MenuSeparator(),
            if (snap.connectionState != .done)
              const MenuLabel(child: Text('Finding models...'))
            else if (choices.isEmpty)
              const MenuLabel(child: Text('No connection is set up'))
            else
              for (final x in choices)
                x.models.isEmpty
                    ? MenuItem(
                        selected: pin?.engineId == x.id,
                        leading: ConnectionLogo(x.id, brand: true),
                        onPressed: () => unawaited(vm.setPin(EnginePin(engineId: x.id))),
                        child: Text(x.name),
                      )
                    : MenuSub(
                        leading: ConnectionLogo(x.id, brand: true),
                        items: [
                          MenuItem(
                            selected: pin?.engineId == x.id && pin?.model == null,
                            onPressed: () => unawaited(vm.setPin(EnginePin(engineId: x.id))),
                            child: const Text('Its default'),
                          ),
                          for (final m in x.models)
                            MenuItem(
                              selected: pin?.engineId == x.id && pin?.model == m.id,
                              onPressed: () => unawaited(
                                vm.setPin(
                                  EnginePin(
                                    engineId: x.id,
                                    model: m.id,
                                    // Kept where the new model takes it.
                                    effort: m.efforts.contains(pin?.effort) ? pin?.effort : null,
                                    fast: m.fast && (pin?.fast ?? false),
                                  ),
                                ),
                              ),
                              child: Tooltip(
                                message: m.description.isEmpty ? m.name : m.description,
                                child: Text(m.name),
                              ),
                            ),
                        ],
                        child: Text(x.name),
                      ),
            if (pin != null && (model?.efforts.isNotEmpty ?? false)) ...[
              const MenuSeparator(),
              MenuSub(
                leading: const AshlarIcon(AshlarIconsRoundedStroke.brain, size: 16),
                items: [
                  MenuItem(
                    selected: pin.effort == null,
                    onPressed: () => unawaited(
                      vm.setPin(
                        EnginePin(engineId: pin.engineId, model: pin.model, fast: pin.fast),
                      ),
                    ),
                    child: Text(
                      model!.defaultEffort == null
                          ? 'Its default'
                          : 'Its default (${model.defaultEffort})',
                    ),
                  ),
                  for (final e in model.efforts)
                    MenuItem(
                      selected: pin.effort == e,
                      onPressed: () => unawaited(
                        vm.setPin(
                          EnginePin(
                            engineId: pin.engineId,
                            model: pin.model,
                            effort: e,
                            fast: pin.fast,
                          ),
                        ),
                      ),
                      child: Text(e),
                    ),
                ],
                child: Text('Effort: ${pin.effort ?? 'default'}'),
              ),
            ],
            if (pin != null && (model?.fast ?? false))
              MenuCheckboxItem(
                checked: pin.fast,
                onChanged: (on) => unawaited(
                  vm.setPin(
                    EnginePin(
                      engineId: pin.engineId,
                      model: pin.model,
                      effort: pin.effort,
                      fast: on,
                    ),
                  ),
                ),
                child: const Text('Fast (uses more of the plan)'),
              ),
          ],
          builder: (context, menu) => Tooltip(
            message: pin == null
                ? 'Helmy picks the connection and model for each message'
                : 'This chat is held to this connection and model',
            child: Pressable(
              onPressed: menu.open,
              semanticLabel: 'Connection and model: $label',
              builder: (context, state) => Container(
                padding: const .symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: state.hovered ? c.foreground.withValues(alpha: .06) : null,
                  borderRadius: .circular(t.radiusMd),
                ),
                child: Row(
                  mainAxisSize: .min,
                  spacing: 5,
                  children: [
                    if (pin == null)
                      AshlarIcon(
                        AshlarIconsRoundedStroke.sparkles,
                        size: 13,
                        color: c.mutedForeground,
                      )
                    else
                      ConnectionLogo(pin.engineId, size: 13, brand: true),
                    if (words)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: t.text.xs.copyWith(
                            color: state.hovered ? c.foreground : c.mutedForeground,
                            height: 1,
                          ),
                        ),
                      ),
                    AshlarIcon(
                      AshlarIconsRoundedStroke.chevronDown,
                      size: 11,
                      color: c.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
