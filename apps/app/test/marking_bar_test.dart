import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/widgets/page_marking.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';

void main() {
  testWidgets('the marking bar fits a narrow panel and a wide one', (tester) async {
    final marking = PageMarking((
      run: (_) async {},
      picture: (_) async => null,
      title: () async => '',
      url: () => '',
    ));
    for (final width in [280.0, 360.0, 600.0]) {
      await tester.pumpWidget(
        AshlarApp(
          theme: appTheme,
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: MarkingBar(marking: marking, onAdd: () {}, onDone: () {}),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'no overflow at $width');
    }
  });
}
