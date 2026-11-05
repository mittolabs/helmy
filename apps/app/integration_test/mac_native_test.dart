// Helmy's Mac actions through its own Swift side, in the real app, with
// nothing changed (no lock, no key pressed, nothing quit or ejected):
// fvm flutter test integration_test/mac_native_test.dart -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/mac/mac_actions.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('outputs, apps and drives come from the Mac side', (tester) async {
    final mac = MacActions();
    await tester.runAsync(() async {
      final outputs = await mac.outputs();
      // ignore: avoid_print
      print('outputs: $outputs');
      expect(outputs, isNotEmpty);
      expect(outputs.where((o) => o.current), hasLength(1));
      // ignore: avoid_print
      print(await mac.sound());
      final apps = await mac.apps();
      // ignore: avoid_print
      print(apps);
      expect(apps, contains('Finder'));
      // ignore: avoid_print
      print(await mac.drives());
      // Quitting something not open says so, and quits nothing.
      await expectLater(mac.quit('No Such App Here'), throwsA(isA<MacTrouble>()));
    });
  });
}
