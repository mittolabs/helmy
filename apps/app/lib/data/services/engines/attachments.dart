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

/// The text to send with [files] the engine does not take as images, and
/// where [pictures] it does take are on disk: real files, so an agent can
/// use them (put one in a pull request, say), not only see them.
String withFiles(String text, List<String> files, {List<String> pictures = const []}) => [
  text,
  if (files.isNotEmpty)
    'Attached files (read them from disk):\n${files.map((f) => '- $f').join('\n')}',
  if (pictures.isNotEmpty)
    'The attached pictures are also on disk, to use the files themselves:\n'
        '${pictures.map((f) => '- $f').join('\n')}',
].join('\n\n');

/// Where Helmy keeps what is pasted or captured into a message: a folder that
/// lasts, unlike the system's temporary one, so an agent can use the files
/// later in the conversation too.
Directory attachmentsDir() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return Directory('$home/.helmy/attachments')..createSync(recursive: true);
}
