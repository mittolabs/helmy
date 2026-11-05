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
  (
    title: 'Mark chats done on their own',
    section: .general,
    keywords: 'settle settled done inactive automatically archive',
  ),
  (
    title: 'Permissions',
    section: .general,
    keywords: 'ask first full access read only edit approvals allowed',
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
  (title: 'Accent', section: .appearance, keywords: 'color highlight buttons blue rose'),
  (title: 'Text size', section: .appearance, keywords: 'font bigger smaller zoom scale'),
  (title: 'Conversation width', section: .appearance, keywords: 'chat width wide layout column'),
  (title: 'Wrap long code blocks', section: .appearance, keywords: 'word wrap lines code'),
  (
    title: 'Colors for changes',
    section: .appearance,
    keywords: 'diff red green blue orange colorblind',
  ),
  (title: 'Hide changes only in spaces', section: .appearance, keywords: 'whitespace diff ignore'),
  // Preview panel.
  (title: 'Show pages with', section: .preview, keywords: 'browser webkit chromium preview engine'),
  (title: 'Chromium browser', section: .preview, keywords: 'chrome edge brave arc browser'),
  // Connections and usage.
  (
    title: 'Connections',
    section: .agents,
    keywords: 'claude code codex ollama accounts sign in update version usage limits',
  ),
  (
    title: 'Move to a connection with more room',
    section: .agents,
    keywords: 'routing switching limits usage headroom',
  ),
  (title: 'Ollama model', section: .agents, keywords: 'local model offline llm'),
  (title: 'Always allowed', section: .agents, keywords: 'rules permissions allow commands'),
  // Skills and tools.
  (title: 'MCP servers', section: .tools, keywords: 'skills tools mcp plugins integrations'),
  // Memory.
  (title: 'Memory', section: .memory, keywords: 'remember notes facts forget'),
  // Data and storage.
  (title: 'Where things are', section: .data, keywords: 'storage disk space folders cache clear'),
  (title: 'Your conversations', section: .data, keywords: 'export markdown backup history'),
  (title: 'Bring in conversations', section: .data, keywords: 'import history claude codex'),
  // Keyboard.
  (title: 'Shortcuts', section: .keyboard, keywords: 'keyboard keybindings hotkeys keys'),
  // Projects.
  (title: 'Projects', section: .projects, keywords: 'repositories folders actions scripts'),
  (
    title: 'What Helmy may do without asking',
    section: .projects,
    keywords: 'project permissions level',
  ),
  // Phone.
  (
    title: 'Reach Helmy from your phone',
    section: .phone,
    keywords: 'remote mobile iphone android pair qr',
  ),
  (title: 'Pair a phone', section: .phone, keywords: 'qr code pairing key revoke'),
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
