import 'dart:io';

/// Pictures the engines take as images; anything else is named by its path for
/// the agent to read itself.
const imageTypes = {
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
};

/// The image type of [path], or null when it is not a picture an engine takes
/// whole. Pictures over 5MB are named by path too: the APIs refuse bigger ones.
String? imageType(String path) {
  final type = imageTypes[path.split('.').last.toLowerCase()];
  if (type == null) return null;
  final file = File(path);
  if (!file.existsSync() || file.lengthSync() > 5 * 1024 * 1024) return null;
  return type;
}

/// The text to send with [files] the engine does not take as images.
String withFiles(String text, List<String> files) => files.isEmpty
    ? text
    : '$text\n\nAttached files (read them from disk):\n${files.map((f) => '- $f').join('\n')}';
