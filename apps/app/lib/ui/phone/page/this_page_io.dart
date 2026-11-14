import '../../../domain/browser_page.dart';

/// Whether this remote can take the page it is beside: only in Chrome.
const pageHere = false;

/// The page the browser is on; null where there is none.
Future<BrowserPage?> thisPage() async => null;
