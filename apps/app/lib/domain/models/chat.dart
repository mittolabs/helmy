/// A chat: one conversation (its session, with side chats and background
/// agents beside it), with what Helmy calls it: its title, topic word, icon.
class const Chat({
  required final String id,
  required final String title,
  required final DateTime createdAt,

  /// Named by the person: kept, whatever its threads come to be called.
  final bool named = false,

  /// Titled by Helmy from what it is about: no longer follows its threads'
  /// first words.
  final bool titled = false,

  /// One line on what it is about and where it stands, kept by Helmy.
  final String description = '',

  /// Its icon, by name in `chatIcons`; null before Helmy chose one.
  final String? icon,

  /// What it falls under, in one word ("Money", "Travel", a project's name),
  /// the same word for chats about the same thing; empty before Helmy chose.
  final String topic = '',

  /// Settled: nothing in it waits on anyone, so it sits in Settled at the
  /// bottom of the list until something new happens in it.
  final DateTime? settledAt,

  /// Last brought back from Settled, by hand or by something new in it: it
  /// counts as worked in then, so being idle does not settle it again at once.
  final DateTime? unsettledAt,
}) {
  bool get settled => settledAt != null;

  Chat copyWith({
    String? title,
    bool? named,
    bool? titled,
    String? description,
    String? icon,
    String? topic,
    DateTime? settledAt,
    DateTime? unsettledAt,
  }) => Chat(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    named: named ?? this.named,
    titled: titled ?? this.titled,
    description: description ?? this.description,
    icon: icon ?? this.icon,
    topic: topic ?? this.topic,
    // Brought back, it is no longer settled.
    settledAt: unsettledAt != null ? null : settledAt ?? this.settledAt,
    unsettledAt: unsettledAt ?? this.unsettledAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    if (named) 'named': true,
    if (titled) 'titled': true,
    if (description.isNotEmpty) 'description': description,
    'icon': ?icon,
    if (topic.isNotEmpty) 'topic': topic,
    if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
    if (unsettledAt != null) 'unsettledAt': unsettledAt!.toIso8601String(),
  };

  static Chat fromJson(Map<String, Object?> j) => Chat(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    named: j['named'] == true,
    titled: j['titled'] == true,
    description: '${j['description'] ?? ''}',
    icon: j['icon'] as String?,
    topic: '${j['topic'] ?? ''}',
    settledAt: DateTime.tryParse('${j['settledAt'] ?? ''}'),
    unsettledAt: DateTime.tryParse('${j['unsettledAt'] ?? ''}'),
  );
}
