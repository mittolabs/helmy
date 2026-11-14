/// The page the browser is on, for Helmy in Chrome's "This page". Only in
/// the extension; elsewhere there is none.
library;

export 'page_trouble.dart';
export 'this_page_io.dart' if (dart.library.js_interop) 'this_page_web.dart';
