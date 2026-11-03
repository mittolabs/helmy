import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../../utils/result.dart';
import '../view_models/sidebar_view_model.dart';

/// Opens a new session straight away, in the folder last worked in.
Future<void> newSession(BuildContext context, SidebarViewModel viewModel) async {
  await viewModel.create.execute();
  if (!context.mounted) return;
  if (viewModel.create.result case Ok(:final value)) context.go('/s/${value.id}');
}
