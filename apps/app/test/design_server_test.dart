import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/design_server.dart';

void main() {
  test('a design file is served only from inside its folder', () {
    expect(DesignServer.fileIn('/d', 'welcome.html')?.path, '/d/welcome.html');
    expect(DesignServer.fileIn('/d', 'img/hero.png')?.path, '/d/img/hero.png');
    for (final bad in ['../secret', 'a/../../b', '', '/etc/passwd', 'a//b', './x', r'a\..\b']) {
      expect(DesignServer.fileIn('/d', bad), isNull, reason: bad);
    }
  });
}
