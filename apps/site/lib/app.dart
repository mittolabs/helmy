import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/changelog.dart';
import 'pages/download.dart';
import 'pages/home.dart';

/// The site, pre-rendered. The only script in the browser is web/reveal.js:
/// the reveal on scroll, and the nav filling in once the page scrolls.
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
      ],
    ),
  ]);

  static const title = 'Helmy: dream it, do it';
}
