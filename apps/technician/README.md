# apps/technician — FixCare Technician App

Flutter 3.x (Android only V1) + Riverpod + go_router + dio. The technician-side
app: onboarding + KYC, go online/offline, accept jobs, navigate, the arrival &
completion handshakes, 3 mandatory repair photos, wallet + cash debt + trust score.

> **Naming:** the technician is the verified person who performs repairs. The
> public/product term and all code/DB use **Technician** (not "Worker"). See
> [`docs/adrs/ADR-0003-worker-to-technician.md`](../../docs/adrs/ADR-0003-worker-to-technician.md).
> Background-job "workers" (BullMQ) are unrelated and keep the "worker" term.

## Build timing
Built **Months 7-9** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md),
after the customer app.

## Toolchain note
Uses its own `pubspec.yaml` (Dart/Flutter). **Not** part of the root pnpm
workspace — see [`docs/adrs/ADR-0001-monorepo.md`](../../docs/adrs/ADR-0001-monorepo.md).

> Empty scaffold. Actual code lands in the Months 7-9 build phase.
