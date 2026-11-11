import 'settings_view_model.dart';

/// One thing Settings can be searched for: a setting, or a part of a page.
/// [title] is the row's or heading's title as the page draws it, which is
/// how the page finds it to scroll to; [keywords] are other words people
/// use for it.
typedef SettingEntry = ({String title, SettingsSection section, String keywords});

/// Everything in Settings, page by page, in the pages' order.
const List<SettingEntry> settingsIndex = [
  // General.
  (
    title: 'When a chat needs you or finishes',
    section: .general,
    keywords: 'notifications alerts badge sound done finished approval',
  ),
  (title: 'How it tells you', section: .general, keywords: 'notification sound banner alert quiet'),
  (title: 'Notices inside Helmy', section: .general, keywords: 'toast in-app notice popup'),
  (
    title: 'Quit on a second press while chats work',
    section: .general,
    keywords: 'quit confirm close command q twice hold',
  ),
  (
    title: 'Carry on after a restart',
    section: .general,
    keywords: 'resume restart crash update continue',
  ),
  (
    title: 'Keep chats working when the window closes',
    section: .general,
    keywords: 'background quit close window dock keep running',
  ),
  (
    title: 'Send with',
    section: .general,
    keywords: 'enter return shift new line keyboard send shortcut',
  ),
  (
    title: 'Each thread on its own branch',
    section: .general,
    keywords: 'worktree branch copy git parallel',
  ),
  (
    title: 'Keep default branches current',
    section: .general,
    keywords: 'pull fetch main git update automatically',
  ),
  (title: 'Send error reports', section: .general, keywords: 'crash bugs diagnostics privacy'),
  (
    title: 'Show steps open',
    section: .general,
    keywords: 'tools commands expanded collapsed details',
  ),
  (title: 'Open at login', section: .general, keywords: 'startup launch boot start automatically'),
  (title: 'Ask before deleting a chat', section: .general, keywords: 'confirm confirmation delete'),
  (title: 'Keep chats with an open pull request', section: .general, keywords: 'pr settle done'),
  (
    title: 'A message sent while a chat works',
    section: .general,
    keywords: 'queue steer follow up redirect interrupt',
  ),
  (
    title: 'Format as you type',
    section: .general,
    keywords: 'markdown rich text bold italic composer',
  ),
  (title: 'How chats are named', section: .general, keywords: 'names titles naming instructions'),
  (
    title: 'Mark chats done on their own',
    section: .general,
    keywords: 'settle settled done inactive automatically archive',
  ),
  (title: 'Start in', section: .general, keywords: 'folder new chat project directory where'),
  (
    title: 'Snapshots with both Shift keys',
    section: .general,
    keywords: 'screenshot capture window shortcut snap',
  ),
  // Appearance.
  (title: 'Theme', section: .appearance, keywords: 'dark light mode system color scheme'),
  (title: 'Colors', section: .appearance, keywords: 'palette theme stone mist colours'),
  (
    title: 'A theme from VS Code',
    section: .appearance,
    keywords: 'import vscode theme json colors dracula nord',
  ),
  (title: 'Accent', section: .appearance, keywords: 'color highlight buttons blue rose'),
  (title: 'Interface font', section: .appearance, keywords: 'font family typeface type'),
  (title: 'Code font', section: .appearance, keywords: 'monospace mono font code terminal'),
  (title: 'Message font', section: .appearance, keywords: 'prompt composer typing font'),
  (title: 'Contrast', section: .appearance, keywords: 'contrast borders accessibility readable'),
  (title: 'Time format', section: .appearance, keywords: 'clock 24 hour 12 hour am pm time'),
  (title: 'Text size', section: .appearance, keywords: 'font bigger smaller zoom scale'),
  (title: 'Conversation width', section: .appearance, keywords: 'chat width wide layout column'),
  (title: 'Wrap long code blocks', section: .appearance, keywords: 'word wrap lines code'),
  (
    title: 'Colors for changes',
    section: .appearance,
    keywords: 'diff red green blue orange colorblind',
  ),
  (
    title: 'Changes in one column',
    section: .appearance,
    keywords: 'diff split stacked unified side by side',
  ),
  (
    title: "Each file's change open",
    section: .appearance,
    keywords: 'diff expanded collapsed files',
  ),
  (title: 'Icon and pin', section: .projects, keywords: 'project emoji icon pin first'),
  (title: 'Branch names', section: .projects, keywords: 'worktree branch prefix semantic feat fix'),
  (title: 'Start copies from', section: .projects, keywords: 'worktree remote origin base'),
  (title: 'Where copies are kept', section: .projects, keywords: 'worktree folder location path'),
  (
    title: 'Tidy away copies of settled chats',
    section: .projects,
    keywords: 'worktree cleanup delete remove clean',
  ),
  (
    title: 'Commits and pull requests',
    section: .projects,
    keywords: 'commit message conventional style writing pr template',
  ),
  (title: 'Hide changes only in spaces', section: .appearance, keywords: 'whitespace diff ignore'),
  // Preview panel.
  (title: 'Show pages with', section: .preview, keywords: 'browser webkit chromium preview engine'),
  (title: 'Zoom', section: .preview, keywords: 'preview zoom scale size page'),
  (
    title: 'Pages appear',
    section: .preview,
    keywords: 'preview dark light appearance color scheme',
  ),
  (
    title: 'Search with',
    section: .preview,
    keywords: 'search engine google duckduckgo bing brave kagi',
  ),
  (
    title: 'Open links in answers',
    section: .preview,
    keywords: 'links browser preview open target',
  ),
  (
    title: 'Profile',
    section: .preview,
    keywords: 'browser profile sign in cookies accounts work personal',
  ),
  (title: 'Chromium browser', section: .preview, keywords: 'chrome edge brave arc browser'),
  // Connections.
  (
    title: 'Connections',
    section: .agents,
    keywords: 'claude code codex ollama accounts sign in update version',
  ),
  // Usage.
  (title: 'How much is left', section: .usage, keywords: 'usage limits quota room left reset'),
  (
    title: 'Move to a connection with more room',
    section: .usage,
    keywords: 'routing switching limits usage headroom',
  ),
  (
    title: 'Best at',
    section: .agents,
    keywords: 'advanced code writing research pictures quick questions which connection strengths',
  ),
  (title: 'Ollama model', section: .agents, keywords: 'local model offline llm'),
  // Skills.
  (title: 'Helmy\'s skills', section: .skills, keywords: 'skills commands slash skill.md new add'),
  // Tools.
  (
    title: 'Accounts',
    section: .tools,
    keywords: 'gmail calendar slack notion drive integrations connectors sign in',
  ),
  (title: 'Add a tool server', section: .tools, keywords: 'mcp server tools plugins integrations'),
  // What Helmy learned, and memory files.
  (
    title: 'What Helmy has learned',
    section: .learned,
    keywords: 'lessons learned corrections habits forget',
  ),
  (
    title: 'Memory files',
    section: .memory,
    keywords: 'remember notes instructions claude.md agents.md',
  ),
  // Storage.
  (
    title: 'Where things are',
    section: .storage,
    keywords: 'storage disk space folders cache clear',
  ),
  (
    title: 'What Helmy is running',
    section: .storage,
    keywords: 'processes diagnostics cpu memory stop kill logs',
  ),
  // Data.
  (title: 'Your conversations', section: .data, keywords: 'export markdown backup history'),
  (title: 'Bring in conversations', section: .data, keywords: 'import history claude codex'),
  // Keyboard.
  (title: 'Shortcuts', section: .keyboard, keywords: 'keyboard keybindings hotkeys keys'),
  // Projects.
  (title: 'Projects', section: .projects, keywords: 'repositories folders actions scripts'),
  // Phone.
  (
    title: 'Reach Helmy from your phone',
    section: .phone,
    keywords: 'remote mobile iphone android pair qr',
  ),
  (title: 'Pair a phone', section: .phone, keywords: 'qr code pairing key'),
  (title: 'Paired phones', section: .phone, keywords: 'unpair revoke remove phone devices'),
  // Archive.
  (
    title: 'Archived chats',
    section: .archive,
    keywords: 'archive unarchive restore deleted old hidden',
  ),
  // About.
  (title: 'Helmy', section: .about, keywords: 'about version update release'),
  (title: 'Privacy', section: .about, keywords: 'privacy data sent telemetry policy'),
  (title: 'Licenses', section: .about, keywords: 'open source licenses credits'),
];

/// The entries that match [query], best first: every word must appear in the
/// title, the page's name or the keywords; a title that matches outranks one
/// matched by its keywords.
List<SettingEntry> searchSettings(String query, String Function(SettingsSection) pageName) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final words = q.split(RegExp(r'\s+'));
  final out = <(SettingEntry, int, int)>[];
  for (final (i, e) in settingsIndex.indexed) {
    final title = e.title.toLowerCase();
    final all = '$title ${pageName(e.section).toLowerCase()} ${e.keywords}';
    if (!words.every(all.contains)) continue;
    final rank = title == q
        ? 5
        : title.startsWith(q)
        ? 4
        : title.contains(q)
        ? 3
        : words.every(title.contains)
        ? 2
        : 1;
    out.add((e, rank, i));
  }
  out.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$3.compareTo(b.$3));
  return [for (final (e, _, _) in out) e];
}
