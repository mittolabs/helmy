import 'package:flutter/foundation.dart';

import '../../domain/models/chat_item.dart';
import '../../domain/activity_words.dart';
import '../../domain/models/engine.dart';
import '../../domain/models/session.dart';
import '../../utils/result.dart';
import '../services/engines/agent_engine.dart';

/// What one session's conversation looks like right now.
/// A message written while the agent was busy, sent when it is free.
/// [from]: what sent it, when not the person (UserMessage.from).
typedef Queued = ({String text, List<String> attachments, Set<Capability> needs, String? from});

class Conversation {
  final List<ChatItem> items = [];
  bool loaded = false;
  bool busy = false;
  bool thinking = false;

  /// How full the context of the engine that answered last is.
  ContextUse? context;

  /// Messages waiting for the turn to end, oldest first.
  final List<Queued> queue = [];

  /// Every connection was at its usage limit: the message waits, and goes by
  /// itself at this time. Null when nothing is held.
  DateTime? heldUntil;

  int get pendingPrompts =>
      items.whereType<PermissionPrompt>().where((p) => p.decision == .pending).length;
}

/// Live conversations. Each message goes to whichever engine the router picks,
/// in a background process per session and engine; the caller never learns
/// which. Notifies on every change.
abstract class ConversationRepository extends ChangeNotifier {
  Future<ActivitySummary?> describeActivities(
    String sessionId,
    List<ToolCall> calls, {
    String context = '',
  }) async => null;
  Conversation of(String sessionId);

  Future<void> load(String sessionId);

  /// What was said in a session, as plain text to search, without loading it
  /// onto the screen.
  Future<String> searchText(String sessionId);

  /// Copies [from]'s conversation up to item [upTo] (included) into [to],
  /// then a note of where it came from: a fork. Its connections hear what
  /// was said with the first message sent there.
  Future<void> copy(String from, String to, {required int upTo, required String note});

  /// Makes [items] session [to]'s conversation, as brought in from a
  /// connection's own history, then [note] of where it came from.
  Future<void> adopt(String to, List<ChatItem> items, {required String note});

  /// [needs] adds what the caller knows the message needs to what its words
  /// say: "make the collar red" from an image's Refine button needs a picture
  /// made, though it never says so.
  Future<Result<void>> send(
    Session session,
    String text, {
    List<String> attachments = const [],
    Set<Capability> needs = const {},
    String? from,
  });

  /// Goes back to the user's message at [index] and sends [text] in its
  /// place. What came after is kept as a version of its own (see [Branches]);
  /// every engine starts a new thread from what came before. Files changed on
  /// disk stay.
  Future<Result<void>> rewind(Session session, int index, String text);

  /// Shows version [to] of the conversation from the edited message at
  /// [index] on. Files on disk are not touched.
  Future<Result<void>> showBranch(Session session, int index, int to);

  /// [call]'s command in plain words, asked of an agent outside the
  /// conversation, and kept on the step.
  Future<Result<String>> explain(String sessionId, ToolCall call);

  /// Stops work an agent left running in the background.
  void stopTask(String sessionId, String taskId);

  void interrupt(String sessionId);

  /// Whether only the model on this Mac could answer the last message (no
  /// connection online was on and reachable), or null before any was sent.
  bool? get onlyThisMac => null;

  /// Every engine's slash commands for [session], each once, by name.
  Future<List<SlashCommand>> commands(Session session);

  /// The connections a chat can be held to (Developer mode), each with the
  /// models it offers; one that offers no choice is still listed.
  Future<List<({String id, String name, List<ModelChoice> models})>> connectionModels() async =>
      const [];

  /// A connection's name, as Settings shows it; null when it is not set up.
  String? connectionName(String engineId) => null;

  /// Takes back a message that was waiting its turn.
  void unqueue(String sessionId, int index);

  /// Sends the waiting message at [index] now: it goes first in line and the
  /// turn under way stops, so the agent takes it up at once, redirected.
  void steer(String sessionId, int index);

  /// Asks the session's engine to shrink the conversation into a summary.
  Future<Result<void>> compact(Session session);

  void answerPermission(String sessionId, PermissionPrompt prompt, PermissionAnswer answer);

  void answerQuestion(String sessionId, PermissionPrompt prompt);

  /// Applies a new permission level to whatever runs this session.
  Future<void> setLevel(String sessionId, PermissionLevel level);

  /// Ends every process of the session; the next message resumes in new ones.
  Future<void> stop(String sessionId);

  Future<void> forget(String sessionId);

  /// Takes back a lesson Helmy learned in [sessionId]'s chat.
  Future<void> forgetLesson(String sessionId, Learned item) async {}
}
