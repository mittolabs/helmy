/// Where the remote runs when it is a page: served by Helmy on a computer
/// to a phone's browser, or in Chrome as the extension. Nothing on a phone
/// app.
library;

export 'served/served_io.dart' if (dart.library.js_interop) 'served/served_web.dart';
