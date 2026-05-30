# apps/customer — FixCare Customer App

Flutter 3.x (Android only V1) + Riverpod + go_router + dio. Customer books →
tracks → pays → rates from mobile, with real-time job updates.

Mobile architecture & conventions: [`docs/03-tech-stack/mobile-stack.md`](../../docs/03-tech-stack/mobile-stack.md)
and the Flutter section of [`docs/05-development/coding-conventions.md`](../../docs/05-development/coding-conventions.md).

## Build timing
Built **Months 5-6** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md).
Built before the technician app to validate customer demand before investing in
supply-side tooling.

## Toolchain note
Uses its own `pubspec.yaml` (Dart/Flutter). **Not** part of the root pnpm
workspace — see [`docs/adrs/ADR-0001-monorepo.md`](../../docs/adrs/ADR-0001-monorepo.md).

> Empty scaffold. Actual code lands in the Months 5-6 build phase.
