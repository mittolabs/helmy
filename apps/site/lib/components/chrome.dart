import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../analytics.dart';
import 'star.dart';

/// The bar at the top: Helmy, its pages, and the way to get it.
class Nav extends StatelessComponent {
  const Nav({super.key});

  @override
  Component build(BuildContext context) => header(classes: 'nav', [
    div(classes: 'wrap nav-inner', [
      a(classes: 'brand', href: '/', [
        img(src: '/icon.png', alt: '', width: 28, height: 28),
        span([Component.text('Helmy')]),
      ]),
      nav(classes: 'links', [
        a(href: '/#how', [Component.text('How it works')]),
        a(href: '/download', attributes: track('get-helmy', {'from': 'nav link'}), [Component.text('Download')]),
        a(href: '/changelog', [Component.text('Changelog')]),
        a(href: '/docs/', [Component.text('Docs')]),
      ]),
      const Star(from: 'nav'),
      a(
        classes: 'btn btn-light btn-sm',
        href: '/download',
        attributes: track('get-helmy', {'from': 'nav'}),
        [Component.text('Get Helmy')],
      ),
    ]),
  ]);
}

/// The foot of every page.
class Footer extends StatelessComponent {
  const Footer({super.key});

  @override
  Component build(BuildContext context) => footer(classes: 'footer', [
    div(classes: 'wrap footer-grid', [
      div(classes: 'footer-brand', [
        img(src: '/helmy/hello.png', alt: '', width: 44, height: 44),
        div([
          p([
            strong([Component.text('Helmy')]),
          ]),
          p(classes: 'muted', [Component.text('Dream it, do it.')]),
        ]),
      ]),
      _column('Product', [
        ('/#how', 'How it works'),
        ('/download', 'Download'),
        ('/changelog', 'Changelog'),
        ('/docs/', 'Docs'),
      ]),
      _column('Open source', [
        (repoUrl, 'GitHub'),
        ('$repoUrl/blob/main/CONTRIBUTING.md', 'Contributing'),
        ('$repoUrl/issues/new/choose', 'Report a bug'),
        ('$repoUrl/blob/main/SECURITY.md', 'Security'),
      ]),
      _column('Legal', [
        ('/privacy', 'Privacy'),
        ('/terms', 'Terms'),
        ('$repoUrl/blob/main/LICENSE', 'License (BSD)'),
      ]),
    ]),
    div(classes: 'wrap footer-base', [
      p([Component.text('© 2026 Mittolabs. Helmy is free and open source.')]),
      p(classes: 'footer-powered', [
        img(src: '/mittolabs-white.png', alt: '', width: 16, height: 15),
        Component.text('Powered by '),
        b([Component.text('Mittolabs')]),
      ]),
    ]),
  ]);

  static Component _column(String title, List<(String, String)> links) => nav(classes: 'footer-col', [
    p(classes: 'footer-title', [Component.text(title)]),
    for (final (href, text) in links)
      a(
        href: href,
        attributes: href.startsWith('http') ? {'target': '_blank', 'rel': 'noopener'} : null,
        [Component.text(text)],
      ),
  ]);
}

/// A page's heading block, for the pages that are not the home page.
class PageHead extends StatelessComponent {
  const PageHead({super.key, required this.eyebrow, required this.title, required this.lead});
  final String eyebrow, title, lead;

  @override
  Component build(BuildContext context) => section(classes: 'page-head wrap', [
    p(classes: 'eyebrow reveal', [Component.text(eyebrow)]),
    h1(classes: 'reveal', [Component.text(title)]),
    p(classes: 'lead reveal', [Component.text(lead)]),
  ]);
}
