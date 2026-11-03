import 'dart:io';

/// What an empty session offers to start with: things that are true of its
/// folder, read without asking a model.
typedef Starter = ({String label, String prompt});

/// What is known of a folder, as far as starting suggestions go.
typedef FolderFacts = ({bool git, int uncommitted, int recentCommits});

/// Suggestions for a folder with [facts]: only ones that hold for it.
List<Starter> startersFor(FolderFacts facts) => [
  if (facts.git && facts.uncommitted > 0)
    (
      label:
          'Review my uncommitted changes (${facts.uncommitted} '
          'file${facts.uncommitted == 1 ? '' : 's'})',
      prompt: 'Review my uncommitted changes. Point out bugs and anything I should fix before committing.',
    ),
  if (facts.git && facts.recentCommits > 0)
    (
      label: 'Summarize this week\'s commits (${facts.recentCommits})',
      prompt: 'Summarize what changed in the commits from the last 7 days.',
    ),
  if (facts.git)
    (
      label: 'Explain how this codebase is organized',
      prompt: 'Explain how this codebase is organized: the main parts and how they fit together.',
    )
  else
    (label: 'What is in this folder?', prompt: 'What is in this folder? Give me a short overview.'),
];

/// Reads [cwd] with git: whether it is a repository, how many files have
/// changes not yet committed, and how many commits the last 7 days had.
Future<FolderFacts> readFolderFacts(String cwd) async {
  Future<String?> git(List<String> args) async {
    try {
      final r = await Process.run('git', ['-C', cwd, ...args]);
      return r.exitCode == 0 ? '${r.stdout}' : null;
    } on Object {
      return null;
    }
  }

  final inside = await git(['rev-parse', '--is-inside-work-tree']);
  if (inside?.trim() != 'true') return (git: false, uncommitted: 0, recentCommits: 0);
  final (status, log) = await (
    git(['status', '--porcelain']),
    git(['log', '--since=7.days', '--oneline']),
  ).wait;
  int lines(String? s) => s == null ? 0 : s.split('\n').where((l) => l.trim().isNotEmpty).length;
  return (git: true, uncommitted: lines(status), recentCommits: lines(log));
}
