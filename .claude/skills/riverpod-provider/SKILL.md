---
name: riverpod-provider
description: Use when adding a standalone Riverpod provider or state notifier in apps/customer or apps/technician (Flutter) without scaffolding a whole feature. Templates the loading/error/data state pattern. For a full feature use flutter-feature instead; use this for smaller state-only additions.
---

# Riverpod Provider (FixCare apps)

State management is **Riverpod 2.x everywhere** (`mobile-stack.md`) — never Bloc,
Provider, or GetX. Use this for a focused provider; for a whole feature, use the
`flutter-feature` skill (which composes providers into data/domain/presentation).

## Pattern

```dart
// presentation/<thing>_providers.dart
final bookingProvider =
    AsyncNotifierProvider<BookingNotifier, Booking>(BookingNotifier.new);

class BookingNotifier extends AsyncNotifier<Booking> {
  @override
  Future<Booking> build() async {
    // ref.watch dependencies; return initial state (AsyncValue handles loading/error)
    final repo = ref.read(bookingRepositoryProvider);
    final result = await repo.getBooking(/* id */);
    return result.fold((b) => b, (failure) => throw failure);  // surfaces as AsyncError
  }
}
```

## Rules baked in
- **Riverpod only** — no Bloc/Provider/GetX mixed in.
- Use **`AsyncValue`** (AsyncNotifier/FutureProvider) so **loading / error / data**
  states are explicit in the UI — never a bare `bool isLoading`.
- Providers read **repositories** (which return domain entities / typed `Failure`) —
  providers never call dio directly (see `api-repository`).
- Keep providers **testable**: no Flutter widget imports in notifier logic.
- Dispose/auto-dispose appropriately to avoid leaks on low-end devices.
- No PII in any logging from providers.

## Process
1. Decide scope: standalone provider (this skill) vs full feature (`flutter-feature`).
2. Define the notifier reading a repository; model state as `AsyncValue`.
3. Render loading/error/data in the widget via `ref.watch(...).when(...)`.
4. Unit-test the notifier with the repository mocked.

> Reference: `docs/05-development/coding-conventions.md` (Flutter Architecture), `docs/03-tech-stack/mobile-stack.md` (State Management).
