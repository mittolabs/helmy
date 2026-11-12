import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/design_export/export.dart';
import 'package:helmy/domain/design_export/flutter_css.dart';
import 'package:helmy/domain/design_export/flutter_writer.dart';
import 'package:helmy/domain/design_export/image_size.dart';
import 'package:helmy/domain/design_export/planner.dart';
import 'package:helmy/domain/design_export/react_writer.dart';
import 'package:helmy/domain/design_export/subset.dart';
import 'package:helmy/domain/identity.dart';
import 'package:helmy/domain/design_export/reader.dart';

void main() {
  test('an inline style is read with its brackets and quotes kept whole', () {
    expect(parseStyle("color:#fff;background:url('a;b.png');padding:clamp(1px, 2vw, 3px);"), {
      'color': '#fff',
      'background': "url('a;b.png')",
      'padding': 'clamp(1px, 2vw, 3px)',
    });
  });

  test('a design is cut where it already is, the same way every time', () async {
    final d = await readDesign('test/fixtures/design');
    final plan = planDesign(title: d.title, screens: d.screens);
    final again = planDesign(
      title: d.title,
      screens: (await readDesign('test/fixtures/design')).screens,
    );

    expect(plan.screens.map((s) => s.title), ['Home', 'Download']);
    final download = plan.parts[plan.screens[1]]!.map((p) => p.name).toList();
    expect(download.first, 'Header');
    expect(download.last, 'Footer');
    expect(download, containsAll(['WindowsSection', 'LinuxSection', 'TerminalSection']));

    final names = plan.components.map((c) => c.name).toList();
    // On both screens: the site's own, one file each.
    expect(names, containsAll(['SiteHeader', 'SiteFooter']));
    // The five download links: one component, its words and link the parameters.
    final link = plan.components.firstWhere((c) => c.name == 'DownloadLink');
    expect(link.uses, hasLength(5));
    expect(link.params.map((p) => p.name), ['href', 'text', 'text2']);
    expect(link.argsOf(link.uses[1])['text'], isNot(link.argsOf(link.uses[0])['text']));

    // The page's own font is the body's; the headings' face is the display one.
    expect(plan.tokens.firstWhere((t) => t.name == 'fontBody').value, startsWith('Inter'));
    expect(plan.tokens.firstWhere((t) => t.name == 'fontDisplay').value, contains('Bricolage'));

    expect(names, again.components.map((c) => c.name).toList());
  });

  test('React: no file is a monolith, and a component takes what differs as props', () async {
    final d = await readDesign('test/fixtures/design');
    final out = writeReact(planDesign(title: d.title, screens: d.screens));
    final files = out.files;
    expect(
      files.keys,
      containsAll([
        'src/screens/Download/Download.tsx',
        'src/components/SiteFooter.tsx',
        'src/theme.css',
      ]),
    );
    for (final e in files.entries.where((e) => e.key.endsWith('.tsx'))) {
      expect('\n'.allMatches(e.value).length, lessThan(220), reason: '${e.key} runs long');
    }
    final link = files['src/components/DownloadLink.tsx']!;
    expect(link, contains('export default function DownloadLink({ href, text, text2 }'));
    expect(link, contains('>{text}</p>'));
    // A link to another screen is the router's; images come from public/.
    expect(files['src/components/SiteHeader.tsx'], contains('<Link to="/download"'));
    expect(out.assets, contains('img/icon.png'));
    // Colors the design reuses are the theme's, by name.
    expect(files['src/theme.css'], contains('--text2: #f5f5f3;'));
    expect(link, contains('color: "var(--text2)"'));
    // Space a browser never draws is not written.
    expect(files['src/screens/Download/Download.tsx'], isNot(contains("{' '}")));
  });

  test('exported into a folder: the web as it is, React as a project with its images', () async {
    final out = await Directory.systemTemp.createTemp('export');
    addTearDown(() => out.delete(recursive: true));
    final web = await exportDesign('test/fixtures/design', '${out.path}/web', ExportTarget.web);
    expect(web, containsAll(['download.html', 'index.html', 'img/icon.png']));
    expect(web, isNot(contains('canvas.json')), reason: "the canvas's index is not the site");
    final react = await exportDesign(
      'test/fixtures/design',
      '${out.path}/react',
      ExportTarget.react,
    );
    expect(
      react,
      containsAll(['package.json', 'index.html', 'src/main.tsx', 'public/img/icon.png']),
    );
    expect(
      File('${out.path}/react/src/screens/Download/Download.tsx').readAsStringSync(),
      contains('↗'),
    );
  });

  test('what will not convert to app code is found, each with where and why', () async {
    // The real design converts whole: its sticky header, drop-shadow and
    // saturated backdrop included.
    expect(await checkDesign('test/fixtures/design'), isEmpty);

    List<SubsetIssue> check(String body, {String css = '', String head = ''}) => checkSubset(
      readScreen(
        'a.html',
        '<html><head>$head<style>$css</style></head><body>$body</body></html>',
        title: 'A',
      ),
    );
    // A header stuck to the top is pinned; sticky anywhere else is not.
    expect(check('<header style="position:sticky;top:0">x</header><main>y</main>'), isEmpty);
    final sticky = check('<main>y</main><aside style="position:sticky;top:0">x</aside>');
    expect(sticky.single.what, 'position: sticky');
    // Found again on the page by where it is.
    expect(sticky.single.selector, startsWith('body > '));
    // A font only some computers have cannot be bundled; one from Google Fonts can.
    const fonts =
        '<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400&amp;display=swap" rel="stylesheet">';
    expect(
      check('<code style="font:14px ui-monospace,monospace">x</code>', head: fonts).single.why,
      contains('ui-monospace is not loaded from Google Fonts'),
    );
    expect(
      check("<code style=\"font:14px/1.4 'JetBrains Mono',monospace\">x</code>", head: fonts),
      isEmpty,
    );
    // Filters: drop-shadow on the element converts; behind it, it does not.
    expect(check('<img style="filter:drop-shadow(0 4px 8px #000) saturate(2)">'), isEmpty);
    expect(
      check('<div style="backdrop-filter:blur(4px) drop-shadow(0 4px 8px #000)"></div>')
          .single
          .what,
      startsWith('backdrop-filter'),
    );
    // Centering with a grid of one cell, and fixed columns, convert.
    expect(check('<div style="display:grid;place-items:center"><b>x</b></div>'), isEmpty);
    expect(
      check('<div style="display:grid;grid-template-columns:repeat(3, 1fr);gap:8px"></div>'),
      isEmpty,
    );
    expect(check('<div style="float:left;transform:skew(10deg)"></div>').map((i) => i.what), [
      'float: left',
      'transform: skew(10deg)',
    ]);
    // A style block may only switch classes by width.
    expect(
      check('', css: '@media (max-width: 720px) { .hide-sm { display: none !important; } }'),
      isEmpty,
    );
    expect(check('', css: 'p { color: red; }').single.selector, 'style');
    // Agents are told the same, when they design.
    expect(helmyIdentity, contains(subsetForAgents));
  });

  test('a picture is as large as its file says, read from its header', () {
    List<int> file(String name) => File('test/fixtures/design/img/$name').readAsBytesSync();
    expect(imageSize(file('design.jpg')), (160.0, 107.0));
    expect(imageSize(file('hello.png')), isNotNull);
    expect(imageSize(file('claude.svg')), isNotNull);
    expect(imageSize(const [1, 2, 3]), isNull);
  });

  test('a percentage is a share of what it is said to be of', () {
    expect(length('80%'), isNull);
    expect(length('80%', percentOf: 'b')?.code, 'b * 0.8');
    expect(length('min(300px,80%)', percentOf: 'b')?.code, 'math.min(300.0, b * 0.8)');
    expect(hasPercent('min(300px,80%)'), isTrue);
    expect(hasPercent('clamp(20px,5vw,64px)'), isFalse);
  });

  test(
    'Flutter: shares of the line, pictures in proportion, margins that follow the screen',
    () async {
      final out = Directory.systemTemp.createTempSync('flutter_export');
      addTearDown(() => out.deleteSync(recursive: true));
      await exportDesign(
        'test/fixtures/design',
        out.path,
        ExportTarget.flutterPlain,
        fetch: (_) async => null,
      );
      String read(String p) => File('${out.path}/$p').readAsStringSync();
      final all = [
        for (final f in Directory('${out.path}/lib').listSync(recursive: true))
          if (f is File) f.readAsStringSync(),
      ].join('\n');
      // width:100% on a picture, min(300px, 80%) on the phone's frame (its
      // 10px borders added, as its width is its content's).
      expect(all, contains('width: (b) => b * 1.0'));
      expect(all, contains('width: (b) => math.min(300.0, b * 0.8) + 20.0'));
      // Each picture's own size, so it is laid out before it has loaded.
      expect(read('lib/ui/core/design.dart'), contains('"assets/img/design.jpg": (160.0, 107.0)'));
      // margin-top: clamp(32px, 4vw, 48px).
      expect(all, contains('SizedBox(height: (vw(context, 4.0)).clamp(32.0, 48.0))'));
    },
  );

  test('Flutter: text, layers, filters and fonts drawn as the page draws them', () async {
    final out = Directory.systemTemp.createTempSync('flutter_exact');
    addTearDown(() => out.deleteSync(recursive: true));
    final asked = <String>[];
    // Google Fonts' CSS, Google's font sources and their files, stood in for.
    Future<List<int>?> fetch(Uri url) async {
      asked.add(url.toString());
      if (url.host == 'fonts.googleapis.com') {
        String face(String family, int weight) =>
            "@font-face { font-family: '$family'; font-weight: $weight; src: url(https://fonts.gstatic.com/${family.replaceAll(' ', '')}$weight.ttf) format('truetype'); }";
        return utf8.encode(
          [
            face('Bricolage Grotesque', 700),
            face('Bricolage Grotesque', 800),
            face('Inter', 400),
          ].join('\n'),
        );
      }
      if (url.host == 'api.github.com') {
        return url.path.endsWith('/ofl/bricolagegrotesque')
            ? utf8.encode(
                jsonEncode([
                  {
                    'name': 'BricolageGrotesque[opsz,wdth,wght].ttf',
                    'download_url': 'https://raw.example/var.ttf',
                  },
                ]),
              )
            : null;
      }
      return [0, 1, 0, 0];
    }

    await exportDesign('test/fixtures/design', out.path, ExportTarget.flutterPlain, fetch: fetch);
    String read(String p) => File('${out.path}/$p').readAsStringSync();
    final all = [
      for (final f in Directory('${out.path}/lib').listSync(recursive: true))
        if (f is File) f.readAsStringSync(),
    ].join('\n');
    // The code as written, whatever the formatter's line breaks.
    final flat = all.replaceAll(RegExp(r'\s+'), '');
    Matcher has(String code) =>
        predicate<String>((_) => flat.contains(code.replaceAll(RegExp(r'\s+'), '')), 'has $code');

    // Asked for with an optical size, Bricolage is its variable font, one file
    // under each weight, its size and weight set on each text; Inter, asked
    // for by weight only, stays a file per weight.
    expect(asked, contains('https://raw.example/var.ttf'));
    expect(read('pubspec.yaml'), contains('assets/fonts/Bricolage_Grotesque-variable.ttf'));
    expect(
      'assets/fonts/Bricolage_Grotesque-variable.ttf'.allMatches(read('pubspec.yaml')),
      hasLength(2),
    );
    expect(read('pubspec.yaml'), contains('assets/fonts/Inter-400.ttf'));
    expect(all, has("FontVariation('opsz', (vw(context, 4.4)).clamp(32.0, 56.0))"));
    // Text in CssText, which places each line where the page does.
    expect(all, has('CssText(TextSpan('));
    expect(all, isNot(has('Text.rich(')));
    // A component's text cased as the page cases it.
    expect(all, has('text.toUpperCase()'));
    // The sticky header pinned over the page as it scrolls.
    expect(read('lib/ui/home/widgets/home_screen.dart'), contains('PinnedHeaderSliver('));
    // The hero's -64px margin passes through main: main is pulled up, not the hero in it.
    expect(all, has('Margin(top: -64.0'));
    // Hidden below 720px: out of the row, its gap with it.
    expect(all, has('if (MediaQuery.sizeOf(context).width > 720.0)'));
    // Filters: a drop-shadow under the astronaut, a backdrop saturated after its blur.
    expect(all, has('DropShadow(offset: Offset(0.0, 24.0), sigma: 24.0'));
    expect(all, has('ui.ImageFilter.compose('));
    // A one-column grid as wide as what will not wrap in it.
    expect(all, has('GridTrack(child: Column('));
  });

  test('Flutter on Ashlar: links and buttons the size the design draws them', () async {
    final d = await readDesign('test/fixtures/design');
    final out = writeFlutter(planDesign(title: d.title, screens: d.screens));
    expect(out.files['lib/main.dart'], contains('tapTarget: 0,'));
    expect(out.files['lib/main.dart'], contains('darkTheme: designTheme(),'));
  });

  test('one screen exports on its own, as the web and as code', () async {
    final out = Directory.systemTemp.createTempSync('one_screen');
    addTearDown(() => out.deleteSync(recursive: true));
    await exportDesign(
      'test/fixtures/design',
      '${out.path}/web',
      ExportTarget.web,
      only: {'download.html'},
    );
    expect(File('${out.path}/web/download.html').existsSync(), isTrue);
    expect(File('${out.path}/web/index.html').existsSync(), isFalse);
    final react = await exportDesign(
      'test/fixtures/design',
      '${out.path}/react',
      ExportTarget.react,
      only: {'download.html'},
    );
    expect(react.where((f) => f.contains('/screens/')).map((f) => f.split('/')[2]).toSet(), {
      'Download',
    });
  });
}
