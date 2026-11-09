import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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
        a(href: '/#open', [Component.text('Open source')]),
        a(href: '/changelog', [Component.text('Changelog')]),
        a(href: '/docs/', [Component.text('Docs')]),
      ]),
      a(classes: 'btn btn-light btn-sm', href: '/#get', [Component.text('Get Helmy')]),
    ]),
  ]);
}

/// The foot of every page.
class Footer extends StatelessComponent {
  const Footer({super.key});

  @override
  Component build(BuildContext context) => footer(classes: 'footer', [
    div(classes: 'wrap footer-inner', [
      div(classes: 'footer-brand', [
        img(src: '/helmy/hello.png', alt: '', width: 44, height: 44),
        div([
          p([strong([Component.text('Helmy')])]),
          p(classes: 'muted', [Component.text('Dream it, do it. Made by Mittolabs.')]),
        ]),
      ]),
      nav(classes: 'footer-links', [
        a(href: '/#how', [Component.text('How it works')]),
        a(href: '/#open', [Component.text('Open source')]),
        a(href: '/changelog', [Component.text('Changelog')]),
        a(href: '/docs/', [Component.text('Docs')]),
      ]),
      p(classes: 'muted small', [Component.text('© 2026 Mittolabs')]),
    ]),
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
