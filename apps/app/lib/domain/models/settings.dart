import 'engine.dart';
import 'permission_rule.dart';

/// Where a new session starts.
enum FolderMode { last, fixed }

/// How readily Helmy moves a session to an engine with more room.
enum Switching {
  rarely('Rarely', .30),
  balanced('Balanced', .15),
  eagerly('Eagerly', .05);

  const Switching(this.label, this.margin);
  final String label;

  /// How much more room another engine needs before a switch is worth a handoff.
  final double margin;
}

enum ThemeChoice { system, light, dark }

/// How large text is, as a scale on the theme's sizes.
enum TextSize {
  small('Small', .92),
  medium('Medium', 1),
  large('Large', 1.12);

  const TextSize(this.label, this.scale);
  final String label;
  final double scale;
}

/// How wide the conversation reads.
enum Width {
  narrow('Narrow', 640),
  medium('Medium', 720),
  wide('Wide', 920);

  const Width(this.label, this.pixels);
  final String label;
  final double pixels;
}

/// Which sessions the sidebar lists, and how.
enum ShowSessions { active, archived, all }

enum GroupSessions { none, folder }

/// How recently a session must have been used to be listed.
enum Recency {
  all(null),
  today(Duration(days: 1)),
  week(Duration(days: 7)),
  month(Duration(days: 30));

  const Recency(this.within);
  final Duration? within;
}

enum SortSessions { recent, name }

/// What is set for one project (a git repository, by its top folder), over
/// the settings for everything. Null means "as everywhere else".
class const ProjectSettings({
  /// Each session on its own branch, in its own working copy (a git
  /// worktree), so sessions in one repository do not collide.
  final bool? ownCopies,

  /// What Helmy may do without asking, in sessions here.
  final PermissionLevel? level,
}) {
  ProjectSettings copyWith({bool? ownCopies, PermissionLevel? level}) =>
      ProjectSettings(ownCopies: ownCopies ?? this.ownCopies, level: level ?? this.level);

  Map<String, Object?> toJson() => {'ownCopies': ?ownCopies, 'level': ?level?.id};

  static ProjectSettings fromJson(Map<String, Object?> json) => ProjectSettings(
    ownCopies: json['ownCopies'] as bool?,
    level: json['level'] == null ? null : PermissionLevel.fromId(json['level'] as String?),
  );
}

/// Everything the user can set, kept in one file.
class const AppSettings({
  final PermissionLevel defaultLevel = .ask,
  final FolderMode folderMode = .last,
  final String? fixedFolder,
  final Set<String> disabledEngines = const {},
  final Switching switching = .balanced,
  final bool notify = true,
  final ThemeChoice theme = .system,
  final TextSize textSize = .medium,
  final Width width = .medium,
  final ShowSessions show = .active,
  final GroupSessions group = .none,
  final SortSessions sort = .recent,
  final bool sidebarOpen = true,
  final List<PermissionRule> rules = const [],
  final String? ollamaModel,
  final bool wrapCode = false,
  final Recency recency = .all,

  /// Closing the window hides it and sessions keep working, until Quit.
  final bool keepRunning = true,

  /// Send with Enter (Shift+Enter for a new line), or with ⌘Enter.
  final bool sendWithEnter = true,

  /// Steps start open to show what went in and came out.
  final bool stepsOpen = false,

  /// Ask before a session is deleted.
  final bool confirmDelete = true,

  /// Each session in a git repository on its own branch, in its own working
  /// copy, unless the project says otherwise.
  final bool ownCopies = false,

  /// Per project, by the repository's top folder.
  final Map<String, ProjectSettings> projects = const {},

  /// Send reports of Helmy's own errors and crashes to Mittolabs, with no
  /// conversation, file or path in them.
  final bool sendErrors = true,

  /// First-run setup has been finished or skipped.
  final bool setupDone = false,
}) {
  /// The settings for the project at [repo] (a repository's top folder).
  ProjectSettings project(String repo) => projects[repo] ?? const ProjectSettings();

  /// Whether sessions in [repo] each get their own working copy.
  bool ownCopiesIn(String repo) => project(repo).ownCopies ?? ownCopies;

  AppSettings copyWith({
    PermissionLevel? defaultLevel,
    FolderMode? folderMode,
    String? fixedFolder,
    Set<String>? disabledEngines,
    Switching? switching,
    bool? notify,
    ThemeChoice? theme,
    TextSize? textSize,
    Width? width,
    ShowSessions? show,
    GroupSessions? group,
    SortSessions? sort,
    bool? sidebarOpen,
    List<PermissionRule>? rules,
    String? ollamaModel,
    bool? wrapCode,
    Recency? recency,
    bool? keepRunning,
    bool? sendWithEnter,
    bool? stepsOpen,
    bool? confirmDelete,
    bool? ownCopies,
    Map<String, ProjectSettings>? projects,
    bool? sendErrors,
    bool? setupDone,
  }) => AppSettings(
    defaultLevel: defaultLevel ?? this.defaultLevel,
    folderMode: folderMode ?? this.folderMode,
    fixedFolder: fixedFolder ?? this.fixedFolder,
    disabledEngines: disabledEngines ?? this.disabledEngines,
    switching: switching ?? this.switching,
    notify: notify ?? this.notify,
    theme: theme ?? this.theme,
    textSize: textSize ?? this.textSize,
    width: width ?? this.width,
    show: show ?? this.show,
    group: group ?? this.group,
    sort: sort ?? this.sort,
    sidebarOpen: sidebarOpen ?? this.sidebarOpen,
    rules: rules ?? this.rules,
    ollamaModel: ollamaModel ?? this.ollamaModel,
    wrapCode: wrapCode ?? this.wrapCode,
    recency: recency ?? this.recency,
    keepRunning: keepRunning ?? this.keepRunning,
    sendWithEnter: sendWithEnter ?? this.sendWithEnter,
    stepsOpen: stepsOpen ?? this.stepsOpen,
    confirmDelete: confirmDelete ?? this.confirmDelete,
    ownCopies: ownCopies ?? this.ownCopies,
    projects: projects ?? this.projects,
    sendErrors: sendErrors ?? this.sendErrors,
    setupDone: setupDone ?? this.setupDone,
  );

  Map<String, Object?> toJson() => {
    'defaultLevel': defaultLevel.id,
    'folderMode': folderMode.name,
    'fixedFolder': fixedFolder,
    'disabledEngines': disabledEngines.toList(),
    'switching': switching.name,
    'notify': notify,
    'theme': theme.name,
    'textSize': textSize.name,
    'width': width.name,
    'show': show.name,
    'group': group.name,
    'sort': sort.name,
    'sidebarOpen': sidebarOpen,
    'rules': [for (final r in rules) r.toJson()],
    'ollamaModel': ollamaModel,
    'wrapCode': wrapCode,
    'recency': recency.name,
    'keepRunning': keepRunning,
    'sendWithEnter': sendWithEnter,
    'stepsOpen': stepsOpen,
    'confirmDelete': confirmDelete,
    'ownCopies': ownCopies,
    'projects': {for (final e in projects.entries) e.key: e.value.toJson()},
    'sendErrors': sendErrors,
    'setupDone': setupDone,
  };

  static AppSettings fromJson(Map<String, Object?> json) => AppSettings(
    defaultLevel: PermissionLevel.fromId(json['defaultLevel'] as String?),
    folderMode: FolderMode.values.asNameMap()[json['folderMode']] ?? .last,
    fixedFolder: json['fixedFolder'] as String?,
    disabledEngines: {...((json['disabledEngines'] as List?) ?? const []).whereType<String>()},
    switching: Switching.values.asNameMap()[json['switching']] ?? .balanced,
    notify: json['notify'] as bool? ?? true,
    theme: ThemeChoice.values.asNameMap()[json['theme']] ?? .system,
    textSize: TextSize.values.asNameMap()[json['textSize']] ?? .medium,
    width: Width.values.asNameMap()[json['width']] ?? .medium,
    show: ShowSessions.values.asNameMap()[json['show']] ?? .active,
    group: GroupSessions.values.asNameMap()[json['group']] ?? .none,
    sort: SortSessions.values.asNameMap()[json['sort']] ?? .recent,
    sidebarOpen: json['sidebarOpen'] as bool? ?? true,
    rules: [
      for (final r in (json['rules'] as List? ?? const []).whereType<Map>())
        PermissionRule.fromJson(r.cast()),
    ],
    ollamaModel: json['ollamaModel'] as String?,
    wrapCode: json['wrapCode'] as bool? ?? false,
    recency: Recency.values.asNameMap()[json['recency']] ?? .all,
    keepRunning: json['keepRunning'] as bool? ?? true,
    sendWithEnter: json['sendWithEnter'] as bool? ?? true,
    stepsOpen: json['stepsOpen'] as bool? ?? false,
    confirmDelete: json['confirmDelete'] as bool? ?? true,
    ownCopies: json['ownCopies'] as bool? ?? false,
    projects: {
      for (final e in ((json['projects'] as Map?) ?? const {}).entries)
        '${e.key}': ProjectSettings.fromJson((e.value as Map).cast()),
    },
    sendErrors: json['sendErrors'] as bool? ?? true,
    // Someone who used Helmy before setup existed has set it up already.
    setupDone: json['setupDone'] as bool? ?? json.containsKey('disabledEngines'),
  );
}
