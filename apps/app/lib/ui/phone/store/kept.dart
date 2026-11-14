/// What a remote keeps between runs (its pairing, its look), by name: in
/// the app's own folder on a phone, in the extension's own storage in a
/// browser. Never synced anywhere.
library;

export 'kept_io.dart' if (dart.library.js_interop) 'kept_web.dart';
