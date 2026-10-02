enum FailureKind { network, unauthorized, forbidden, notFound, rateLimited, validation, server, unknown }

FailureKind failureKindFromStatus(int? status) {
  switch (status) {
    case 401: return FailureKind.unauthorized;
    // The backend saying "not yours" / "gone" — distinct kinds so callers (e.g. the job-detail poll)
    // can stop instead of treating them like a transient failure.
    case 403: return FailureKind.forbidden;
    case 404: return FailureKind.notFound;
    case 429: return FailureKind.rateLimited;
    case 400: return FailureKind.validation;
    // A gateway/request timeout is transient (retry, not a rejection) — never the backend saying no.
    case 408: return FailureKind.network;
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

  /// The backend's stable machine code from its `{code, message}` error envelope (e.g. `JOB_NOT_FOUND`,
  /// `ESTIMATE_CHANGED`) — callers branch on this, never on [message]. Null when the response carried none
  /// (a network error, a 404 from a route the backend doesn't have).
  final String? code;
  const Failure(this.kind, this.message, {this.code});
}

/// The `code` of the backend's `{code, message}` error envelope (errorHandler.ts), or null when absent.
String? errorCodeOf(dynamic data) => (data is Map && data['code'] is String) ? data['code'] as String : null;
