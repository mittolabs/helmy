/// A chat's standing goal (as T3 Code has `/goal`, kept by Helmy rather than
/// a connection, so it holds when the chat moves between them). Set with
/// `/goal <objective>`; Helmy then asks the agent to keep going after each
/// turn until the agent ends a reply with [goalMetMarker], having checked
/// that the goal is met. It stops for the person: a failed turn, something
/// waiting for them, their own message, or many turns in a row.
library;

const goalMetMarker = 'HELMY_GOAL_MET';

/// Where a goal's "keep going" message came from: Helmy, not the person.
const goalFrom = 'Helmy, working toward the goal';

final _met = RegExp(r'^[ \t]*HELMY_GOAL_MET[ \t]*$', multiLine: true);

/// Whether [text] says the goal is met.
bool goalMetIn(String text) => _met.hasMatch(text);

/// [text] without the marker line.
String withoutGoalMarker(String text) =>
    _met.hasMatch(text) ? text.replaceAll(_met, '').trimRight() : text;

/// What a `/goal` message asks.
sealed class GoalCommand {
  const GoalCommand();
}

class GoalShow extends GoalCommand {
  const GoalShow();
}

class GoalClear extends GoalCommand {
  const GoalClear();
}

class GoalPause extends GoalCommand {
  const GoalPause();
}

class GoalResume extends GoalCommand {
  const GoalResume();
}

class GoalSet extends GoalCommand {
  const GoalSet(this.objective);
  final String objective;
}

/// The `/goal` command [text] is; null when it is not one.
GoalCommand? goalCommand(String text) {
  final m = RegExp(r'^/goal(?:\s+([\s\S]*))?$').firstMatch(text.trim());
  if (m == null) return null;
  final arg = (m[1] ?? '').trim();
  return switch (arg.toLowerCase()) {
    '' => const GoalShow(),
    'clear' => const GoalClear(),
    'pause' => const GoalPause(),
    'resume' => const GoalResume(),
    _ => GoalSet(arg),
  };
}

/// What the agent is told to carry on with.
String goalNext(String objective) =>
    'Keep going toward the goal: $objective\n\n'
    'Take the next step. When the goal is fully met, and you have checked that it is, end '
    'your reply with a line of its own: $goalMetMarker.';
