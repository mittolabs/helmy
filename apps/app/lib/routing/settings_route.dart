import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../ui/settings/view_models/settings_view_model.dart';

/// Opens Settings over the page, at [section] when given.
void openSettings(GoRouter router, [SettingsSection? section]) {
  final where = section == null ? '/settings' : '/settings?section=${section.name}';
  if (router.state.uri.path == '/settings') {
    router.replace(where);
  } else {
    unawaited(router.push(where));
  }
}

/// Closes Settings, back to the page it opened over.
void closeSettings(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/');
  }
}
