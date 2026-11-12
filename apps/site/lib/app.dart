import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/changelog.dart';
import 'pages/download.dart';
import 'pages/home.dart';
import 'pages/privacy.dart';
import 'pages/terms.dart';

/// The site, pre-rendered. The scripts in the browser are web/reveal.js (the reveal
/// on scroll, the nav filling in once the page scrolls) and, on helmy.ke, Umami's
/// with web/track.js (analytics.dart).
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    div(classes: 'grain', []),
    Router(
      routes: [
        Route(path: '/', builder: (context, state) => const Home()),
        Route(path: '/changelog', builder: (context, state) => const Changelog()),
        Route(path: '/download', builder: (context, state) => const Download()),
        Route(path: '/privacy', builder: (context, state) => const Privacy()),
        Route(path: '/terms', builder: (context, state) => const Terms()),
      ],
    ),
  ]);

  static const title = 'Helmy: dream it, do it';
}
