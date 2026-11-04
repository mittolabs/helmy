/// A topic talked about, over any number of threads (decision `0014`): your
/// finances, an app being made. Its threads are sessions with its id.
class const Chat({
  required final String id,
  required final String title,
  required final DateTime createdAt,

  /// Named by the person: kept, whatever its threads come to be called.
  final bool named = false,

  /// What the topic has come to: decisions and open questions, short. Written
  /// by hand for now; kept by Helmy as threads go on, later.
  final String brief = '',
}) {
  Chat copyWith({String? title, bool? named, String? brief}) => Chat(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    named: named ?? this.named,
    brief: brief ?? this.brief,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    if (named) 'named': true,
    if (brief.isNotEmpty) 'brief': brief,
  };

  static Chat fromJson(Map<String, Object?> j) => Chat(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    named: j['named'] == true,
    brief: '${j['brief'] ?? ''}',
  );
}
