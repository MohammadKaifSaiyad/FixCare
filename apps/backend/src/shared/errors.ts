/** Base for all expected, mapped application errors. */
export class AppError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
    readonly code: string,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(message = 'Validation failed') { super(message, 400, 'VALIDATION_ERROR'); }
}
export class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized') { super(message, 401, 'UNAUTHORIZED'); }
}
// Forbidden / NotFound / Conflict take an optional machine `code` so a client can branch on a stable
// identifier (e.g. JOB_NOT_FOUND, ESTIMATE_CHANGED) instead of matching the human message.
export class ForbiddenError extends AppError {
  constructor(message = 'Forbidden', code = 'FORBIDDEN') { super(message, 403, code); }
}
export class NotFoundError extends AppError {
  constructor(message = 'Not found', code = 'NOT_FOUND') { super(message, 404, code); }
}
export class TooManyRequestsError extends AppError {
  constructor(message = 'Too many requests') { super(message, 429, 'TOO_MANY_REQUESTS'); }
}
export class ConflictError extends AppError {
  constructor(message = 'Conflict', code = 'CONFLICT') { super(message, 409, code); }
}
export class UnprocessableError extends AppError {
  constructor(message = 'Unprocessable', code = 'UNPROCESSABLE') { super(message, 422, code); }
}
