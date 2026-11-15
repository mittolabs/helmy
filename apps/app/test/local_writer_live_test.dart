@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/data/repositories/chat_keeper.dart';
import 'package:helmy/data/services/local_writer.dart';
import 'package:helmy/domain/models/chat_item.dart';

void main() {
  test("the keeper's prompts on this Mac's models (local, no cloud)", () async {
    final items = <ChatItem>[
      UserMessage('I want to plan my November budget. Income is 3,400 after tax.'),
      AssistantText('a:0', 'Rent 1,100, food 450, transport 180. That leaves 1,670.'),
      UserMessage(
        'Put 1,000 to the car loan and keep the rest as savings, but I am not sure about the car insurance yet.',
      ),
      AssistantText(
        'b:0',
        'Done: 1,000 to the car loan, 670 to savings. Car insurance is still to decide; quotes come next week.',
      ),
    ];
    final text = ChatKeeper.transcript(items);
    for (final model in ['qwen3:0.6b', 'qwen3:8b-16k']) {
      final w = LocalWriter(model: () => model);
      final watch = Stopwatch()..start();
      final s = await w.write(
        'Here is a conversation between a person and an assistant.\n\n<conversation>\n$text\n</conversation>\n\n'
        'In one line of at most 15 words, say what it is about and where it stands. No quotes, no preamble.',
        maxTokens: 60,
      );
      // ignore: avoid_print
      print(
        '--- $model (${watch.elapsedMilliseconds} ms, tokens ${s?.promptTokens}+${s?.outputTokens})\n'
        'summary: ${s == null ? null : ChatKeeper.summaryFrom(s.text)}',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
