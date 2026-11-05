import 'dart:convert';

import 'engine.dart';
import 'permission_rule.dart';
import 'project_action.dart';

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

/// What draws pages in Preview: the system's own web view, or a Chromium
/// browser on this computer (for Chrome's developer tools).
enum PreviewEngine { system, chromium }

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

/// The colors changes are shown in: people see colors differently.
enum DiffColors {
  greenRed('Green and red'),
  blueOrange('Blue and orange (for color blindness)'),
  none('Without color');

  const DiffColors(this.label);
  final String label;
}

/// What is set for one project (a git repository, by its top folder), over
/// the settings for everything. Null means "as everywhere else".
class const ProjectSettings({
  /// Each session on its own branch, in its own working copy (a git
  /// worktree), so sessions in one repository do not collide.
  final bool? ownCopies,

  /// What Helmy may do without asking, in sessions here.
  final PermissionLevel? level,

  /// Actions the user added, beside those found in the project's files.
  final List<ProjectAction> actions = const [],
}) {
  ProjectSettings copyWith({
    bool? ownCopies,
    PermissionLevel? level,
    List<ProjectAction>? actions,
  }) => ProjectSettings(
    ownCopies: ownCopies ?? this.ownCopies,
    level: level ?? this.level,
    actions: actions ?? this.actions,
  );

  Map<String, Object?> toJson() => {
    'ownCopies': ?ownCopies,
    'level': ?level?.id,
    if (actions.isNotEmpty) 'actions': [for (final a in actions) a.toJson()],
  };

  static ProjectSettings fromJson(Map<String, Object?> json) => ProjectSettings(
    ownCopies: json['ownCopies'] as bool?,
    level: json['level'] == null ? null : PermissionLevel.fromId(json['level'] as String?),
    actions: [
      for (final a in (json['actions'] as List?) ?? const [])
        if (a is Map) ProjectAction.fromJson(a.cast<String, Object?>()),
    ],
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

  /// How wide the sidebar is, as last dragged.
  final double sidebarWidth = 272,
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

  /// Ask before a chat is deleted.
  final bool confirmDelete = true,

  /// A chat settles by itself when its pull request merges, or after three
  /// days untouched.
  final bool settleOnItsOwn = true,

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

  /// What draws pages in Preview.
  final PreviewEngine previewWith = .system,

  /// The Chromium browser Preview uses, by its program; null lets Helmy pick
  /// one of those installed.
  final String? chromiumBrowser,

  /// The app projects open in, by bundle id, as last chosen; null lets
  /// Helmy pick the editor used most recently.
  final String? editor,

  /// Each project's default branch brought up to date when its checkout is
  /// on it with nothing of its own (fast-forward only).
  final bool keepDefaultCurrent = true,

  /// The colors changes are shown in.
  final DiffColors diffColors = .greenRed,

  /// Changes only in spaces and tabs shown as unchanged.
  final bool diffHideSpace = false,

  /// Both Shift keys, in any app, snapshot the window in front into the
  /// message being written. Off until turned on: macOS must allow it.
  final bool snapshotKeys = false,

  /// The one-time review of grouping earlier threads into chats is done.
  final bool groupingReviewed = false,
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
    double? sidebarWidth,
    List<PermissionRule>? rules,
    String? ollamaModel,
    bool? wrapCode,
    Recency? recency,
    bool? keepRunning,
    bool? sendWithEnter,
    bool? stepsOpen,
    PreviewEngine? previewWith,
    String? chromiumBrowser,
    String? editor,
    bool? keepDefaultCurrent,
    DiffColors? diffColors,
    bool? diffHideSpace,
    bool? snapshotKeys,
    bool? groupingReviewed,
    bool? confirmDelete,
    bool? settleOnItsOwn,
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
    sidebarWidth: sidebarWidth ?? this.sidebarWidth,
    rules: rules ?? this.rules,
    ollamaModel: ollamaModel ?? this.ollamaModel,
    wrapCode: wrapCode ?? this.wrapCode,
    recency: recency ?? this.recency,
    keepRunning: keepRunning ?? this.keepRunning,
    sendWithEnter: sendWithEnter ?? this.sendWithEnter,
    stepsOpen: stepsOpen ?? this.stepsOpen,
    previewWith: previewWith ?? this.previewWith,
    chromiumBrowser: chromiumBrowser ?? this.chromiumBrowser,
    editor: editor ?? this.editor,
    keepDefaultCurrent: keepDefaultCurrent ?? this.keepDefaultCurrent,
    diffColors: diffColors ?? this.diffColors,
    diffHideSpace: diffHideSpace ?? this.diffHideSpace,
    snapshotKeys: snapshotKeys ?? this.snapshotKeys,
    groupingReviewed: groupingReviewed ?? this.groupingReviewed,
    confirmDelete: confirmDelete ?? this.confirmDelete,
    settleOnItsOwn: settleOnItsOwn ?? this.settleOnItsOwn,
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
    'sidebarWidth': sidebarWidth,
    'rules': [for (final r in rules) r.toJson()],
    'ollamaModel': ollamaModel,
    'wrapCode': wrapCode,
    'recency': recency.name,
    'keepRunning': keepRunning,
    'sendWithEnter': sendWithEnter,
    'stepsOpen': stepsOpen,
    'previewWith': previewWith.name,
    'chromiumBrowser': chromiumBrowser,
    'editor': editor,
    'keepDefaultCurrent': keepDefaultCurrent,
    'diffColors': diffColors.name,
    'diffHideSpace': diffHideSpace,
    'snapshotKeys': snapshotKeys,
    'groupingReviewed': groupingReviewed,
    'confirmDelete': confirmDelete,
    'settleOnItsOwn': settleOnItsOwn,
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
    sidebarWidth: (json['sidebarWidth'] as num?)?.toDouble() ?? 272,
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
    previewWith: PreviewEngine.values.asNameMap()[json['previewWith']] ?? .system,
    chromiumBrowser: json['chromiumBrowser'] as String?,
    editor: json['editor'] as String?,
    keepDefaultCurrent: json['keepDefaultCurrent'] as bool? ?? true,
    diffColors: DiffColors.values.asNameMap()[json['diffColors']] ?? .greenRed,
    diffHideSpace: json['diffHideSpace'] as bool? ?? false,
    snapshotKeys: json['snapshotKeys'] as bool? ?? false,
    groupingReviewed: json['groupingReviewed'] as bool? ?? false,
    confirmDelete: json['confirmDelete'] as bool? ?? true,
    settleOnItsOwn: json['settleOnItsOwn'] as bool? ?? true,
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

/// The settings a person chooses, by the names Settings shows them under,
/// with the fields each covers. What restoring the defaults puts back; not
/// connections, projects, rules or the window's layout, which are what was
/// set up rather than chosen.
const restorableSettings = <String, List<String>>{
  'Theme': ['theme'],
  'Text size': ['textSize'],
  'Conversation width': ['width'],
  'Wrap long code blocks': ['wrapCode'],
  'Colors for changes': ['diffColors'],
  'Hide changes only in spaces': ['diffHideSpace'],
  'Snapshots with both Shift keys': ['snapshotKeys'],
  'When a chat needs you or finishes': ['notify'],
  'Keep chats working when the window closes': ['keepRunning'],
  'Send with': ['sendWithEnter'],
  'Each thread on its own branch': ['ownCopies'],
  'Keep default branches current': ['keepDefaultCurrent'],
  'Send error reports': ['sendErrors'],
  'Show steps open': ['stepsOpen'],
  'Ask before deleting a chat': ['confirmDelete'],
  'Mark chats done on their own': ['settleOnItsOwn'],
  'Permissions': ['defaultLevel'],
  'Start in': ['folderMode', 'fixedFolder'],
  'Move to an agent with more room': ['switching'],
  'Show pages with': ['previewWith'],
  'Chromium browser': ['chromiumBrowser'],
  'Editor projects open in': ['editor'],
  'Chat list': ['show', 'group', 'sort', 'recency'],
};

/// The names of the settings in [s] that differ from Helmy's own, in the
/// order Settings shows them.
List<String> changedSettings(AppSettings s) {
  final now = s.toJson();
  final defaults = const AppSettings().toJson();
  return [
    for (final MapEntry(key: label, value: fields) in restorableSettings.entries)
      if (fields.any((f) => jsonEncode(now[f]) != jsonEncode(defaults[f]))) label,
  ];
}

/// [s] with the settings named in [labels] (all that changed when null) as
/// Helmy has them, everything else kept.
AppSettings withDefaults(AppSettings s, [Iterable<String>? labels]) {
  final json = s.toJson();
  final defaults = const AppSettings().toJson();
  for (final label in labels ?? changedSettings(s)) {
    for (final f in restorableSettings[label] ?? const <String>[]) {
      json[f] = defaults[f];
    }
  }
  return AppSettings.fromJson(jsonDecode(jsonEncode(json)) as Map<String, Object?>);
}
