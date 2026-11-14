/// Why the page could not be taken, in words for the person.
class PageTrouble implements Exception {
  const PageTrouble(this.why);
  final String why;

  @override
  String toString() => why;
}
