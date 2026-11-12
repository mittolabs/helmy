part of '../chat_screen.dart';

/// The strip under the message box: the chat's project (choose one, or none),
/// its files, and Helmy's skills to pick from.
class _Tray extends StatelessWidget {
  const _Tray({required this.vm, required this.session, required this.onSkills});
  final ChatViewModel vm;
  final Session session;

  /// Opens the skills list in the message box, as typing / does.
  final VoidCallback onSkills;

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
            _TrayButton(
              icon: AshlarIconsRoundedStroke.files,
              label: 'Files',
              words: words,
              onPressed: () => vm.show(.files),
            ),
            _TrayButton(
              icon: AshlarIconsRoundedStroke.puzzle,
              label: 'Skills',
              words: words,
              onPressed: onSkills,
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
    required this.icon,
    required this.label,
    required this.onPressed,
    this.words = true,
  });
  final IconData icon;
  final String label;
  final bool words;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    return Pressable(
      onPressed: onPressed,
      semanticLabel: label,
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
            AshlarIcon(icon, size: 13, color: state.hovered ? c.foreground : c.mutedForeground),
            if (words)
              Text(
                label,
                style: t.text.xs.copyWith(
                  color: state.hovered ? c.foreground : c.mutedForeground,
                  height: 1,
                ),
              ),
          ],
        ),
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
