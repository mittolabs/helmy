import 'package:helmy/data/services/desktop_service.dart';
import 'package:helmy/data/services/watch_service.dart';
import 'package:helmy/ui/core/file_actions.dart';

/// Media actions for tests: what was opened, revealed and previewed is
/// recorded; pictures of documents and videos come from the real services
/// when given (on macOS, in integration tests), and none otherwise.
class TestMediaActions implements MediaActions {
  TestMediaActions({this.desktop, this.watch});
  final DesktopService? desktop;
  final WatchService? watch;

  final opened = <String>[];
  final revealed = <String>[];
  final previewed = <String>[];

  @override
  Future<void> open(String where) async => opened.add(where);

  @override
  Future<void> reveal(String path) async => revealed.add(path);

  @override
  void preview(String url) => previewed.add(url);

  @override
  Future<bool> copyImage(String path) async => false;

  @override
  Future<String?> documentPicture(String path) async => desktop?.documentPicture(path);

  @override
  Future<List<Frame>> frames(String path, {int count = 40, int width = 240}) async =>
      await watch?.frames(path, count: count, width: width) ?? const [];
}
