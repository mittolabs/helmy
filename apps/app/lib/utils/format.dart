import 'platform.dart';

/// `/Users/me/code/app` as `~/code/app`.
String tildePath(String path) {
  final home = homeDir;
  if (home.isEmpty || !path.startsWith(home)) return path;
  return '~${path.substring(home.length)}';
}

/// The last folder of a path, with / or Windows' \ between its parts.
String folderName(String path) =>
    path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).lastOrNull ?? path;

/// "now", "5m", "3h", "2d", then a date: how long ago something was used.
String ago(DateTime then, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(then);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[then.month - 1]} ${then.day}';
}

/// Where sessions started without a project keep their folders (one each,
/// Helmy's own); set once at startup.
String? scratchRoot;

/// Whether [path] is a folder of a session started without a project.
bool isScratch(String path) => scratchRoot != null && path.startsWith('$scratchRoot/');

/// A session folder's name as shown: "No project" for one of Helmy's own.
String projectName(String path) => isScratch(path) ? 'No project' : folderName(path);

/// The end of a path, which tells folders apart: `cadence/videos` for
/// `/Users/me/Downloads/cadence/videos`, the home folder as `~`.
String pathEnd(String path) {
  final parts = tildePath(path).split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
  return parts.length <= 2 ? parts.join('/') : parts.sublist(parts.length - 2).join('/');
}
