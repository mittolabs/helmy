import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry/sentry.dart';

import '../../utils/platform.dart';

/// Reports of Helmy's own errors and crashes, to Mittolabs' Bugslad (which
/// speaks Sentry's protocol). Only when the build names where to send them
/// (`--dart-define=HELMY_ERRORS=<address>`) and the user has not turned them
/// off. A report carries what went wrong in Helmy's code: never a
/// conversation, a file's contents, or a path inside the user's home.
class ErrorReports {
  static const _address = String.fromEnvironment('HELMY_ERRORS');

  /// Whether this build can send reports at all.
  static bool get configured => _address.isNotEmpty;

  static bool _on = false;

  /// Starts reporting, when the build is configured and [allowed]; turned on
  /// or off later with [allow].
  static Future<void> start({required bool allowed, required String release}) async {
    if (!configured) return;
    await Sentry.init((o) {
      o.dsn = _address;
      o.release = 'helmy@$release';
      o.sendDefaultPii = false;
      o.beforeSend = (event, hint) => _on ? scrub(event) : null;
      // Breadcrumbs can hold what was typed or shown: none.
      o.maxBreadcrumbs = 0;
    });
    _on = allowed;
    final flutter = FlutterError.onError;
    FlutterError.onError = (details) {
      if (_on) unawaited(Sentry.captureException(details.exception, stackTrace: details.stack));
      flutter?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      if (_on) unawaited(Sentry.captureException(error, stackTrace: stack));
      return platform?.call(error, stack) ?? false;
    };
  }

  static void allow(bool allowed) => _on = allowed;

  /// [event] with the user's home taken out of every path and message, and
  /// nothing about the user or the machine's name.
  static SentryEvent scrub(SentryEvent event) {
    final home = homeDir;
    String clean(String? s) {
      var out = s ?? '';
      if (home.isNotEmpty) out = out.replaceAll(home, '~');
      return out;
    }

    for (final e in event.exceptions ?? const <SentryException>[]) {
      e.value = clean(e.value);
      for (final f in e.stackTrace?.frames ?? const <SentryStackFrame>[]) {
        f.absPath = f.absPath == null ? null : clean(f.absPath);
        f.fileName = f.fileName == null ? null : clean(f.fileName);
      }
    }
    event.user = null;
    event.serverName = null;
    final message = event.message;
    if (message != null) {
      event.message = SentryMessage(clean(message.formatted));
    }
    return event;
  }
}
