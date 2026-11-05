import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/models/settings.dart';
import 'package:helmy/ui/chat/widgets/preview_panel.dart';

void main() {
  test('what is typed in the address goes somewhere sensible', () {
    expect(addressFor('https://example.com/a'), 'https://example.com/a');
    expect(addressFor('file:///tmp/a.html'), 'file:///tmp/a.html');
    expect(addressFor('localhost:3000'), 'http://localhost:3000');
    expect(addressFor('127.0.0.1:8080/x'), 'http://127.0.0.1:8080/x');
    expect(addressFor('example.com'), 'https://example.com');
    expect(addressFor('docs.flutter.dev/ui'), 'https://docs.flutter.dev/ui');
    expect(addressFor('how to center a div'), 'https://duckduckgo.com/?q=how+to+center+a+div');
    expect(addressFor('lisbon in march', .kagi), 'https://kagi.com/search?q=lisbon+in+march');
  });

  test('the browser is off in a project that says so, and in its folders', () {
    const s = AppSettings(projects: {'/w/site': ProjectSettings(browser: false)});
    expect(s.browserIn('/w/site'), isFalse);
    expect(s.browserIn('/w/site/docs'), isFalse);
    expect(s.browserIn('/w/sitemap'), isTrue);
    expect(s.browserIn('/w/other'), isTrue);
    const back = AppSettings(previewZoom: 1.25, previewAppearance: 'dark', linksInHelmy: true);
    final read = AppSettings.fromJson(back.toJson());
    expect((read.previewZoom, read.previewAppearance, read.linksInHelmy), (1.25, 'dark', true));
    expect(AppSettings.fromJson(s.toJson()).project('/w/site').browser, isFalse);
  });
}
