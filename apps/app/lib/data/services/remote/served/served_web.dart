import 'package:web/web.dart' as web;

/// The computer that served this page to a browser, as the browser reached
/// it; null in the extension, which no computer serves.
({String host, int port, bool secure})? servedFrom() {
  final l = web.window.location;
  final secure = l.protocol == 'https:';
  if (!secure && l.protocol != 'http:') return null;
  final port = int.tryParse(l.port) ?? (secure ? 443 : 80);
  return (host: l.hostname, port: port, secure: secure);
}

/// Whether this is Helmy in Chrome, the extension.
bool get inExtension => web.window.location.protocol == 'chrome-extension:';

/// The pairing link in the page's address, after the `#`, where a scanned
/// code puts it: a browser never sends that part to the server.
String? linkInAddress() {
  final h = web.window.location.hash;
  return h.length > 1 ? h.substring(1) : null;
}

/// Takes the pairing link out of the page's address, so it is not left in
/// view, in the browser's history, or in a link shared from the page.
void clearAddress() {
  final l = web.window.location;
  web.window.history.replaceState(null, '', '${l.pathname}${l.search}');
}
