import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/error_reports.dart';
import 'package:helmy/utils/platform.dart';
import 'package:sentry/sentry.dart';

void main() {
  test('a report has no path in the home, no user and no machine name', () {
    final event = SentryEvent(
      exceptions: [
        SentryException(
          type: 'FileSystemException',
          value: 'Cannot open file, path = $homeDir/Projects/secret/plan.txt',
          stackTrace: SentryStackTrace(
            frames: [SentryStackFrame(absPath: '$homeDir/code/helmy/lib/main.dart', lineNo: 3)],
          ),
        ),
      ],
      message: SentryMessage('failed in $homeDir/Downloads'),
      user: SentryUser(id: 'someone', email: 'someone@helmy.test'),
      serverName: 'Someones-MacBook',
    );
    final out = ErrorReports.scrub(event);
    final all = [
      out.exceptions!.single.value,
      out.exceptions!.single.stackTrace!.frames.single.absPath,
      out.message!.formatted,
    ].join(' ');
    expect(all, isNot(contains(homeDir)));
    expect(all, contains('~/Projects/secret/plan.txt'));
    expect(out.user, isNull);
    expect(out.serverName, isNull);
    expect(ErrorReports.configured, isFalse, reason: 'tests are built with no address');
  });
}
