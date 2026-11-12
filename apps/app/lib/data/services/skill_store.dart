import 'dart:io';

import 'package:flutter/foundation.dart';

/// One skill: a folder with a SKILL.md, as the Agent Skills format has it
/// (YAML frontmatter with a name and a description, then instructions).
typedef Skill = ({String name, String description, String folder});

/// Helmy's own skills: one folder, given to every connection, so a skill
/// added once works whichever connection Helmy picks for a message.
///
/// How each gets them, each tried 2026-11-10:
/// - Claude Code: as a plugin, `--plugin-dir` [pluginDir] (its skills then
///   show as `helmy:<name>`).
/// - Codex: a link, `<CODEX_HOME>/skills/helmy`, to [root] ([linkInto]):
///   Codex finds skills in folders below its own.
/// - OpenCode: its `skills` setting, naming [root].
class SkillStore extends ChangeNotifier {
  SkillStore(this.root);

  /// Where the skills live: one folder per skill.
  final String root;

  /// The folder Claude Code is given as a plugin: a manifest, and its
  /// `skills` a link to [root].
  String get pluginDir => '${File(root).parent.path}/skills-plugin';

  List<Skill> _skills = const [];
  List<Skill> get skills => _skills;

  /// The names, for telling Helmy's skills from a connection's.
  Set<String> get names => {for (final s in _skills) s.name};

  Future<void> load() async {
    final dir = Directory(root);
    await dir.create(recursive: true);
    final found = <Skill>[];
    await for (final e in dir.list()) {
      if (e is! Directory) continue;
      final md = File('${e.path}/SKILL.md');
      if (!md.existsSync()) continue;
      final s = read(await md.readAsString(), e.path);
      if (s != null) found.add(s);
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    _skills = found;
    await _plugin();
    notifyListeners();
  }

  /// The skill a SKILL.md describes; null without a name.
  static Skill? read(String text, String folder) {
    final m = RegExp(r'^---\s*\n([\s\S]*?)\n---').firstMatch(text);
    if (m == null) return null;
    String? field(String key) {
      final f = RegExp('^$key:\\s*(.*)\$', multiLine: true).firstMatch(m[1]!);
      if (f == null) return null;
      final v = f[1]!.trim();
      if (v.length > 1 && v.startsWith('"') && v.endsWith('"')) {
        // YAML double quotes: a backslash escapes the character after it.
        return v.substring(1, v.length - 1).replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!);
      }
      if (v.length > 1 && v.startsWith("'") && v.endsWith("'")) {
        return v.substring(1, v.length - 1).replaceAll("''", "'");
      }
      return v;
    }

    final name = field('name') ?? folder.split('/').last;
    if (name.isEmpty) return null;
    return (name: name, description: field('description') ?? '', folder: folder);
  }

  /// A name a skill's folder can have: lower case, digits and dashes.
  static String slug(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  /// Makes a skill from what the person wrote. Its folder is its name;
  /// an existing one of that name is replaced.
  Future<Skill?> create({
    required String name,
    required String description,
    required String instructions,
  }) async {
    final id = slug(name);
    if (id.isEmpty) return null;
    final dir = Directory('$root/$id');
    await dir.create(recursive: true);
    final oneLine = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    await File('${dir.path}/SKILL.md').writeAsString(
      '---\nname: $id\ndescription: ${_quoted(oneLine)}\n---\n\n${instructions.trim()}\n',
    );
    await load();
    return _skills.where((s) => s.name == id).firstOrNull;
  }

  static String _quoted(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Copies in a skill from [folder] (one with a SKILL.md). Null, and
  /// nothing copied, when it has none.
  Future<Skill?> addFolder(String folder) async {
    final found = await skillsIn(folder);
    if (found.length != 1 || found.single.folder != folder) return null;
    final to = await _copyIn(found.single);
    await load();
    return _skills.where((k) => k.folder == to).firstOrNull;
  }

  /// Every skill in [folder]: the folder itself when it is one, else each
  /// folder in it that is (`skills/`), or in its `skills` (`.agents/`).
  Future<List<Skill>> skillsIn(String folder) async {
    Future<Skill?> one(String dir) async {
      final md = File('$dir/SKILL.md');
      return md.existsSync() ? read(await md.readAsString(), dir) : null;
    }

    if (await one(folder) case final s?) return [s];
    final out = <Skill>[];
    for (final under in [folder, '$folder/skills']) {
      final dir = Directory(under);
      if (!dir.existsSync() || _isOurs(under)) continue;
      final children = await dir.list().where((e) => e is Directory || e is Link).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final e in children) {
        if (_isOurs(e.path)) continue;
        if (await one(e.path) case final s?) out.add(s);
      }
      if (out.isNotEmpty) break;
    }
    return out;
  }

  /// Copies in each of [skills]; one of a name already here is replaced.
  /// How many came in.
  Future<int> addAll(List<Skill> skills) async {
    var n = 0;
    for (final s in skills) {
      try {
        await _copyIn(s);
        n++;
      } on FileSystemException {
        // One that cannot be read is left; the rest still come in.
      }
    }
    await load();
    return n;
  }

  Future<String> _copyIn(Skill s) async {
    final to = Directory('$root/${slug(s.name)}');
    if (to.existsSync()) await to.delete(recursive: true);
    await _copy(Directory(s.folder), to);
    return to.path;
  }

  /// Whether [path] is Helmy's own skills (Codex's link to them, say).
  bool _isOurs(String path) {
    try {
      final real = Directory(path).resolveSymbolicLinksSync();
      return real == Directory(root).resolveSymbolicLinksSync() || real.startsWith('$root/');
    } on FileSystemException {
      return false;
    }
  }

  /// Where skills are kept on a computer for every project: the shared
  /// `.agents` folder, and each connection's own.
  static List<String> systemFolders(String home) => [
    '$home/.agents/skills',
    '$home/.claude/skills',
    '$home/.codex/skills',
    '$home/.config/opencode/skills',
    '$home/.cursor/skills',
  ];

  /// Skills on this computer, in [systemFolders], that Helmy does not have
  /// yet (by name): each once, the first folder's where two share a name.
  Future<List<Skill>> onThisComputer(String home) async {
    final seen = {for (final s in _skills) s.name};
    return [
      for (final f in systemFolders(home))
        for (final s in await skillsIn(f))
          if (seen.add(s.name)) s,
    ];
  }

  Future<void> remove(String name) async {
    final s = _skills.where((s) => s.name == name).firstOrNull;
    if (s == null) return;
    await Directory(s.folder).delete(recursive: true);
    await load();
  }

  static Future<void> _copy(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final e in from.list()) {
      final name = e.path.split('/').last;
      if (e is Directory) {
        await _copy(e, Directory('${to.path}/$name'));
      } else if (e is File) {
        await e.copy('${to.path}/$name');
      }
    }
  }

  /// Claude Code's plugin: named "helmy", its skills Helmy's.
  Future<void> _plugin() async {
    final meta = File('$pluginDir/.claude-plugin/plugin.json');
    if (!meta.existsSync()) {
      await meta.parent.create(recursive: true);
      await meta.writeAsString('{"name": "helmy", "description": "Helmy\'s skills"}\n');
    }
    await _link('$pluginDir/skills', root);
  }

  /// Codex's link to Helmy's skills, in [codexHome]'s skills folder.
  Future<void> linkInto(String codexHome) async {
    await Directory('$codexHome/skills').create(recursive: true);
    await _link('$codexHome/skills/helmy', root);
  }

  static Future<void> _link(String at, String to) async {
    final link = Link(at);
    try {
      if (link.existsSync()) {
        if (await link.target() == to) return;
        await link.delete();
      } else if (FileSystemEntity.typeSync(at, followLinks: false) != .notFound) {
        // Something of the person's own is there: left alone.
        return;
      }
      await link.create(to);
    } on FileSystemException {
      // Unwritable: that connection goes without Helmy's skills.
    }
  }

  /// [text] with a Helmy skill's /command turned into words every
  /// connection follows: each names Helmy's skills differently (Claude Code
  /// as `/helmy:name`), but all load a skill they are asked to use.
  static String asked(String text, Set<String> names) {
    final m = RegExp(r'^/([\w.-]+)(?:\s+([\s\S]*))?$').firstMatch(text.trim());
    if (m == null || !names.contains(m[1])) return text;
    final rest = (m[2] ?? '').trim();
    return 'Use the "${m[1]}" skill.${rest.isEmpty ? '' : ' $rest'}';
  }
}
