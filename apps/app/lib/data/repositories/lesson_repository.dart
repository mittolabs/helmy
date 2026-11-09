import 'package:flutter/foundation.dart';

import '../services/storage_service.dart';

/// Where a lesson holds: for the person everywhere, or in one project.
const everywhere = 'me';

/// Something Helmy learned working with the person, to do better next time:
/// a correction, what worked, a habit of theirs.
class Lesson {
  Lesson({
    required this.id,
    required this.text,
    required this.scope,
    required this.kind,
    required this.learnedAt,
    this.chatId,
    this.sessionId,
  });

  final String id;
  String text;

  /// [everywhere], or a project's folder.
  String scope;

  /// 'correction', 'worked' or 'habit'.
  final String kind;
  final DateTime learnedAt;

  /// Where it was learned, to go back to.
  final String? chatId, sessionId;

  Map<String, Object?> toJson() => {
    'id': id,
    'text': text,
    'scope': scope,
    'kind': kind,
    'learnedAt': learnedAt.toIso8601String(),
    'chatId': ?chatId,
    'sessionId': ?sessionId,
  };

  static Lesson? fromJson(Object? j) {
    if (j is! Map || j['id'] == null || j['text'] == null) return null;
    return Lesson(
      id: '${j['id']}',
      text: '${j['text']}',
      scope: '${j['scope'] ?? everywhere}',
      kind: '${j['kind'] ?? 'habit'}',
      learnedAt: DateTime.tryParse('${j['learnedAt']}') ?? DateTime.now(),
      chatId: j['chatId'] as String?,
      sessionId: j['sessionId'] as String?,
    );
  }
}

/// What Helmy has learned, across projects: Helmy's own, given to every
/// connection, never written into the person's repositories.
class LessonRepository extends ChangeNotifier {
  LessonRepository(this._storage);
  final StorageService? _storage;
  static const _file = 'lessons.json';

  final List<Lesson> _all = [];
  List<Lesson> get all => List.unmodifiable(_all);

  Future<void> load() async {
    final j = await _storage?.read(_file);
    _all
      ..clear()
      ..addAll([for (final l in (j as List?) ?? const []) ?Lesson.fromJson(l)]);
    notifyListeners();
  }

  Future<void> _save() async => _storage?.write(_file, [for (final l in _all) l.toJson()]);

  /// The lessons for work in [project]: the person's own, then the project's.
  List<Lesson> forProject(String project) => [
    ..._all.where((l) => l.scope == everywhere),
    ..._all.where((l) => l.scope == project),
  ];

  Future<void> add(Lesson l) async {
    _all.add(l);
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _all.removeWhere((l) => l.id == id);
    await _save();
    notifyListeners();
  }

  Future<void> edit(String id, {String? text, String? scope}) async {
    final l = _all.where((l) => l.id == id).firstOrNull;
    if (l == null) return;
    if (text != null && text.trim().isNotEmpty) l.text = text.trim();
    if (scope != null) l.scope = scope;
    await _save();
    notifyListeners();
  }

  /// [lessons] as instructions: what a thread starts knowing about working
  /// with this person. Empty when there are none.
  static String asInstructions(List<Lesson> lessons) {
    if (lessons.isEmpty) return '';
    final me = lessons.where((l) => l.scope == everywhere).toList();
    final here = lessons.where((l) => l.scope != everywhere).toList();
    return [
      '## What you have learned working with this person',
      '',
      'From earlier chats. Follow these unless they say otherwise now.',
      if (me.isNotEmpty) ...['', 'Everywhere:', for (final l in me) '- ${l.text}'],
      if (here.isNotEmpty) ...['', 'In this project:', for (final l in here) '- ${l.text}'],
    ].join('\n');
  }
}
