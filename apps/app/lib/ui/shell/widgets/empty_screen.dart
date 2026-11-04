import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/ashlar/button.dart';
import '../../core/ashlar/theme.dart';
import '../view_models/sidebar_view_model.dart';
import 'new_session.dart';

/// No session open.
class EmptyScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final vm = context.read<SidebarViewModel>();
    return ColoredBox(
      color: t.colors.background,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: .min,
            spacing: 8,
            children: [
              Text('Start a session', style: t.text.xl.copyWith(fontWeight: .w600)),
              Text(
                'It keeps going in the background while you look at others.',
                textAlign: .center,
                style: t.text.sm.copyWith(color: t.colors.mutedForeground),
              ),
              const SizedBox(height: 12),
              Button(onPressed: () => newSession(context, vm), child: const Text('New chat')),
            ],
          ),
        ),
      ),
    );
  }
}
