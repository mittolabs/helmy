import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../ui/chat/view_models/chat_view_model.dart';
import '../ui/chat/widgets/chat_screen.dart';
import '../ui/schedule/view_models/schedule_view_model.dart';
import '../ui/schedule/widgets/schedule_screen.dart';
import '../ui/settings/view_models/settings_view_model.dart';
import '../ui/settings/widgets/settings_screen.dart';
import '../ui/shell/view_models/sidebar_view_model.dart';
import '../ui/shell/widgets/empty_screen.dart';
import '../ui/shell/widgets/shell_screen.dart';
import '../ui/setup/setup_screen.dart';

GoRouter router(String initialLocation) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => _Kept(
        create: (context) => SidebarViewModel(
          attention: context.read(),
          sessions: context.read(),
          conversations: context.read(),
          settings: context.read(),
          projects: context.read(),
          fixes: context.read(),
        ),
        builder: (vm) => ChangeNotifierProvider.value(
          value: vm,
          child: ShellScreen(
            viewModel: vm,
            selectedId: state.pathParameters['id'],
            inSettings: state.uri.path == '/settings',
            inSchedule: state.uri.path == '/scheduled',
            child: child,
          ),
        ),
      ),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const EmptyScreen()),
        GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
        GoRoute(
          path: '/settings',
          builder: (context, state) => _Kept(
            create: (context) =>
                SettingsViewModel(
                    settings: context.read(),
                    engines: context.read(),
                    meter: context.read(),
                    memory: context.read(),
                  )
                  ..desktop = context.read()
                  ..sessions = context.read()
                  ..projectsOf = context.read()
                  ..section =
                      SettingsSection.values.asNameMap()[state.uri.queryParameters['section']] ??
                      .general,
            builder: (vm) => SettingsScreen(viewModel: vm),
            key: ValueKey(state.uri.toString()),
          ),
        ),
        GoRoute(
          path: '/scheduled',
          builder: (context, state) => _Kept(
            create: (context) =>
                ScheduleViewModel(schedules: context.read(), settings: context.read()),
            builder: (vm) => ScheduleScreen(viewModel: vm),
          ),
        ),
        GoRoute(
          path: '/s/:id',
          builder: (context, state) => _Kept(
            key: ValueKey(state.uri.toString()),
            create: (context) => ChatViewModel(
              attention: context.read(),
              settings: context.read(),
              sessionId: state.pathParameters['id']!,
              sessions: context.read(),
              conversations: context.read(),
              projects: context.read(),
              desktop: context.read(),
              watch: context.read(),
              fixes: context.read(),
              devices: context.read(),
            ),
            builder: (vm) => ChatScreen(viewModel: vm),
          ),
        ),
      ],
    ),
  ],
);

/// Makes a page's view model once and disposes it with the page, since
/// go_router calls a route's builder again whenever it moves
/// (docs/engineering/flutter.md).
class _Kept<T extends ChangeNotifier> extends StatefulWidget {
  const new({super.key, required this.create, required this.builder});
  final T Function(BuildContext context) create;
  final Widget Function(T viewModel) builder;

  @override
  State<_Kept<T>> createState() => _KeptState<T>();
}

class _KeptState<T extends ChangeNotifier> extends State<_Kept<T>> {
  late final T viewModel = widget.create(context);

  @override
  void dispose() {
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(viewModel);
}
