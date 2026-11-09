import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';

void main() {
  test('comments on the design go ahead of the message as parts of the design', () {
    final text = ChatViewModel.commentsText([
      (
        id: 1,
        quote:
            '${ChatViewModel.designComment}"Today" (design/home.html), the h2 "Today" at body > div > h2',
        note: 'Make it friendlier',
      ),
    ]);
    expect(text, startsWith('About these parts of the design'));
    expect(text, contains('> ${ChatViewModel.designComment}"Today" (design/home.html)'));
    expect(text, endsWith('Make it friendlier'));
    final mixed = ChatViewModel.commentsText([
      (
        id: 1,
        quote: '${ChatViewModel.designComment}"Today" (design/home.html), the whole screen',
        note: '',
      ),
      (id: 2, quote: 'Some words from the chat', note: 'And this'),
    ]);
    expect(mixed, startsWith('About these parts of the conversation and the design'));
  });
}
