import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/changelog.dart';
import 'pages/home.dart';
import 'pages/pricing.dart';

/// The site, pre-rendered. The only script in the browser is the reveal on
/// scroll in web/reveal.js.
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    div(classes: 'grain', []),
    Router(
      routes: [
        Route(path: '/', builder: (context, state) => const Home()),
        Route(path: '/pricing', builder: (context, state) => const Pricing()),
        Route(path: '/changelog', builder: (context, state) => const Changelog()),
      ],
    ),
  ]);

  static const title = 'Helmy: dream it, do it';
}
