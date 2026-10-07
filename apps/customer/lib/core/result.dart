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

  /// The backend's stable machine code from its `{code, message}` error envelope (e.g. `ROLE_MISMATCH`) —
  /// callers branch on this, never on [message]. Null when the response carried none.
  final String? code;
  const Failure(this.kind, this.message, {this.code});
}

/// The `code` of the backend's `{code, message}` error envelope, or null when absent.
String? errorCodeOf(dynamic data) => (data is Map && data['code'] is String) ? data['code'] as String : null;

