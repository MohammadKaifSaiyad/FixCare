enum FailureKind { network, unauthorized, rateLimited, validation, server, unknown }

FailureKind failureKindFromStatus(int? status) {
  switch (status) {
    case 401: return FailureKind.unauthorized;
    case 429: return FailureKind.rateLimited;
    case 400: return FailureKind.validation;
    case null: return FailureKind.unknown;
    default: return status >= 500 ? FailureKind.server : FailureKind.unknown;
  }
}

sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Failure<T> extends Result<T> {
  final FailureKind kind;
  final String message;
  const Failure(this.kind, this.message);
}
