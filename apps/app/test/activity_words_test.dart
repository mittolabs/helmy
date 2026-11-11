import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/activity_words.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';

void main() {
  test('source searches mentioning tests are not reported as test executions', () {
    expect(commandActivity("rg -n 'flutter test|dart test' lib").done, 'Searched the files');
    expect(commandActivity("sed -n '1,80p' test/editor_test.dart").done, 'Read file contents');
  });

  test('fallback labels name the editor checks and test subjects', () {
    expect(
      specificCommandLabel(
        'rg getLocalRectForCaret numbered_code_input.dart; rg hasUnsavedEdits files_panel.dart',
        done: true,
      ),
      'Inspected line-number alignment and unsaved-edit protection',
    );
    expect(
      specificCommandLabel(
        'flutter test test/file_document_test.dart test/file_editor_test.dart',
        done: true,
        result: '+8: All tests passed!',
      ),
      'Passed 8 checks for file document and file editor',
    );
  });

  test('known activities describe the work; arbitrary scripts stay generic', () {
    expect(commandActivity('flutter test test/example_test.dart').done, 'Ran tests');
    expect(commandActivity('flutter build macos --debug').action, 'Build the app');
    expect(commandActivity('ps -axo pid,comm | rg Helmy.app').done, 'Checked the installation');
    expect(commandActivity('python3 unknown.py').done, 'Ran a script');
    expect(commandActivity('write_text helmy-relaunch Popen').action, 'Prepare Helmy to reopen');
  });

  test('internal connection addresses never become automatic previews', () {
    for (final url in [
      'http://localhost:11434/',
      'http://127.0.0.1:59871/mcp/example?session=example',
      'http://localhost:9222/json',
      'http://localhost:8080/hooks/example',
    ]) {
      expect(isInternalConnectionUrl(url), isTrue, reason: url);
      expect(localServerInText('Listening at $url'), isNull, reason: url);
    }
    expect(
      localServerInText('App http://localhost:3000/\nTransport http://localhost:11434/'),
      'http://localhost:3000/',
    );
    expect(localServerInText('Listening on http://0.0.0.0:5173/'), 'http://localhost:5173/');
    expect(isInternalConnectionUrl('https://example.com/mcp/docs'), isFalse);
  });
}
