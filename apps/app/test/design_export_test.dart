import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/design_export/export.dart';
import 'package:helmy/domain/design_export/planner.dart';
import 'package:helmy/domain/design_export/react_writer.dart';
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
    final again = planDesign(title: d.title, screens: (await readDesign('test/fixtures/design')).screens);

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
    expect(files.keys, containsAll(['src/screens/Download/Download.tsx', 'src/components/SiteFooter.tsx', 'src/theme.css']));
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
    final react = await exportDesign('test/fixtures/design', '${out.path}/react', ExportTarget.react);
    expect(react, containsAll(['package.json', 'index.html', 'src/main.tsx', 'public/img/icon.png']));
    expect(File('${out.path}/react/src/screens/Download/Download.tsx').readAsStringSync(), contains('↗'));
  });
}
