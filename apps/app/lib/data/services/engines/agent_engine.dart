import '../../../domain/models/chat_item.dart';
import '../../../domain/models/engine.dart';
import '../../../domain/models/memory.dart';

/// What to start a run with.
class const EngineLaunch({
  required final String cwd,
  required final PermissionLevel level,

  /// The engine's own conversation id, to pick up where it left off.
  final String? resumeId,
});

/// State an engine reports alongside the items it writes.
class EngineStatus {
  bool thinking = false;
  String? resumeId;

  /// The fuller of its usage windows, as it last reported; null until it has.
  Usage? usage;

  /// How full its context was at the last request; null until it reports.
  ContextUse? context;

  /// Set when the agent began a turn nobody sent it, as Claude Code does when
  /// work it left in the background ends. Whoever acts on it clears it.
  bool startedByItself = false;
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

  /// Its usage now, asked without sending a message; null when the engine has
  /// no way to say outside a turn.
  Future<Usage?> readUsage() async => null;

  /// Its MCP servers and the state each is in ("connected", "needs-auth",
  /// "failed"...), as it reports; asked without sending a message.
  Future<List<({String name, String status})>> servers() async => const [];

  /// The services it is connected to right now: see [connectedOf].
  Future<Set<Capability>> connected();

  /// One short answer to [question] under [instructions]: no tools, no
  /// conversation, nothing kept. Null when it cannot answer.
  Future<String?> ask(String instructions, String question);

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
  void answer(PermissionPrompt prompt, PermissionAnswer answer);

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
