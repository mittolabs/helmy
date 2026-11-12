/// The entrypoint for the **server** environment.
///
/// The [main] method will only be executed on the server during pre-rendering.
/// To run code on the client, check the `main.client.dart` file.
library;

// Server-specific Jaspr import.
import 'package:jaspr/dom.dart' show Color, Preload, figcaption, figure, video;
import 'package:jaspr/server.dart';

import 'dart:io';

import 'package:jaspr_content/components/callout.dart';
import 'package:jaspr_content/components/code_block.dart';
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
        // Colored code. Dart's grammar comes built in; JSON and shell are VS Code's
        // (grammars/, MIT), read when the docs are built.
        CodeBlock(
          defaultLanguage: 'json',
          grammars: {
            for (final name in ['json', 'bash']) name: File('grammars/$name.tmLanguage.json').readAsStringSync(),
          },
        ),
        // Adds zooming and caption support to images.
        Image(zoom: true),
        // A tutorial at the top of its page, as BetterStack has them: recorded in
        // the real app, voiced by Mitto. <Tutorial src="first-task" title="…" />
        // plays web/videos/first-task.mp4, its first frame web/videos/first-task.jpg.
        CustomComponent(
          pattern: 'Tutorial',
          builder: (_, attrs, _) => figure(
            classes: 'tutorial',
            attributes: {'style': 'margin: 1.25rem 0 2rem'},
            [
              video(
                [],
                src: '/videos/${attrs['src']}.mp4',
                poster: '/videos/${attrs['src']}.jpg',
                controls: true,
                preload: Preload.metadata,
                attributes: {
                  'playsinline': '',
                  'aria-label': attrs['title'] ?? 'Tutorial',
                  'style':
                      'display: block; width: 100%; height: auto; border-radius: 12px; '
                      'border: 1px solid rgba(127, 127, 127, 0.25); background: #000',
                },
              ),
              if (attrs['title'] case final t?)
                figcaption(
                  attributes: {'style': 'margin-top: 0.5rem; font-size: 0.875rem; opacity: 0.7'},
                  [Component.text(t)],
                ),
            ],
          ),
        ),
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
                  SidebarLink(text: 'What Is Helmy?', href: '/'),
                  SidebarLink(text: 'Getting Started', href: '/getting-started'),
                  SidebarLink(text: 'Your First Task', href: '/first-task'),
                ],
              ),
              SidebarGroup(
                title: 'Working With Helmy',
                links: [
                  SidebarLink(text: 'Chats and Threads', href: '/chats'),
                  SidebarLink(text: 'Connections', href: '/connections'),
                  SidebarLink(text: 'Approvals', href: '/approvals'),
                  SidebarLink(text: 'The Vault', href: '/vault'),
                  SidebarLink(text: 'Beside the Chat', href: '/beside-the-chat'),
                  SidebarLink(text: 'Design', href: '/design'),
                  SidebarLink(text: 'Your Phone', href: '/phone'),
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
          // Code sits on a dark panel in both themes: its colors are a dark theme's.
          ContentColors.preBg.apply(ThemeColor(Color('#16130f'), dark: Color('#141210'))),
          ContentColors.preCode.apply(ThemeColor(Color('#e7e2dc'), dark: Color('#e7e2dc'))),
        ],
      ),
    ),
  );
}
