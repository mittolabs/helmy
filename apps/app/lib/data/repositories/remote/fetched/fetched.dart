/// Where a remote keeps a file it fetched from the computer Helmy runs on,
/// to show it: a temporary file on a phone, a `blob:` address in a browser.
library;

export 'fetched_io.dart' if (dart.library.js_interop) 'fetched_web.dart';
