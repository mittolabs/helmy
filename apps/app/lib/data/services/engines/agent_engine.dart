import '../../../domain/models/chat_item.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/memory.dart';

/// What to start a run with.
class const EngineLaunch({
  required final String cwd,
  required final PermissionLevel level,

  /// The engine's own conversation id, to pick up where it left off.
  final String? resumeId,

  /// Helmy's session, so Helmy's own tools know which session asks (the
  /// page in its Preview panel).
  final String? sessionId,

  /// The brief of the thread's chat, frozen when the thread began (decision
  /// `0014`): sent with Helmy's instructions on every run of the thread.
  final String? brief,

  /// What Helmy has learned working with the person (LessonRepository),
  /// as instructions, frozen with the thread as its brief is.
  final String? lessons,

  /// A model, effort and speed chosen for the chat (Developer mode); null
  /// for the connection's own.
  final String? model,
  final String? effort,
  final bool fast = false,
});

/// State an engine reports alongside the items it writes.
class EngineStatus {
  bool thinking = false;
  String? resumeId;

  /// The fuller of its usage windows, as it last reported; null until it has.
  Usage? usage;

  /// How full its context was at the last request; null until it reports.
  ContextUse? context;

  /// The last turn's tokens; null until it reports.
  TurnTokens? tokens;

  /// Set when the agent began a turn nobody sent it, as Claude Code does when
  /// work it left in the background ends. Whoever acts on it clears it.
  bool startedByItself = false;

  /// The model answering, as the connection names it; null until it says.
  String? model;
}

/// What [AgentEngine.ask] got back: the text, the model that wrote it, and
/// its tokens as the connection reported them. What it did not report is
/// null: unknown, never estimated.
class const Answer({required final String text, final String? model, final TurnTokens? tokens});

/// Effort levels by how hard they think, least first, as connections name them.
const _efforts = ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'];

/// What a model's id or name says when it is a connection's small one.
final _smallName = RegExp(
  r'\b(mini|nano|small|lite|tiny|haiku|flash|luna)\b',
  caseSensitive: false,
);

/// What its description says when it is.
final _smallWords = RegExp(
  r'\b(affordable|cheap|cheaper|cheapest|lightweight|efficient|smaller|smallest|easier tasks|'
  r'simple tasks)\b',
  caseSensitive: false,
);

/// A model the connection itself calls old.
final _oldWords = RegExp(r'\b(older|previous|legacy|deprecated)\b', caseSensitive: false);

/// The model in [models] to ask a short question of: the first, newest
/// first as connections list them, whose id, name or description says it
/// is small, fast or cheap, preferring one the connection does not call
/// old. Chosen from what the account offers, never a name assumed to exist.
/// Null when none says so, and the connection's default answers.
ModelChoice? smallestModel(List<ModelChoice> models) {
  final small = [
    for (final m in models)
      if (_smallName.hasMatch('${m.id} ${m.name}') || _smallWords.hasMatch(m.description)) m,
  ];
  return small.where((m) => !_oldWords.hasMatch(m.description)).firstOrNull ?? small.firstOrNull;
}

/// The least effort [model] takes; null when it lists none, and the
/// connection's own default applies.
String? leastEffort(ModelChoice? model) {
  final efforts = model?.efforts ?? const <String>[];
  if (efforts.isEmpty) return null;
  final known = efforts.where(_efforts.contains).toList()
    ..sort((a, b) => _efforts.indexOf(a).compareTo(_efforts.indexOf(b)));
  return known.firstOrNull ?? efforts.first;
}

/// How the user answered a [PermissionPrompt].
enum PermissionAnswer { allow, allowForSession, deny }

/// An agent CLI Helmy can drive: Claude Code, Codex, and whatever comes
/// next. Implement this and add it to the registry in `config/dependencies.dart`;
/// the router starts sending it messages, and nothing else changes.
abstract class AgentEngine {
  EngineInfo get info;

  /// Null when the engine can be started; otherwise why not.
  Future<String?> unavailableReason();

  /// The files it keeps memory and standing instructions in, including ones
  /// that do not exist yet but would be read if they did.
  Future<List<MemoryFile>> memoryFiles();

  /// What it runs for a message that starts with /name, in [cwd]. Engines
  /// with none return an empty list.
  Future<List<SlashCommand>> commands(String cwd) async => const [];

  /// The models it offers, for choosing one in Developer mode; empty when
  /// it offers no choice.
  Future<List<ModelChoice>> models() async => const [];

  /// Its usage now, asked without sending a message; null when the engine has
  /// no way to say outside a turn.
  Future<Usage?> readUsage() async => null;

  /// Its MCP servers and the state each is in ("connected", "needs-auth",
  /// "failed"...), as it reports; asked without sending a message.
  Future<List<({String name, String status})>> servers() async => const [];

  /// The services it is connected to right now: see [connectedOf].
  Future<Set<Capability>> connected();

  /// One short answer to [question] under [instructions]: no tools, no
  /// conversation, nothing kept, on the connection's smallest model at its
  /// least effort ([smallestModel], [leastEffort]), since what asks is
  /// Helmy's upkeep and its judge, many times a chat. Null when it cannot
  /// answer.
  Future<Answer?> ask(String instructions, String question);

  /// Memory it keeps somewhere Helmy should not edit, described.
  Future<List<MemoryNote>> memoryNotes() async => const [];

  /// Starts a background process. The run appends to and updates [items],
  /// the conversation's shared transcript, as output arrives.
  Future<EngineRun> start(EngineLaunch launch, List<ChatItem> items);
}

/// One live process for one session.
abstract class EngineRun {
  EngineStatus get status;

  /// Fires after every change to the items or [status]: `true` when a turn
  /// has just ended. Closes when the process exits.
  Stream<bool> get changes;

  /// Why the process ended, when it ended badly.
  String? get exitDetail;

  /// Sends a message, with files by path: pictures as images where the engine
  /// takes them, anything else named for the agent to read.
  void send(String text, {List<String> attachments = const []});

  /// Adds a message to the turn under way, without stopping it: the agent
  /// takes it in at its next step. False when this run cannot, and then
  /// nothing was sent.
  Future<bool> steer(String text, {List<String> attachments = const []});

  void interrupt();

  /// [why]: for a denial, what the agent is told (where it can be told).
  void answer(PermissionPrompt prompt, PermissionAnswer answer, {String? why});

  /// Sends the chosen answers of a question prompt.
  void answerQuestion(PermissionPrompt prompt);

  /// Shrinks the conversation so far into a summary, to free context.
  void compact();

  /// Stops work the agent left running in the background.
  void stopTask(String taskId);

  /// Only called when [EngineInfo.liveModeSwitch] is true.
  void setLevel(PermissionLevel level);
  Future<void> close();
}

/// The services among [servers] that are connected.
Set<Capability> connectedOf(List<({String name, String status})> servers) => {
  for (final s in servers)
    if (s.status == 'connected') ?Capability.ofServer(s.name),
};
