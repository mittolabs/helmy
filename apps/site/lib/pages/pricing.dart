import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../components/chrome.dart';
import '../components/page_title.dart';

/// What Helmy costs: nothing, for now, said plainly.
class Pricing extends StatelessComponent {
  const Pricing({super.key});

  @override
  Component build(BuildContext context) => Component.fragment([
    const PageTitle('Pricing · Helmy'),
    const Nav(),
    main_([
      const PageHead(
        eyebrow: 'Pricing',
        title: 'Free, while it grows.',
        lead:
            'Helmy costs nothing today. You pay only for the AI tools you already use, '
            'and Helmy makes their limits go further.',
      ),
      section(classes: 'wrap plans', [
        div(classes: 'plan reveal', [
          p(classes: 'eyebrow', [Component.text('Now')]),
          h2([Component.text('\$0')]),
          p(classes: 'muted', [Component.text('Everything Helmy does, on your Mac and your phone.')]),
          ul(classes: 'points', [
            li([Component.text('Every connection, every panel, the design canvas')]),
            li([Component.text('Your phone, paired to your Mac')]),
            li([Component.text('Approvals decided for you, and the vault')]),
          ]),
        ]),
        div(classes: 'plan plan-quiet reveal', [
          p(classes: 'eyebrow', [Component.text('Later')]),
          h2([Component.text('Not decided')]),
          p(classes: 'muted', [
            Component.text(
              'If Helmy ever charges, it will be for what costs us to run, such as work that '
              'carries on while your Mac is off. What you can run yourself stays free.',
            ),
          ]),
        ]),
      ]),
    ]),
    const Footer(),
  ]);
}
