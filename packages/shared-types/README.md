# packages/shared-types — Shared API Contract Types

TypeScript types/interfaces for the API contract, shared between `apps/backend`
(producer) and `apps/admin` (consumer). Keeping them here lets a contract change
and its consumers move in **one atomic PR** — the key advantage of the monorepo
over separate repos.

Flutter apps do not consume this package (different toolchain); they mirror
contracts in Dart independently.

## Status
**Seam folder, not yet populated.** Created now to mark where shared contracts
go. Populate when the backend's first API contract lands (Months 1-2). Until
then this package is intentionally empty.
