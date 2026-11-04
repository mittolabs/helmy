import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/filing.dart';

void main() {
  const chats = [
    (
      id: 'money',
      text: 'Finances. Monthly budget for November. Paying off the car loan. Savings goal',
    ),
    (
      id: 'rika',
      text: 'Rika app. Design the onboarding screens. Build sign-in with Apple. Invites expire',
    ),
    (id: 'site', text: 'Mittolabs site. Home page hero copy. Pricing page layout'),
    (id: 'trip', text: 'Trip to Lisbon. Flights and hotels in March'),
  ];

  test('a clear match is filed', () {
    final f = file("What's left in my budget this month after the car loan payment?", chats);
    expect((f.kind, f.best), (FilingKind.file, 'money'));
  });

  test('another clear one, in other words of the same topic', () {
    final f = file('The onboarding screens for Rika need a skip button', chats);
    expect((f.kind, f.best), (FilingKind.file, 'rika'));
  });

  test('nothing alike: a chat of its own', () {
    final f = file('Write a haiku about rain on a tin roof', chats);
    expect(f.kind, FilingKind.own);
  });

  test('alike two chats at once: the person is asked', () {
    final f = file('Add the pricing for the Rika app to the site page', chats);
    expect(f.kind, FilingKind.ask);
    expect({f.best, f.runnerUp}, {'rika', 'site'});
  });

  test('words are compared by their stems, and common words do not count', () {
    expect(words('Designing the invites'), ['design', 'invit']);
    expect(file('', chats).kind, FilingKind.own);
    expect(file('budget', const []).kind, FilingKind.own);
  });
}
