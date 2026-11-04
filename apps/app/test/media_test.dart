import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/domain/folder_move.dart';
import 'package:helmy/ui/chat/widgets/media.dart';
import 'package:helmy/ui/core/ashlar/app.dart';
import 'package:helmy/ui/core/ashlar/app_theme.dart';
import 'package:helmy/ui/core/ashlar/markdown.dart';
import 'package:provider/provider.dart';

void main() {
  test('a folder line is found, taken out, and hidden while it is still arriving', () {
    const answer = 'Moved.\nHELMY_FOLDER: /Users/someone/Mittolabs\n';
    expect(folderMoveIn(answer), '/Users/someone/Mittolabs');
    expect(withoutFolderLines(answer), 'Moved.');
    expect(folderMoveIn('Nothing to move.'), isNull);
    expect(withoutFolderLines('Moved.\nHELMY_FO', streaming: true), 'Moved.');
    expect(withoutFolderLines('Moved.\nHe said', streaming: true), 'Moved.\nHe said');
    expect(
      withoutFolderLines('Moved.\nHELMY_FO'),
      'Moved.\nHELMY_FO',
      reason: 'only while streaming',
    );
  });

  test('what a shown thing is, and where it lives', () {
    expect(kindOf('/a/dolly.PNG'), MediaKind.image);
    expect(kindOf('~/clip.mov'), MediaKind.video);
    expect(kindOf('song.m4a'), MediaKind.audio);
    expect(kindOf('/a/report.pdf'), MediaKind.document);
    expect(kindOf('/a/plan.docx'), MediaKind.quickLook);
    expect(kindOf('http://localhost:3000'), MediaKind.page);
    expect(kindOf('https://example.com/cat.jpg?w=200'), MediaKind.image);
    expect(kindOf('/a/notes'), isNull);
    final home = Platform.environment['HOME'];
    expect(locate('~/x.png', '/w').path, '$home/x.png');
    expect(locate('art/x.png', '/w').path, '/w/art/x.png');
    expect(locate('file:///a/my%20file.png', '/w').path, '/a/my file.png');
    expect(locate('https://example.com', '/w').web, Uri.parse('https://example.com'));
  });

  testWidgets('an answer shows a picture, says when a file is missing, and offers a page', (
    tester,
  ) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('media');
      // A 1x1 PNG.
      await File('${dir.path}/my dot.png').writeAsBytes(const [
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, //
        8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 15, //
        4, 0, 9, 251, 3, 253, 227, 85, 242, 156, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130,
      ]);
    });
    final previewed = <String>[];
    await tester.pumpWidget(
      Provider(
        create: (_) => DesktopService(),
        child: AshlarApp(
          theme: appTheme,
          darkTheme: appDarkTheme,
          home: MarkdownMedia(
            show: (where, words) =>
                Media(where: where, words: words, cwd: dir.path, onPreview: previewed.add),
            child: Markdown(
              'Here it is:\n\n![a dot](${dir.path}/my dot.png)\n\n'
              '![the old one](${dir.path}/gone.png)\n\n'
              '![your app](http://localhost:3000)',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('a dot'), findsOneWidget);
    expect(find.textContaining('Not found: the old one'), findsOneWidget);
    expect(find.text('your app'), findsOneWidget);
    await tester.tap(find.text('Open beside'));
    expect(previewed, ['http://localhost:3000']);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
}
