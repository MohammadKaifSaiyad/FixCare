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
  const Failure(this.kind, this.message);
}
