# apps/backend — FixCare API

Node.js 22 + Fastify 5 + TypeScript (strict) + Prisma 6 + PostgreSQL 16/PostGIS + Redis 7 + BullMQ.

**Modular monolith.** Folder organization and module pattern: see
[`docs/04-architecture/module-structure.md`](../../docs/04-architecture/module-structure.md).
Conventions enforced every session: [`docs/05-development/coding-conventions.md`](../../docs/05-development/coding-conventions.md).

## Build timing
First component built — **Months 1-2** (backend foundation) per
[`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md).
Deploys to `api.fixcare.in`.

## Workspace
Part of the root **pnpm workspace** (see `/pnpm-workspace.yaml`). Shares API
contract types with `apps/admin` via `packages/shared-types`.

> Empty scaffold. Actual code lands in the Months 1-2 build phase.
