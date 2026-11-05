import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/identity.dart';

/// How commits and pull requests are written goes with Helmy's instructions,
/// only when chosen.
void main() {
  tearDown(() => writingStyle = '');

  test("the repository's own way adds nothing; a chosen one is said", () {
    expect(writingStyleFor('repository', 'ignored'), isEmpty);
    expect(identityWith(null), helmyIdentity);
    writingStyle = writingStyleFor('conventional', '');
    expect(identityWith(null), contains('Conventional Commits: type(scope): subject'));
    writingStyle = writingStyleFor('custom', '  Subjects under 50 characters. ');
    expect(
      identityWith('Decided: ship Friday'),
      allOf(
        contains(
          'How the user wants commit messages and pull requests written: Subjects under 50 characters.',
        ),
        endsWith('Decided: ship Friday'),
      ),
    );
    expect(helmyIdentity, contains('pull request template, fill it in'));
  });
}
