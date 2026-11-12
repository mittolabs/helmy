/// The entry point for pre-rendering the site.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';

import 'analytics.dart';
import 'app.dart';
import 'main.server.options.dart';

const _description =
    'Stop hopping between Claude, ChatGPT and the rest. Helmy picks the right one for each '
    'message, moves on when one runs out, and keeps the whole conversation with you.';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);
  runApp(
    Document(
      title: App.title,
      lang: 'en',
      meta: const {'description': _description, 'theme-color': '#000000'},
      head: [
        link(rel: 'icon', type: 'image/png', href: '/icon.png'),
        _property('og:type', 'website'),
        _property('og:description', _description),
        meta(name: 'twitter:card', content: 'summary'),
        link(rel: 'preconnect', href: 'https://fonts.googleapis.com'),
        link(rel: 'preconnect', href: 'https://fonts.gstatic.com', attributes: {'crossorigin': ''}),
        link(
          rel: 'stylesheet',
          href:
              'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800'
              '&family=Inter:wght@400;500;600;700&display=swap',
        ),
        link(rel: 'stylesheet', href: '/styles.css'),
        script(src: '/reveal.js', defer: true),
        script(src: '/copy.js', defer: true),
        script(src: '/stars.js', defer: true),
        // Analytics, run by us (stats.ashlar.ke), first-party under /u/ (analytics.dart).
        // Release builds only: in development there is no tracker to load.
        if (kReleaseMode) ...[
          script(
            src: '/u/script.js',
            defer: true,
            attributes: {
              'data-website-id': umamiWebsiteId,
              'data-domains': 'helmy.ke',
              'data-do-not-track': 'true',
            },
          ),
          script(src: '/track.js', defer: true),
        ],
      ],
      body: const App(),
    ),
  );
}

/// An Open Graph tag, which is keyed by `property` rather than `name`.
Component _property(String property, String content) => meta(attributes: {'property': property, 'content': content});
