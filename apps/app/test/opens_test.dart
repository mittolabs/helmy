import 'package:flutter_test/flutter_test.dart';
import 'package:helmy/domain/opens.dart';

/// Search puts the chats opened most lately first: a count halving every two weeks.
void main() {
  final now = DateTime(2026, 11, 15, 12);

  test('a count halves every two weeks', () {
    expect(openScore(8, now, now), 8);
    expect(openScore(8, now.subtract(const Duration(days: 14)), now), closeTo(4, 1e-9));
    expect(openScore(8, now.subtract(const Duration(days: 28)), now), closeTo(2, 1e-9));
    expect(openScore(3, null, now), 0, reason: 'never opened');
  });

  test('an open adds one to what is left of the count', () {
    final o = opened(4, now.subtract(const Duration(days: 14)), now);
    expect(o.score, closeTo(3, 1e-9));
    expect(o.at, now);
    // Opened often a month ago ranks below opened twice this week.
    final old = openScore(10, now.subtract(const Duration(days: 60)), now);
    final lately = openScore(2, now.subtract(const Duration(days: 2)), now);
    expect(lately, greaterThan(old));
  });
}
