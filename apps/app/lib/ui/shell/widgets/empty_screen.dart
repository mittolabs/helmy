import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/ashlar/spinner.dart';
import '../../core/ashlar/theme.dart';
import '../view_models/sidebar_view_model.dart';
import 'new_session.dart';

/// No chat open: a new one opens at once, ready to type in, rather than a
/// page with a button to it. A blank one already there (nothing sent or
/// written) is opened again rather than another made.
class EmptyScreen extends StatefulWidget {
  const new({super.key});

  @override
  State<EmptyScreen> createState() => _EmptyScreenState();
}

class _EmptyScreenState extends State<EmptyScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    if (!mounted) return;
    final vm = context.read<SidebarViewModel>();
    final blank = vm.sessions.where((s) => s.blank && !s.archived).firstOrNull;
    if (blank != null) return context.go('/s/${blank.id}');
    await newSession(context, vm);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AshlarTheme.of(context).colors.background,
    child: const Center(child: Spinner(size: 16)),
  );
}
