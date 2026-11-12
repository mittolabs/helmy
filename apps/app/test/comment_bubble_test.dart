import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/ui/chat/view_models/chat_view_model.dart';

void main() {
  test('a message with comments shows the parts and notes, not the instruction', () {
    final text = ChatViewModel.commentsText([
      (
        id: 0,
        quote:
            '${ChatViewModel.designComment}"Rise Bakery · Home" (design/index.html), the h2 '
            '"Your loaf, set aside." at body > section#weekend > div > div:nth-of-type(1) > h2',
        note: 'Make this stand out more',
      ),
    ]);
    final split = ChatViewModel.splitComments('$text\n\nAnd keep it warm.')!;
    expect(split.comments.single.part, 'Rise Bakery · Home, the h2 "Your loaf, set aside."');
    expect(split.comments.single.note, 'Make this stand out more');
    expect(split.rest, 'And keep it warm.');
    expect(ChatViewModel.splitComments('Just a message'), isNull);
  });
}
