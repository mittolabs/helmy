/// The state of a folder's files at one moment, taken with git without
/// touching them: `git stash create` makes a commit of the working tree that
/// no branch, index or stash list ever sees. Files git does not track yet are
/// not in that commit, so their contents are stored as git objects of their
/// own (`git hash-object -w`), by path.
class const Snapshot({required final String sha, required final Map<String, String> untracked}) {
  Map<String, Object?> toJson() => {'sha': sha, 'untracked': untracked};

  static Snapshot? fromJson(Object? json) => json is Map && json['sha'] is String
      ? Snapshot(
          sha: json['sha']! as String,
          untracked: {
            for (final e in ((json['untracked'] as Map?) ?? const {}).entries)
              '${e.key}': '${e.value}',
          },
        )
      : null;
}

/// A file changed since a snapshot.
typedef FileChange = ({String path, int added, int removed, String kind});
