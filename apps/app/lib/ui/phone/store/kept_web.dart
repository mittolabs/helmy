import 'package:web/web.dart' as web;

// The extension's own origin: no page and no other extension reads it, and
// it is not synced.
String _key(String name) => 'helmy.$name';

/// What was kept under [name]; null when nothing was.
Future<String?> keptRead(String name) async {
  try {
    return web.window.localStorage.getItem(_key(name));
  } on Object {
    return null;
  }
}

/// Keeps [value] under [name]; null forgets it.
Future<void> keptWrite(String name, String? value) async {
  try {
    if (value == null) {
      web.window.localStorage.removeItem(_key(name));
    } else {
      web.window.localStorage.setItem(_key(name), value);
    }
  } on Object {
    // Storage turned off: it stays paired until the panel closes.
  }
}
