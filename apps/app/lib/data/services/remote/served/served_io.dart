/// The page this remote was served as: never, in an app.
({String host, int port, bool secure})? servedFrom() => null;

/// Whether this is Helmy in Chrome, the extension: never, in an app.
bool get inExtension => false;

/// The pairing link in the page's address, after the `#`: none in an app.
String? linkInAddress() => null;

/// Takes the pairing link out of the page's address.
void clearAddress() {}
