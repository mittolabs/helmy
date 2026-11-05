// Drives what only a Mac has.
@TestOn('mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/man_pages.dart';

// Shaped like macOS's own pages: overstruck bold, options set in by five.
const _page =
    'LS(1)        General Commands Manual        LS(1)\n'
    '\n'
    'N\bNA\bAM\bME\bE\n'
    '     ls – list directory\n'
    '     contents\n'
    '\n'
    'D\bDE\bES\bSC\bCR\bRI\bIP\bPT\bTI\bIO\bON\bN\n'
    '     The following options are available:\n'
    '\n'
    '     -\b-a\ba      Include directory entries whose names begin with a dot.\n'
    '             Shown by default for the super-user.  More text here.\n'
    '\n'
    '     -n, --lines=count\n'
    '             Print count lines.\n';

void main() {
  test('the manual says what a program is and what its flags do', () {
    final page = plainMan(_page);
    expect(nameLine(page), 'list directory contents');
    expect(
      flagHelp(page, '-a'),
      'Include directory entries whose names begin with a dot. Shown by default for the super-user.',
    );
    expect(flagHelp(page, '--lines'), 'Print count lines.');
    expect(flagHelp(page, '-n'), 'Print count lines.');
    expect(flagHelp(page, '-z'), isNull);
  });

  test("this Mac's own pages explain a command", () async {
    if (!File('/usr/bin/man').existsSync()) return;
    final parts = await explainFromManual('cd /tmp && ls -la | head -n 3');
    final byText = {for (final p in parts) p.text: p};
    expect(byText['cd']!.help, 'change the working directory');
    expect(byText['ls']!.help, 'list directory contents');
    expect(byText['-l']!.help, contains('long format'));
    expect(byText['-a']!.help, contains('dot'));
    expect(byText['head']!.program, isTrue);
  });
}
