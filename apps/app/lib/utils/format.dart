import 'dart:io';

/// `/Users/me/code/app` as `~/code/app`.
String tildePath(String path) {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty || !path.startsWith(home)) return path;
  return '~${path.substring(home.length)}';
}

/// The last folder of a path.
String folderName(String path) => path.split('/').where((p) => p.isNotEmpty).lastOrNull ?? path;

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
