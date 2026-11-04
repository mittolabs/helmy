import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Where you have been in the app, for ⌘[ and ⌘] like a browser's back and
/// forward. go_router replaces the location rather than stacking it, so the
/// trail is kept here, from the router's own changes. It tells its
/// listeners when going back or forward becomes possible or not.
class NavHistory extends ChangeNotifier {
  new(this._router) {
    _router.routerDelegate.addListener(_onChange);
    _onChange();
  }

  final GoRouter _router;
  final List<String> _trail = [];
  int _at = -1;

  /// The one for this app, set when the router is made.
  static NavHistory? current;

  String get _here => _router.routerDelegate.currentConfiguration.uri.toString();

  void _onChange() {
    final here = _here;
    if (here.isEmpty) return;
    // Arrived at by going back or forward: the trail already has it.
    if (_at >= 0 && _trail[_at] == here) return;
    _trail
      ..removeRange(_at + 1, _trail.length)
      ..add(here);
    if (_trail.length > 100) _trail.removeAt(0);
    _at = _trail.length - 1;
    notifyListeners();
  }

  bool get canBack => _at > 0;
  bool get canForward => _at < _trail.length - 1;

  void back() {
    if (!canBack) return;
    _router.go(_trail[--_at]);
    notifyListeners();
  }

  void forward() {
    if (!canForward) return;
    _router.go(_trail[++_at]);
    notifyListeners();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onChange);
    super.dispose();
  }
}
