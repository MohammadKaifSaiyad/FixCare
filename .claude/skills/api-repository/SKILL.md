---
name: api-repository
description: Use when adding a data-layer repository or API call in apps/customer or apps/technician (Flutter). Templates a dio-based repository that returns domain entities or a typed Failure (never raw JSON), with freezed models, secure-storage tokens, and an in-app retry queue for deferred work. UI must never call dio directly.
---

# API Repository (FixCare apps)

The mobile data layer. All network access goes through a repository; the UI depends
on domain entities and typed failures, never on dio or JSON.

## Pattern

```dart
// data/booking_repository.dart
class BookingRepository {
  final Dio _dio;          // injected; configured with auth interceptor
  BookingRepository(this._dio);

  Future<Result<Booking, Failure>> getBooking(String id) async {
    try {
      final res = await _dio.get('/v1/bookings/$id');
      return Ok(Booking.fromJson(res.data));   // map to DOMAIN entity
    } on DioException catch (e) {
      return Err(_mapFailure(e));               // typed Failure, never raw error/JSON
    }
  }
}
```

## Rules baked in (coding-conventions.md API & Data, Storage)
- **UI never calls dio directly** — only repositories do.
- Repositories return **domain entities or a typed `Failure`** (sealed/`freezed` union),
  never raw JSON or `Map`.
- **Models use `freezed` + `json_serializable`.**
- **Auth tokens in `flutter_secure_storage`**; attach via a dio interceptor; handle
  401 → refresh-token rotation centrally.
- **No PII in logs** (phone, VPA, address) — scrub before any logging/analytics.
- **In-app retry queue** (NOT BullMQ — that's backend-only): for deferred/offline work
  (e.g. queued photo upload), retry with backoff locally; surface state to the user.
- Map backend DTOs to app domain types — don't let server shapes leak into the UI.

## Process
1. Define the domain entity + `Failure` union (freezed).
2. Implement the repository with try/catch → `Result`/typed failure mapping.
3. Wire the dio auth interceptor + 401 refresh once, app-wide.
4. For deferred work, add a local retry queue with backoff.
5. Run `flutter-widget-reviewer` before merge.

> Reference: `docs/05-development/coding-conventions.md` (API & Data, Storage), `docs/03-tech-stack/mobile-stack.md` (Backend Communication).
