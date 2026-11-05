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

  /// The brief as the person wrote it: Helmy leaves it as it is.
  final bool briefByPerson = false,

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
    String? brief,
    bool? briefByPerson,
    DateTime? settledAt,
    DateTime? unsettledAt,
  }) => Chat(
    id: id,
    title: title ?? this.title,
    createdAt: createdAt,
    named: named ?? this.named,
    brief: brief ?? this.brief,
    briefByPerson: briefByPerson ?? this.briefByPerson,
    // Brought back, it is no longer settled.
    settledAt: unsettledAt != null ? null : settledAt ?? this.settledAt,
    unsettledAt: unsettledAt ?? this.unsettledAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    if (named) 'named': true,
    if (brief.isNotEmpty) 'brief': brief,
    if (briefByPerson) 'briefByPerson': true,
    if (settledAt != null) 'settledAt': settledAt!.toIso8601String(),
    if (unsettledAt != null) 'unsettledAt': unsettledAt!.toIso8601String(),
  };

  static Chat fromJson(Map<String, Object?> j) => Chat(
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    named: j['named'] == true,
    brief: '${j['brief'] ?? ''}',
    briefByPerson: j['briefByPerson'] == true,
    settledAt: DateTime.tryParse('${j['settledAt'] ?? ''}'),
    unsettledAt: DateTime.tryParse('${j['unsettledAt'] ?? ''}'),
  );
}
