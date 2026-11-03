// Tests for Input Group. Copied into your app by `ashlar add input-group` with the component: they
// check what it promises, so change them as you change it.
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/input.dart';
import 'package:helmy/ui/core/ashlar/input_group.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child) => AshlarApp(home: Center(child: child));

void main() {
  testWidgets(
    'an input group puts its pieces in one border and rings it when the field has focus',
    (tester) async {
      await tester.pumpWidget(
        app(
          const SizedBox(
            width: 320,
            child: InputGroup(
              start: Text('https://'),
              end: Text('.com'),
              child: Input(decorated: false, placeholder: 'example'),
            ),
          ),
        ),
      );
      BoxDecoration group() =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .descendant(
                          of: find.byType(InputGroup),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      expect(group().boxShadow!.any((s) => s.spreadRadius == 3), isFalse);
      // The field inside draws no box of its own.
      final inner = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byType(Input), matching: find.byType(AnimatedContainer)).first,
      );
      expect(inner.decoration, isNull);
      await tester.tap(find.byType(Input));
      await tester.pumpAndSettle();
      expect(group().boxShadow!.any((s) => s.spreadRadius == 3), isTrue);
      expect(
        tester.getRect(find.text('https://')).right,
        lessThan(tester.getRect(find.byType(Input)).left + 1),
      );
    },
  );
}
