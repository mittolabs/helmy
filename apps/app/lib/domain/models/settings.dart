import 'dart:convert';

import 'engine.dart';
import 'permission_rule.dart';
import 'project_action.dart';
import 'work.dart';

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

/// The colors Helmy is drawn in, light and dark alike: its own (pure black
/// when dark), or one of the warmer or cooler greys.
enum Palette {
  helmy('Helmy'),
  stone('Stone'),
  taupe('Taupe'),
  olive('Olive'),
  mauve('Mauve'),
  mist('Mist'),
  zinc('Zinc'),

  /// A VS Code theme the user brought in ([AppSettings.themeImport]).
  imported('Imported');

  const Palette(this.label);
  final String label;
}

/// A color for the main buttons and what is chosen; none keeps them grey.
enum AccentChoice { none, blue, teal, emerald, amber, orange, rose, violet }

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

/// How a chat that finishes or needs you is told, when not on screen.
enum AlertStyle {
  both('A notification with a sound'),
  banner('A notification only'),
  sound('A sound only');

  const AlertStyle(this.label);
  final String label;
}

/// Where a search typed in the Preview panel's address goes.
enum SearchEngine {
  duckDuckGo('DuckDuckGo', 'https://duckduckgo.com/?q=%s'),
  google('Google', 'https://www.google.com/search?q=%s'),
  bing('Bing', 'https://www.bing.com/search?q=%s'),
  brave('Brave Search', 'https://search.brave.com/search?q=%s'),
  kagi('Kagi', 'https://kagi.com/search?q=%s'),
  ecosia('Ecosia', 'https://www.ecosia.org/search?q=%s');

  const SearchEngine(this.label, this.url);
  final String label;

  /// With %s where the words go.
  final String url;
}

/// How clock times read.
enum ClockFormat {
  system('As the system has it'),
  twelve('1:05 PM'),
  twentyFour('13:05');

  const ClockFormat(this.label);
  final String label;
}

/// How wide the conversation reads.
enum Width {
  narrow('Narrow', 640),
  medium('Medium', 720),
  wide('Wide', 920),
  full('Full', double.infinity);

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

  /// Whether the assistant may use its browser here; null as everywhere
  /// (it may).
  final bool? browser,

  /// An emoji the project goes by in the list; empty for none.
  final String icon = '',

  /// Pinned: its chats come first when the list is grouped by folder.
  final bool pinned = false,
}) {
  ProjectSettings copyWith({
    bool? ownCopies,
    PermissionLevel? level,
    List<ProjectAction>? actions,
    bool? browser,
    String? icon,
    bool? pinned,
  }) => ProjectSettings(
    ownCopies: ownCopies ?? this.ownCopies,
    level: level ?? this.level,
    actions: actions ?? this.actions,
    browser: browser ?? this.browser,
    icon: icon ?? this.icon,
    pinned: pinned ?? this.pinned,
  );

  Map<String, Object?> toJson() => {
    'ownCopies': ?ownCopies,
    'level': ?level?.id,
    if (actions.isNotEmpty) 'actions': [for (final a in actions) a.toJson()],
    'browser': ?browser,
    if (icon.isNotEmpty) 'icon': icon,
    if (pinned) 'pinned': true,
  };

  static ProjectSettings fromJson(Map<String, Object?> json) => ProjectSettings(
    ownCopies: json['ownCopies'] as bool?,
    level: json['level'] == null ? null : PermissionLevel.fromId(json['level'] as String?),
    actions: [
      for (final a in (json['actions'] as List?) ?? const [])
        if (a is Map) ProjectAction.fromJson(a.cast<String, Object?>()),
    ],
    browser: json['browser'] as bool?,
    icon: json['icon'] as String? ?? '',
    pinned: json['pinned'] as bool? ?? false,
  );
}

/// A connection added in Settings: another Claude Code or Codex account,
/// signed in to a folder of its own (CLAUDE_CONFIG_DIR or CODEX_HOME), or an
/// agent that speaks the Agent Client Protocol (kind 'acp').
class const ConnectionAccount({
  /// The engine id: 'claude-work', 'codex-personal'.
  final String id = '',

  /// 'claude' or 'codex'.
  final String kind = 'claude',

  /// The name the user gave it.
  final String name = '',

  /// Where its sign-in lives.
  final String folder = '',

  /// Helmy made the folder (a browser sign-in, an agent it installed), so
  /// removing the account removes it; a folder the user pointed at is only
  /// forgotten.
  final bool made = false,

  /// For an agent ('acp'): the program and what it is started with.
  final String? command,
  final List<String> args = const [],

  /// For an agent from the ACP registry: its id there, and its icon.
  final String? agentId,
  final String? icon,
}) {
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'folder': folder,
    'made': made,
    'command': ?command,
    if (args.isNotEmpty) 'args': args,
    'agentId': ?agentId,
    'icon': ?icon,
  };

  static ConnectionAccount fromJson(Map<String, Object?> json) => ConnectionAccount(
    id: json['id'] as String? ?? '',
    kind: json['kind'] as String? ?? 'claude',
    name: json['name'] as String? ?? '',
    folder: json['folder'] as String? ?? '',
    made: json['made'] as bool? ?? false,
    command: json['command'] as String?,
    args: [...((json['args'] as List?) ?? const []).map((a) => '$a')],
    agentId: json['agentId'] as String?,
    icon: json['icon'] as String?,
  );
}

/// Everything the user can set, kept in one file.
class const AppSettings({
  final PermissionLevel defaultLevel = .ask,
  final FolderMode folderMode = .last,
  final String? fixedFolder,
  final Set<String> disabledEngines = const {},

  /// Fonts chosen in Appearance, by family; null is the system's own.
  final String? interfaceFont,
  final String? codeFont,
  final String? promptFont,

  /// How much firmer borders and quiet text are: 0 as designed, up to 1.
  final double contrast = 0,

  /// How a notification comes, and whether one shows inside Helmy when it
  /// is in front.
  final AlertStyle alertStyle = .both,
  final bool inAppNotices = true,

  /// While chats work, ⌘Q quits on a second press, not the first.
  final bool quitTwice = true,

  /// Days untouched before a chat settles by itself.
  final int settleDays = 3,

  /// A chat with an open pull request is not done: it does not settle.
  final bool keepWithPr = true,

  /// What the user wants of chats' names, added to how Helmy names them.
  final String namingNote = '',

  /// How commits and pull requests are written: 'repository' (its own
  /// way), 'conventional', or 'custom' with [commitNote].
  final String commitStyle = 'repository',
  final String commitNote = '',

  /// Changes always in one column, rather than side by side where there is
  /// room; and each file's change open from the start.
  final bool diffStacked = false,
  final bool diffFilesOpen = false,

  /// Threads' own copies: branch names by kind of change (fix/, feat/) or
  /// after [copyPrefix]; started from the remote's default branch or from
  /// the checkout; kept in [copyFolder] (null: ~/.helmy/worktrees); and
  /// tidied away once their chat settles.
  final bool copySemantic = true,
  final String copyPrefix = 'helmy/',
  final bool copyFromRemote = false,
  final String? copyFolder,
  final bool tidySettled = false,

  /// The Preview panel as it starts: its zoom and the light or dark pages
  /// see ('system', 'light', 'dark'); where searches go; and whether links
  /// in answers open there rather than in the browser.
  final double previewZoom = 1,
  final String previewAppearance = 'system',
  final SearchEngine searchEngine = .duckDuckGo,
  final bool linksInHelmy = false,

  /// Another shortcut that takes a snapshot, beside both Shift keys, as
  /// `KeyBinding.saved` writes it; empty for none.
  final String snapshotKey = '',

  /// A snapshot taken: a sound ('Pop', 'Tink', or '' for none) and a flash.
  final String snapshotSound = 'Pop',
  final bool snapshotFlash = true,

  /// Chats at work when Helmy closed carry on when it opens again.
  final bool carryOnAfterRestart = true,

  /// A VS Code theme brought in, as `importedThemeToJson` writes it.
  final Map<String, Object?>? themeImport,

  /// Programs pointed at by hand, by name ('claude', 'codex'), for when
  /// Helmy cannot find them.
  final Map<String, String> programs = const {},

  /// Whether the assistant may use the simulators, emulators and phones in
  /// the Device panel.
  final bool agentDevices = true,

  /// Secrets webhook senders sign events with, by thread: where one is set,
  /// unsigned events are turned away.
  final Map<String, String> hookSigning = const {},

  /// Keys the user chose for commands, by command name, as
  /// `KeyBinding.saved` writes them; the rest keep Helmy's own.
  final Map<String, String> keys = const {},

  /// A message sent while a chat works redirects it at once, rather than
  /// waiting its turn; ⇧⌘Enter does the other.
  final bool steerByDefault = false,
  final ClockFormat clock = .system,

  /// Accounts added beside the usual Claude Code and Codex ones.
  final List<ConnectionAccount> accounts = const [],

  /// The user's choice of which kind of connection is best at a kind of
  /// work, by the kind's name: 'claude', 'codex', or 'any'. Kinds not here
  /// keep Mittolabs's choice ([defaultBestAt]).
  final Map<String, String> bestAt = const {},
  final Switching switching = .balanced,
  final bool notify = true,
  final ThemeChoice theme = .system,

  /// The colors, light and dark alike.
  final Palette palette = .helmy,

  /// A color for the main buttons and what is chosen.
  final AccentChoice accent = .none,
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

  /// A paired phone can reach Helmy here.
  final bool remoteOn = false,

  /// The key phones pair with (see `Pairing`); empty before the first.
  final String remoteKey = '',

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
  /// The kind of connection best at [kind]: the user's choice, else
  /// Mittolabs's; null for any.
  String? bestFor(WorkKind kind) => switch (bestAt[kind.name]) {
    'any' => null,
    final String family => family,
    null => defaultBestAt[kind],
  };

  ProjectSettings project(String repo) => projects[repo] ?? const ProjectSettings();

  /// The project [folder] is in, by its settings: the one whose folder holds
  /// it; empty settings when none does.
  ProjectSettings projectAt(String folder) {
    for (final e in projects.entries) {
      if (folder == e.key || folder.startsWith('${e.key}/')) return e.value;
    }
    return const ProjectSettings();
  }

  /// Whether the assistant may use its browser in [folder]: no where a
  /// project it is in says so.
  bool browserIn(String folder) {
    for (final e in projects.entries) {
      if ((folder == e.key || folder.startsWith('${e.key}/')) && e.value.browser == false) {
        return false;
      }
    }
    return true;
  }

  /// Whether sessions in [repo] each get their own working copy.
  bool ownCopiesIn(String repo) => project(repo).ownCopies ?? ownCopies;

  AppSettings copyWith({
    PermissionLevel? defaultLevel,
    FolderMode? folderMode,
    String? fixedFolder,
    Set<String>? disabledEngines,
    List<ConnectionAccount>? accounts,
    String? interfaceFont,
    String? codeFont,
    String? promptFont,
    double? contrast,
    AlertStyle? alertStyle,
    bool? inAppNotices,
    bool? quitTwice,
    int? settleDays,
    bool? keepWithPr,
    String? namingNote,
    bool? steerByDefault,
    Map<String, String>? keys,
    String? commitStyle,
    Map<String, String>? hookSigning,
    Map<String, String>? programs,
    bool? agentDevices,
    Map<String, Object?>? themeImport,
    bool? carryOnAfterRestart,
    String? snapshotSound,
    String? snapshotKey,
    bool? snapshotFlash,
    double? previewZoom,
    String? previewAppearance,
    SearchEngine? searchEngine,
    bool? linksInHelmy,
    bool? copySemantic,
    String? copyPrefix,
    bool? copyFromRemote,
    String? copyFolder,
    bool? tidySettled,
    String? commitNote,
    bool? diffStacked,
    bool? diffFilesOpen,
    ClockFormat? clock,
    Map<String, String>? bestAt,
    Switching? switching,
    bool? notify,
    ThemeChoice? theme,
    Palette? palette,
    AccentChoice? accent,
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
    bool? remoteOn,
    String? remoteKey,
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
    accounts: accounts ?? this.accounts,
    interfaceFont: interfaceFont == '' ? null : interfaceFont ?? this.interfaceFont,
    codeFont: codeFont == '' ? null : codeFont ?? this.codeFont,
    promptFont: promptFont == '' ? null : promptFont ?? this.promptFont,
    contrast: contrast ?? this.contrast,
    alertStyle: alertStyle ?? this.alertStyle,
    inAppNotices: inAppNotices ?? this.inAppNotices,
    quitTwice: quitTwice ?? this.quitTwice,
    settleDays: settleDays ?? this.settleDays,
    keepWithPr: keepWithPr ?? this.keepWithPr,
    namingNote: namingNote ?? this.namingNote,
    steerByDefault: steerByDefault ?? this.steerByDefault,
    keys: keys ?? this.keys,
    commitStyle: commitStyle ?? this.commitStyle,
    hookSigning: hookSigning ?? this.hookSigning,
    programs: programs ?? this.programs,
    agentDevices: agentDevices ?? this.agentDevices,
    themeImport: themeImport ?? this.themeImport,
    carryOnAfterRestart: carryOnAfterRestart ?? this.carryOnAfterRestart,
    snapshotSound: snapshotSound ?? this.snapshotSound,
    snapshotKey: snapshotKey ?? this.snapshotKey,
    snapshotFlash: snapshotFlash ?? this.snapshotFlash,
    previewZoom: previewZoom ?? this.previewZoom,
    previewAppearance: previewAppearance ?? this.previewAppearance,
    searchEngine: searchEngine ?? this.searchEngine,
    linksInHelmy: linksInHelmy ?? this.linksInHelmy,
    copySemantic: copySemantic ?? this.copySemantic,
    copyPrefix: copyPrefix ?? this.copyPrefix,
    copyFromRemote: copyFromRemote ?? this.copyFromRemote,
    copyFolder: copyFolder == '' ? null : copyFolder ?? this.copyFolder,
    tidySettled: tidySettled ?? this.tidySettled,
    commitNote: commitNote ?? this.commitNote,
    diffStacked: diffStacked ?? this.diffStacked,
    diffFilesOpen: diffFilesOpen ?? this.diffFilesOpen,
    clock: clock ?? this.clock,
    bestAt: bestAt ?? this.bestAt,
    switching: switching ?? this.switching,
    notify: notify ?? this.notify,
    theme: theme ?? this.theme,
    palette: palette ?? this.palette,
    accent: accent ?? this.accent,
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
    remoteOn: remoteOn ?? this.remoteOn,
    remoteKey: remoteKey ?? this.remoteKey,
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
    if (accounts.isNotEmpty) 'accounts': [for (final a in accounts) a.toJson()],
    'bestAt': bestAt,
    'interfaceFont': interfaceFont,
    'codeFont': codeFont,
    'promptFont': promptFont,
    'contrast': contrast,
    'alertStyle': alertStyle.name,
    'inAppNotices': inAppNotices,
    'quitTwice': quitTwice,
    'settleDays': settleDays,
    'keepWithPr': keepWithPr,
    'namingNote': namingNote,
    'steerByDefault': steerByDefault,
    'keys': keys,
    'commitStyle': commitStyle,
    'hookSigning': hookSigning,
    'programs': programs,
    'agentDevices': agentDevices,
    'themeImport': themeImport,
    'carryOnAfterRestart': carryOnAfterRestart,
    'snapshotSound': snapshotSound,
    'snapshotKey': snapshotKey,
    'snapshotFlash': snapshotFlash,
    'previewZoom': previewZoom,
    'previewAppearance': previewAppearance,
    'searchEngine': searchEngine.name,
    'linksInHelmy': linksInHelmy,
    'copySemantic': copySemantic,
    'copyPrefix': copyPrefix,
    'copyFromRemote': copyFromRemote,
    'copyFolder': copyFolder,
    'tidySettled': tidySettled,
    'commitNote': commitNote,
    'diffStacked': diffStacked,
    'diffFilesOpen': diffFilesOpen,
    'clock': clock.name,
    'switching': switching.name,
    'notify': notify,
    'theme': theme.name,
    'palette': palette.name,
    'accent': accent.name,
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
    'remoteOn': remoteOn,
    'remoteKey': remoteKey,
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
    interfaceFont: json['interfaceFont'] as String?,
    codeFont: json['codeFont'] as String?,
    promptFont: json['promptFont'] as String?,
    contrast: (json['contrast'] as num?)?.toDouble() ?? 0,
    alertStyle: AlertStyle.values.asNameMap()[json['alertStyle']] ?? .both,
    inAppNotices: json['inAppNotices'] as bool? ?? true,
    quitTwice: json['quitTwice'] as bool? ?? true,
    settleDays: (json['settleDays'] as num?)?.toInt() ?? 3,
    keepWithPr: json['keepWithPr'] as bool? ?? true,
    namingNote: json['namingNote'] as String? ?? '',
    steerByDefault: json['steerByDefault'] as bool? ?? false,
    keys: {for (final e in ((json['keys'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
    commitStyle: json['commitStyle'] as String? ?? 'repository',
    hookSigning: {
      for (final e in ((json['hookSigning'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
    },
    programs: {
      for (final e in ((json['programs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
    },
    agentDevices: json['agentDevices'] as bool? ?? true,
    themeImport: (json['themeImport'] as Map?)?.cast<String, Object?>(),
    carryOnAfterRestart: json['carryOnAfterRestart'] as bool? ?? true,
    snapshotSound: json['snapshotSound'] as String? ?? 'Pop',
    snapshotKey: json['snapshotKey'] as String? ?? '',
    snapshotFlash: json['snapshotFlash'] as bool? ?? true,
    previewZoom: (json['previewZoom'] as num?)?.toDouble() ?? 1,
    previewAppearance: json['previewAppearance'] as String? ?? 'system',
    searchEngine: SearchEngine.values.asNameMap()[json['searchEngine']] ?? .duckDuckGo,
    linksInHelmy: json['linksInHelmy'] as bool? ?? false,
    copySemantic: json['copySemantic'] as bool? ?? true,
    copyPrefix: json['copyPrefix'] as String? ?? 'helmy/',
    copyFromRemote: json['copyFromRemote'] as bool? ?? false,
    copyFolder: json['copyFolder'] as String?,
    tidySettled: json['tidySettled'] as bool? ?? false,
    commitNote: json['commitNote'] as String? ?? '',
    diffStacked: json['diffStacked'] as bool? ?? false,
    diffFilesOpen: json['diffFilesOpen'] as bool? ?? false,
    clock: ClockFormat.values.asNameMap()[json['clock']] ?? .system,
    bestAt: {
      for (final e in ((json['bestAt'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
    },
    accounts: [
      for (final a in (json['accounts'] as List?) ?? const [])
        if (a is Map) ConnectionAccount.fromJson(a.cast<String, Object?>()),
    ],
    switching: Switching.values.asNameMap()[json['switching']] ?? .balanced,
    notify: json['notify'] as bool? ?? true,
    theme: ThemeChoice.values.asNameMap()[json['theme']] ?? .system,
    palette: Palette.values.asNameMap()[json['palette']] ?? .helmy,
    accent: AccentChoice.values.asNameMap()[json['accent']] ?? .none,
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
    remoteOn: json['remoteOn'] as bool? ?? false,
    remoteKey: json['remoteKey'] as String? ?? '',
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
  'Mark chats done on their own': ['settleOnItsOwn', 'settleDays'],
  'Keep chats with an open pull request': ['keepWithPr'],
  'How chats are named': ['namingNote'],
  'A message sent while a chat works': ['steerByDefault'],
  'Shortcuts': ['keys'],
  'Commits and pull requests': ['commitStyle', 'commitNote'],
  'Branch names': ['copySemantic', 'copyPrefix'],
  'Zoom': ['previewZoom'],
  'The assistant uses devices': ['agentDevices'],
  'Carry on after a restart': ['carryOnAfterRestart'],
  'When a snapshot is taken': ['snapshotSound', 'snapshotFlash'],
  'Pages appear': ['previewAppearance'],
  'Search with': ['searchEngine'],
  'Open links in answers': ['linksInHelmy'],
  'Start copies from': ['copyFromRemote'],
  'Where copies are kept': ['copyFolder'],
  'Tidy away copies of settled chats': ['tidySettled'],
  'Changes in one column': ['diffStacked'],
  "Each file's change open": ['diffFilesOpen'],
  'Reach Helmy from your phone': ['remoteOn'],
  'Permissions': ['defaultLevel'],
  'Start in': ['folderMode', 'fixedFolder'],
  'Move to an agent with more room': ['switching'],
  'Show pages with': ['previewWith'],
  'Chromium browser': ['chromiumBrowser'],
  'Editor projects open in': ['editor'],
  'Chat list': ['show', 'group', 'sort', 'recency'],
  'Best at': ['bestAt'],
  'Interface font': ['interfaceFont'],
  'Code font': ['codeFont'],
  'Message font': ['promptFont'],
  'Contrast': ['contrast'],
  'Time format': ['clock'],
  'How it tells you': ['alertStyle'],
  'Notices inside Helmy': ['inAppNotices'],
  'Quit on a second press while chats work': ['quitTwice'],
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
