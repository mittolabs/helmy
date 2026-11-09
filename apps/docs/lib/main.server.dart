/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

// Server-specific Jaspr import.
import 'package:jaspr/dom.dart' show Color;
import 'package:jaspr/server.dart';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/header.dart';
import 'package:jaspr_content/components/image.dart';
import 'package:jaspr_content/components/sidebar.dart';
import 'package:jaspr_content/components/theme_toggle.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

// This file is generated automatically by Jaspr, do not remove or edit.
import 'main.server.options.dart';

void main() {
  // Initializes the server environment with the generated default options.
  Jaspr.initializeApp(
    options: defaultServerOptions,
  );

  // Starts the app.
  //
  // [ContentApp] spins up the content rendering pipeline from jaspr_content to render
  // your markdown files in the content/ directory to a beautiful documentation site.
  runApp(
    ContentApp(
      // Enables mustache templating inside the markdown files.
      templateEngine: MustacheTemplateEngine(),
      parsers: [
        MarkdownParser(),
      ],
      extensions: [
        // Adds heading anchors to each heading.
        HeadingAnchorsExtension(),
        // Generates a table of contents for each page.
        TableOfContentsExtension(),
      ],
      components: [
        // The <Info> block and other callouts.
        Callout(),
        // Adds zooming and caption support to images.
        Image(zoom: true),
      ],
      layouts: [
        // Out-of-the-box layout for documentation sites.
        DocsLayout(
          header: Header(
            title: 'Helmy docs',
            logo: '/images/helmy.png',
            items: [
              // Enables switching between light and dark mode.
              ThemeToggle(),
            ],
          ),
          sidebar: Sidebar(
            groups: [
              SidebarGroup(
                links: [
                  SidebarLink(text: 'What Helmy is', href: '/'),
                  SidebarLink(text: 'Getting started', href: '/getting-started'),
                ],
              ),
              SidebarGroup(
                title: 'Working with Helmy',
                links: [
                  SidebarLink(text: 'Connections', href: '/connections'),
                  SidebarLink(text: 'Approvals', href: '/approvals'),
                  SidebarLink(text: 'The vault', href: '/vault'),
                  SidebarLink(text: 'Design', href: '/design'),
                  SidebarLink(text: 'Your phone', href: '/phone'),
                ],
              ),
            ],
          ),
        ),
      ],
      theme: ContentTheme(
        // Customizes the default theme colors.
        // Helmy's warm accent, on the app's black.
        primary: ThemeColor(ThemeColors.orange.$600, dark: ThemeColors.orange.$300),
        background: ThemeColor(ThemeColors.stone.$50, dark: Color('#000000')),
        colors: [
          ContentColors.quoteBorders.apply(ThemeColors.orange.$400),
        ],
      ),
    ),
  );
}
