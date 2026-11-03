/// Anything that can fail returns a [Result], as in Flutter's architecture guide.
sealed class Result<T> {
  const new();

  const factory ok(T value) = Ok<T>;
  const factory error(Exception error) = Error<T>;
}

final class Ok<T> extends Result<T> {
  const new(this.value);
  final T value;
}

final class Error<T> extends Result<T> {
  const new(this.error);
  final Exception error;
}
