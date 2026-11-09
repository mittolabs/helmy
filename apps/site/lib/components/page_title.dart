import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A page's title, in the tab and in the Open Graph card a shared link shows.
class PageTitle extends StatelessComponent {
  const PageTitle(this.title, {super.key});

  final String title;

  @override
  Component build(BuildContext context) => Document.head(
    title: title,
    children: [
      meta(id: 'og-title', attributes: {'property': 'og:title', 'content': title}),
    ],
  );
}
