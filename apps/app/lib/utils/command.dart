import 'package:flutter/foundation.dart';

import 'result.dart';

typedef CommandAction0<T> = Future<Result<T>> Function();
typedef CommandAction1<T, A> = Future<Result<T>> Function(A);

/// An action a view triggers, with its running and error state. A call made
/// while one is running is dropped.
abstract class Command<T> extends ChangeNotifier {
  bool _running = false;
  bool get running => _running;

  Result<T>? _result;
  Result<T>? get result => _result;
  bool get error => _result is Error;
  bool get completed => _result is Ok;

  void clearResult() {
    _result = null;
    notifyListeners();
  }

  Future<void> _execute(CommandAction0<T> action) async {
    if (_running) return;
    _running = true;
    _result = null;
    notifyListeners();
    try {
      _result = await action();
    } finally {
      _running = false;
      notifyListeners();
    }
  }
}

class Command0<T> extends Command<T> {
  new(this._action);
  final CommandAction0<T> _action;
  Future<void> execute() => _execute(_action);
}

class Command1<T, A> extends Command<T> {
  new(this._action);
  final CommandAction1<T, A> _action;
  Future<void> execute(A argument) => _execute(() => _action(argument));
}
