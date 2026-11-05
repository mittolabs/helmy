import '../../data/services/watch_service.dart' show Frame;

/// What a screen's widgets may do with a file or an address, given them by
/// the screen's view model, so no widget reaches a service itself.
abstract interface class FileActions {
  /// Opens [where] (a file or a web address) in its own app.
  Future<void> open(String where);

  /// Shows [path] in the file manager.
  Future<void> reveal(String path);
}

/// What the conversation's widgets (pictures, players, documents, pages) may
/// do besides: preview beside the conversation, copy a picture, and the
/// pictures made of a document or a video.
abstract interface class MediaActions implements FileActions {
  /// Opens [url] in the Preview panel beside the conversation.
  void preview(String url);

  /// Puts the picture at [path] on the clipboard; false when it could not.
  Future<bool> copyImage(String path);

  /// A picture of a document's first page, where this computer can make one.
  Future<String?> documentPicture(String path);

  /// A rich text document's words, as plain text; null where they cannot be read.
  Future<String?> documentText(String path);

  /// [count] small frames along the video at [path], for its bar.
  Future<List<Frame>> frames(String path, {int count, int width});
}
