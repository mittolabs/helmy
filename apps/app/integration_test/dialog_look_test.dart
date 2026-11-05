// A look at Helmy's dialog and its compact answers, on this Mac:
// fvm flutter test integration_test/dialog_look_test.dart -d macos --dart-define=SHOTS=<dir>
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/helmy_dialog.dart';
import 'package:integration_test/integration_test.dart';

import 'support/shot.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a question with compact answers', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 2;
    await tester.pumpWidget(
      shootable(
        AshlarApp(
          theme: themeFor(Brightness.dark),
          darkTheme: themeFor(Brightness.dark),
          home: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => confirm(
                  context,
                  title: 'Put earlier threads together?',
                  body:
                      'Before chats, each conversation stood alone. Nothing moves that you untick.',
                  action: 'Put 22 together',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final button = tester.getSize(find.text('Put 22 together').hitTestable());
    expect(button.height, lessThan(24));
    final pressable = tester.getSize(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(AnimatedContainer)).first,
    );
    expect(pressable.height, lessThanOrEqualTo(32));
    if (shots.isNotEmpty) await shot(tester, '$shots/dialog.png');
  });
}
