// Tests for Attachment. Copied into your app by `ashlar add attachment` with the component: they
// check what it promises, so change them as you change it.
import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/attachment.dart';
import 'package:helmy/ui/core/ashlar/spinner.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    AshlarApp(
      builder: (context, page) =>
          Directionality(textDirection: direction, child: page!),
      home: child,
    );

void main() {
  group('Attachment', () {
    testWidgets('says how it is getting on, to the eye and the ear', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Attachment(
                  title: 'report.pdf',
                  description: '2.4 MB',
                  state: AttachmentState.uploading,
                ),
                Attachment(
                  title: 'photo.jpg',
                  description: 'Too large to send.',
                  state: AttachmentState.error,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(Spinner), findsOneWidget);
      expect(
        find.bySemanticsLabel('report.pdf, 2.4 MB, uploading'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('photo.jpg, Too large to send., failed'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('opens when pressed; its actions work on their own', (
      tester,
    ) async {
      var opened = 0, removed = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          Center(
            child: Attachment(
              title: 'notes.txt',
              onPressed: () => opened++,
              actions: [
                AttachmentAction(
                  icon: AshlarIconsRoundedStroke.x,
                  label: 'Remove',
                  onPressed: () => removed++,
                ),
              ],
            ),
          ),
        ),
      );
      // The name lets the press through to the card under it.
      await tester.tap(find.text('notes.txt'), warnIfMissed: false);
      await tester.tap(find.bySemanticsLabel('Remove'));
      expect((opened, removed), (1, 1));
      semantics.dispose();
    });

    testWidgets('a group scrolls sideways rather than overflowing', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          SizedBox(
            width: 300,
            child: AttachmentGroup(
              children: [
                for (var i = 0; i < 6; i++) Attachment(title: 'file-$i.pdf'),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsOneWidget);
    });
  });
}
