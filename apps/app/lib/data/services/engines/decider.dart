import 'dart:convert';
import 'dart:io';
import 'dart:math' show exp;

import '../../../domain/models/engine.dart';
import 'codex/codex_engine.dart';

/// What the model on this Mac decided about a message.
typedef Decision = ({
  /// It is sure (0.9 or more) the message needs no tools and no service: a
  /// plain answer will do.
  bool direct,

  /// Services or abilities it named the message as needing.
  Set<Capability> services,
});

/// Asks the model on this Mac typed questions about a message: one answer held
/// to a fixed list of options, with the probability behind it (the System One
/// pattern, through Ollama's structured output and log probabilities).
///
/// Measured on 40 labeled messages with qwen3:8b (2026-11-03): 38 of 40 right
/// on "plain answer or tools", with its two mistakes at 0.85 and 0.50 against
/// 0.99 for right answers; 39 of 40 on which service; about half a second a
/// question once loaded.
class Decider {
  new({required this._model, this.host = 'http://localhost:11434'});

  /// The model chosen in settings; null for the first one pulled.
  final String? Function() _model;
  final String host;

  /// How sure it must be that no tools are needed before a plain answer.
  static const sureEnough = .9;

  static const _route = (
    instructions: 'A developer sent this message to a coding assistant that works in their project folder. How should it be handled?',
    criteria: {
      'direct': 'It can be answered from general knowledge alone: greetings, thanks, explanations, opinions, or writing a standalone code snippet. Nothing of the user\'s needs to be looked at or changed.',
      'tools': 'It needs the user\'s own things: reading or changing files in their project, running commands, git, logs, their email, calendar, drive, chat or notes, or making an image.',
    },
  );

  static const _service = (
    instructions: 'Which outside service, if any, does this message need?',
    criteria: {
      'none': 'None of these services; general questions or work on the project\'s own files.',
      'image': 'Making a new picture, icon, logo or illustration.',
      'drive': 'The user\'s Google Drive files and documents.',
      'gmail': 'The user\'s email inbox: reading, searching or replying to emails.',
      'calendar': 'The user\'s calendar: meetings, events, availability.',
      'slack': 'The user\'s Slack channels and messages.',
      'notion': 'The user\'s Notion pages and databases.',
    },
  );

  static const _capabilities = {
    'image': Capability.imageGeneration,
    'drive': Capability.googleDrive,
    'gmail': Capability.gmail,
    'calendar': Capability.googleCalendar,
    'slack': Capability.slack,
    'notion': Capability.notion,
  };

  /// Decides about [message]: which services it needs, and, when [route],
  /// whether a plain answer will do. With [onlyIfLoaded] it asks only when the
  /// model is already in memory, so routing never loads one. Null when there is
  /// no model, or it does not answer within [timeout]: the caller goes on as if
  /// it had not asked.
  Future<Decision?> decide(
    String message, {
    required bool route,
    bool onlyIfLoaded = false,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final model = await _resolveModel();
    if (model == null) return null;
    if (onlyIfLoaded && !await _loaded(model)) return null;
    try {
      final (service, plain) = await (
        _choose(model, _service, message),
        route ? _choose(model, _route, message) : Future.value(null),
      ).wait.timeout(timeout);
      if (service == null || (route && plain == null)) return null;
      final services = {?_capabilities[service.answer]};
      return (
        direct: route && plain!.answer == 'direct' && plain.p >= sureEnough && services.isEmpty,
        services: services,
      );
    } on Object {
      return null;
    }
  }

  Future<String?> _resolveModel() async {
    final models = await CodexEngine.ollamaModels();
    if (models == null || models.isEmpty) return null;
    final chosen = _model();
    return chosen != null && models.contains(chosen) ? chosen : models.first;
  }

  Future<bool> _loaded(String model) async {
    final j = await _call('GET', '/api/ps', null, const Duration(seconds: 2));
    return (j?['models'] as List? ?? const []).whereType<Map>().any(
      (m) => m['name'] == model || m['model'] == model,
    );
  }

  /// One typed question: the answer is held to the options, and its
  /// probability read from the first token of the chosen option.
  Future<({String answer, double p})?> _choose(
    String model,
    ({String instructions, Map<String, String> criteria}) q,
    String message,
  ) async {
    final options = q.criteria.keys.toList();
    final system =
        '${q.instructions}\nAnswer with one option:\n'
        '${[for (final o in options) '- $o: ${q.criteria[o]}'].join('\n')}';
    final j = await _call('POST', '/api/chat', {
      'model': model,
      'think': false,
      'stream': false,
      'logprobs': true,
      'top_logprobs': 5,
      'options': {'temperature': 0},
      'format': {
        'type': 'object',
        'properties': {
          'answer': {'type': 'string', 'enum': options},
        },
        'required': ['answer'],
      },
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': message.length > 4000 ? message.substring(0, 4000) : message},
      ],
    }, const Duration(seconds: 60));
    final content = (j?['message'] as Map?)?['content'];
    if (content is! String) return null;
    final answer = (jsonDecode(content) as Map)['answer'];
    if (answer is! String || !options.contains(answer)) return null;
    return (answer: answer, p: probabilityOf(answer, j?['logprobs']));
  }

  /// The probability of [answer], from the first token of it in [logprobs];
  /// 0.5 when it cannot be found, so an unread answer never counts as sure.
  static double probabilityOf(String answer, Object? logprobs) {
    for (final t in (logprobs as List? ?? const []).whereType<Map>()) {
      final token = '${t['token']}'.trim();
      if (token.isNotEmpty && answer.startsWith(token) && token != '"') {
        final lp = (t['logprob'] as num?)?.toDouble();
        if (lp != null) return exp(lp);
      }
    }
    return .5;
  }

  Future<Map<String, Object?>?> _call(
    String method,
    String path,
    Map<String, Object?>? body,
    Duration timeout,
  ) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.openUrl(method, Uri.parse('$host$path'));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return (jsonDecode(await res.transform(utf8.decoder).join()) as Map).cast();
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
