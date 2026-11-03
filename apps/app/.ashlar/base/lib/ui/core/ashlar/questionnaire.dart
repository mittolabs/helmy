// Ashlar UI: Questionnaire. Copied into your app by `ashlar add questionnaire`; it is yours
// to change.
//
// Questions asked one at a time: a choice, several, or words of your own, each required or
// skippable, with keys for every answer. The page, card or dialog around it owns closing,
// saving and sending.

import 'package:ashlar_icons/ashlar_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'button.dart';
import 'input.dart';
import 'kbd.dart';
import 'pressable.dart';
import 'progress.dart';
import 'theme.dart';

/// One answer to pick.
@immutable
class QuestionChoice {
  const QuestionChoice(
    this.value,
    this.label, {
    this.description,
    this.enabled = true,
  });

  /// The answer's value, given back in the answers.
  final String value;

  /// What the answer says.
  final String label;

  /// A line under the label.
  final String? description;

  /// False fades it and stops it being picked.
  final bool enabled;
}

/// One question of a [Questionnaire].
@immutable
class Question {
  const Question({
    required this.name,
    required this.prompt,
    this.description,
    this.choices = const [],
    this.multiple = false,
    this.required = false,
    this.other,
    this.otherPlaceholder,
    this.applies,
  });

  /// The answer's key in what [Questionnaire.onSubmit] gives.
  final String name;

  /// The question.
  final String prompt;

  /// A line under the question.
  final String? description;

  /// The answers to pick from.
  final List<QuestionChoice> choices;

  /// Several choices may be picked, not one.
  final bool multiple;

  /// It must be answered: no skipping it.
  final bool required;

  /// A field for an answer of one's own, named by this (a screen reader hears it). Alone,
  /// without [choices], the question is answered in words.
  final String? other;

  /// Faint text in the answer field while it is empty.
  final String? otherPlaceholder;

  /// Whether to ask it, from the answers so far: a question that does not apply is left
  /// out of the count and passed over.
  final bool Function(Map<String, QuestionAnswer> answers)? applies;
}

/// An answer: the choices picked, words of one's own, or a skip.
@immutable
class QuestionAnswer {
  const QuestionAnswer({
    this.picked = const {},
    this.text = '',
    this.skipped = false,
  });

  /// The choices picked.
  final Set<String> picked;

  /// Words of one's own.
  final String text;

  /// Whether the question was skipped.
  final bool skipped;

  bool get answered => picked.isNotEmpty || text.trim().isNotEmpty;

  @override
  String toString() => skipped
      ? 'skipped'
      : [...picked, if (text.trim().isNotEmpty) text.trim()].join(', ');
}

/// Keys that pick answers.
enum QuestionShortcuts { none, letters, numbers }

/// The words on its buttons and in its messages: English unless given.
@immutable
class QuestionnaireLabels {
  const QuestionnaireLabels({
    this.previous = 'Back',
    this.next = 'Next',
    this.skip = 'Skip',
    this.submit = 'Submit',
    this.required = 'Choose an answer to go on.',
    this.progress = _progress,
  });

  /// The back button.
  final String previous;

  /// The next button.
  final String next;

  /// The skip button.
  final String skip;

  /// The button on the last question.
  final String submit;

  /// Shown when a required question is left unanswered.
  final String required;

  /// Writes where you are: 'Question 2 of 5'.
  final String Function(int current, int total) progress;

  static String _progress(int current, int total) =>
      'Question $current of $total';
}

/// Questions one at a time, with progress above and the way on below.
///
/// ```dart
/// Questionnaire(
///   shortcuts: QuestionShortcuts.letters,
///   questions: [
///     Question(name: 'size', prompt: 'How big is your team?', required: true, choices: [
///       QuestionChoice('small', '1 to 10'), QuestionChoice('large', 'More than 10'),
///     ]),
///     Question(name: 'notes', prompt: 'Anything else?', other: 'Notes'),
///   ],
///   onSubmit: (answers) => save(answers),
/// )
/// ```
class Questionnaire extends StatefulWidget {
  const Questionnaire({
    super.key,
    required this.questions,
    required this.onSubmit,
    this.initialAnswers = const {},
    this.index,
    this.onIndexChanged,
    this.onChanged,
    this.shortcuts = QuestionShortcuts.none,
    this.showProgress = true,
    this.labels = const QuestionnaireLabels(),
    this.validator,
  });

  /// The questions, in order.
  final List<Question> questions;

  /// Given every answer, by question name, when the last is done.
  final ValueChanged<Map<String, QuestionAnswer>> onSubmit;

  /// Answers to start from: a saved, unfinished questionnaire.
  final Map<String, QuestionAnswer> initialAnswers;

  /// Which question shows, when you hold it: to send someone back to one.
  final int? index;

  /// Told the question that shows.
  final ValueChanged<int>? onIndexChanged;

  /// Told every change, to save as it goes.
  final ValueChanged<Map<String, QuestionAnswer>>? onChanged;

  /// Letters or numbers that pick answers, shown beside them.
  final QuestionShortcuts shortcuts;

  /// Where you are, as words and a bar, above the questions.
  final bool showProgress;

  /// The words on its buttons and in its messages.
  final QuestionnaireLabels labels;

  /// A check of your own on an answer: the message to show, or null when it will do.
  final String? Function(Question question, QuestionAnswer answer)? validator;

  @override
  State<Questionnaire> createState() => _QuestionnaireState();
}

class _QuestionnaireState extends State<Questionnaire> {
  late final _answers = Map<String, QuestionAnswer>.of(widget.initialAnswers);
  late int _own = widget.index ?? _firstApplying(0, 1) ?? 0;
  String? _error;
  final _item = FocusNode(debugLabel: 'Question');
  final _choiceNodes = <FocusNode>[];
  final _other = TextEditingController();
  final _otherNode = FocusNode(debugLabel: 'Other answer');
  var _forward = true;

  int get _index => widget.index ?? _own;
  Question get _question => widget.questions[_index];
  QuestionAnswer get _answer =>
      _answers[_question.name] ?? const QuestionAnswer();

  bool _applies(int i) => widget.questions[i].applies?.call(_answers) ?? true;

  /// The first question from [i] on, going [step] at a time, that applies.
  int? _firstApplying(int i, int step) {
    for (var j = i; j >= 0 && j < widget.questions.length; j += step) {
      if (_applies(j)) return j;
    }
    return null;
  }

  List<int> get _asked => [
    for (var i = 0; i < widget.questions.length; i++)
      if (_applies(i)) i,
  ];

  @override
  void initState() {
    super.initState();
    _other.text = _answer.text;
    _other.addListener(_typed);
  }

  @override
  void didUpdateWidget(Questionnaire old) {
    super.didUpdateWidget(old);
    if (widget.index != null && widget.index != old.index) _arrive();
  }

  @override
  void dispose() {
    _item.dispose();
    for (final n in _choiceNodes) {
      n.dispose();
    }
    _other.dispose();
    _otherNode.dispose();
    super.dispose();
  }

  void _set(QuestionAnswer answer) {
    setState(() {
      _answers[_question.name] = answer;
      if (answer.answered) _error = null;
    });
    widget.onChanged?.call(Map.unmodifiable(_answers));
  }

  void _typed() {
    if (_other.text == _answer.text) return;
    _set(
      QuestionAnswer(
        // One choice or words of one's own: typing clears the choice.
        picked: _question.multiple || _other.text.isEmpty ? _answer.picked : {},
        text: _other.text,
      ),
    );
  }

  void _pick(QuestionChoice choice) {
    if (!choice.enabled) return;
    final picked = Set.of(_answer.picked);
    if (_question.multiple) {
      picked.contains(choice.value)
          ? picked.remove(choice.value)
          : picked.add(choice.value);
    } else {
      picked
        ..clear()
        ..add(choice.value);
      if (_other.text.isNotEmpty) _other.clear();
    }
    _set(
      QuestionAnswer(
        picked: picked,
        text: _question.multiple ? _other.text : '',
      ),
    );
  }

  String? _check() {
    final answer = _answer;
    if (_question.required && !answer.answered) return widget.labels.required;
    if (answer.answered) return widget.validator?.call(_question, answer);
    return null;
  }

  /// Goes to question [i]: shows it, and puts focus on it.
  void _go(int i) {
    if (i == _index) return;
    _forward = i > _index;
    _error = null;
    if (widget.index == null) setState(() => _own = i);
    widget.onIndexChanged?.call(i);
    if (widget.index == null) _arrive();
  }

  void _arrive() {
    _other.removeListener(_typed);
    _other.text = _answer.text;
    _other.addListener(_typed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _item.requestFocus();
    });
  }

  /// Checks this answer, then goes on, or sends them all after the last.
  void _next() {
    final error = _check();
    if (error != null) {
      setState(() => _error = error);
      // Back to the answers, where it can be put right.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_choiceNodes.isNotEmpty ? _choiceNodes.first : _otherNode)
            .requestFocus();
      });
      return;
    }
    final next = _firstApplying(_index + 1, 1);
    if (next == null) {
      widget.onSubmit({
        for (final i in _asked)
          widget.questions[i].name:
              _answers[widget.questions[i].name] ??
              const QuestionAnswer(skipped: true),
      });
    } else {
      _go(next);
    }
  }

  void _previous() {
    final previous = _firstApplying(_index - 1, -1);
    if (previous != null) _go(previous);
  }

  void _skip() {
    _set(const QuestionAnswer(skipped: true));
    _other.clear();
    final next = _firstApplying(_index + 1, 1);
    if (next == null) {
      _next();
    } else {
      _go(next);
    }
  }

  String? _shortcut(int i) => switch (widget.shortcuts) {
    QuestionShortcuts.none => null,
    QuestionShortcuts.letters => i < 26 ? String.fromCharCode(65 + i) : null,
    QuestionShortcuts.numbers => i < 9 ? '${i + 1}' : null,
  };

  bool get _typing => _otherNode.hasFocus;

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter &&
        (keys.isMetaPressed || keys.isControlPressed)) {
      _next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter && !_typing && _answer.answered) {
      // A picked answer goes on with Enter; a focused button is pressed by it instead.
      final focused = FocusManager.instance.primaryFocus;
      if (focused == _item || _choiceNodes.contains(focused)) {
        _next();
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.enter && _typing && _other.text.isNotEmpty) {
      _next();
      return KeyEventResult.handled;
    }
    if (_typing) return KeyEventResult.ignored;
    final rtl = isRtl(context);
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.arrowUp) {
      final nodes = [
        ..._choiceNodes.where((n) => n.canRequestFocus),
        if (_question.other != null) _otherNode,
      ];
      if (nodes.isEmpty) return KeyEventResult.ignored;
      final at = nodes.indexOf(FocusManager.instance.primaryFocus!);
      final by = k == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final to = at < 0
          ? (by > 0 ? 0 : nodes.length - 1)
          : (at + by).clamp(0, nodes.length - 1);
      nodes[to].requestFocus();
      // One choice: moving to it picks it, as radio buttons do.
      final c = to < _question.choices.length && !_question.multiple
          ? _question.choices.where((c) => c.enabled).elementAtOrNull(to)
          : null;
      if (c != null) _pick(c);
      return KeyEventResult.handled;
    }
    final back = rtl
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    final on = rtl
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    if (k == back) {
      _previous();
      return KeyEventResult.handled;
    }
    if (k == on && (_answer.answered || _answer.skipped)) {
      _next();
      return KeyEventResult.handled;
    }
    if (!keys.isMetaPressed && !keys.isControlPressed && !keys.isAltPressed) {
      final label = e.character?.toUpperCase();
      for (final (i, c) in _question.choices.indexed) {
        if (label != null && _shortcut(i) == label && c.enabled) {
          _pick(c);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    final q = _question;
    final asked = _asked;
    final at = asked.indexOf(_index);
    final last = _firstApplying(_index + 1, 1) == null;
    final first = _firstApplying(_index - 1, -1) == null;
    while (_choiceNodes.length < q.choices.length) {
      final i = _choiceNodes.length;
      _choiceNodes.add(
        FocusNode(
          debugLabel: 'Choice',
          // Enter on an answer goes on, taking this one when none is picked yet. It
          // comes before the answer's own Enter, which would only pick it again.
          onKeyEvent: (node, e) {
            if (e is! KeyDownEvent ||
                e.logicalKey != LogicalKeyboardKey.enter ||
                HardwareKeyboard.instance.isMetaPressed ||
                HardwareKeyboard.instance.isControlPressed) {
              return KeyEventResult.ignored;
            }
            final choices = _question.choices;
            if (!_answer.answered && i < choices.length) _pick(choices[i]);
            _next();
            return KeyEventResult.handled;
          },
        ),
      );
    }
    final item = Focus(
      focusNode: _item,
      child: Semantics(
        container: true,
        label: q.prompt,
        hint: q.description,
        child: Column(
          key: ValueKey(_index),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                q.prompt,
                style: t.text.base.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (q.description != null) ...[
              const SizedBox(height: 4),
              Text(
                q.description!,
                style: t.text.sm.copyWith(color: c.mutedForeground),
              ),
            ],
            const SizedBox(height: 16),
            for (final (i, choice) in q.choices.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              _Choice(
                choice: choice,
                multiple: q.multiple,
                checked: _answer.picked.contains(choice.value),
                invalid: _error != null,
                shortcut: _shortcut(i),
                focusNode: _choiceNodes[i],
                onPressed: () => _pick(choice),
              ),
            ],
            if (q.other != null) ...[
              if (q.choices.isNotEmpty) const SizedBox(height: 8),
              Input(
                controller: _other,
                focusNode: _otherNode,
                semanticLabel: q.other,
                placeholder: q.otherPlaceholder ?? q.other,
                error: _error != null,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: t.text.sm.copyWith(color: c.destructive),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showProgress) ...[
            Row(
              children: [
                Text(
                  widget.labels.progress(at + 1, asked.length),
                  style: t.text.xs.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Progress(
                    value: (at + 1) / asked.length,
                    semanticLabel: widget.labels.progress(at + 1, asked.length),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          AnimatedSwitcher(
            duration: t.duration,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: Offset(_forward ? .04 : -.04, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [
                // The one leaving is out of the way of the eye, the hand and the ear.
                for (final p in previous)
                  IgnorePointer(child: ExcludeSemantics(child: p)),
                ?current,
              ],
            ),
            child: KeyedSubtree(key: ValueKey(_index), child: item),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (!first)
                Button(
                  variant: ButtonVariant.ghost,
                  onPressed: _previous,
                  leading: AshlarIcon(
                    isRtl(context)
                        ? AshlarIconsRoundedStroke.arrowRight
                        : AshlarIconsRoundedStroke.arrowLeft,
                  ),
                  child: Text(widget.labels.previous),
                ),
              const Spacer(),
              if (!q.required && !_answer.answered) ...[
                Button(
                  variant: ButtonVariant.outline,
                  onPressed: _skip,
                  child: Text(widget.labels.skip),
                ),
                const SizedBox(width: 8),
              ],
              Button(
                onPressed: _next,
                trailing: last
                    ? null
                    : AshlarIcon(
                        isRtl(context)
                            ? AshlarIconsRoundedStroke.arrowLeft
                            : AshlarIconsRoundedStroke.arrowRight,
                      ),
                child: Text(last ? widget.labels.submit : widget.labels.next),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// An answer as a card to pick: a round mark for one choice, a box for several.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.choice,
    required this.multiple,
    required this.checked,
    required this.invalid,
    required this.shortcut,
    required this.focusNode,
    required this.onPressed,
  });

  final QuestionChoice choice;
  final bool multiple, checked, invalid;
  final String? shortcut;
  final FocusNode focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AshlarTheme.of(context);
    final c = t.colors;
    // One choice reads as a radio button, several as checkboxes.
    return Pressable(
      focusNode: focusNode,
      onPressed: choice.enabled ? onPressed : null,
      checked: checked,
      exclusive: !multiple,
      semanticLabel: [choice.label, ?choice.description].join(', '),
      builder: (context, states) => AnimatedContainer(
        duration: t.duration,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked
              ? c.primary.withValues(alpha: .05)
              : (states.hovered ? c.muted.withValues(alpha: .5) : null),
          borderRadius: BorderRadius.circular(t.radiusLg),
          border: Border.all(
            color: states.focused
                ? c.ring
                : invalid
                ? c.destructive
                : (checked ? c.primary : c.border),
          ),
        ),
        child: Opacity(
          opacity: choice.enabled ? 1 : .5,
          child: Row(
            children: [
              AnimatedContainer(
                duration: t.duration,
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: checked ? c.primary : null,
                  shape: multiple ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: multiple ? BorderRadius.circular(4) : null,
                  border: Border.all(color: checked ? c.primary : c.input),
                ),
                child: checked
                    ? (multiple
                          ? AshlarIcon(
                              AshlarIconsRoundedStroke.check,
                              size: 12,
                              color: c.primaryForeground,
                            )
                          : Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: c.primaryForeground,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ))
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      choice.label,
                      style: t.text.sm.copyWith(fontWeight: FontWeight.w500),
                    ),
                    if (choice.description != null)
                      Text(
                        choice.description!,
                        style: t.text.sm.copyWith(color: c.mutedForeground),
                      ),
                  ],
                ),
              ),
              if (shortcut != null) ...[
                const SizedBox(width: 8),
                ExcludeSemantics(child: Kbd(child: Text(shortcut!))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
