import 'package:flutter_test/flutter_test.dart';
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
  });
}
