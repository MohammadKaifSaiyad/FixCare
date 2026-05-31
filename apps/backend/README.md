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

## Local development
Requires the Docker data stack running from the repo root (`docker compose up -d`
→ Postgres+PostGIS + Redis) and Node 22 (`nvm use` honours the repo `.nvmrc`).

```bash
nvm use                 # Node 22 (per .nvmrc)
pnpm install            # from repo root or here
pnpm db:migrate         # apply migrations to fixcare_dev
pnpm test               # Vitest schema tests (run against fixcare_test)
```

Env: copy `.env.example` → `.env`. Tests require `TEST_DATABASE_URL` (the
`fixcare_test` DB) and fail fast if it's unset.

## Status
Scaffolded; **auth + users schema slice** implemented (`User`, `RefreshToken`,
`Customer`/`Technician`/`Merchant`/`Admin`, `AuditLog`) with passing tests and an
initial migration. Auth module (OTP/JWT/refresh service + routes) is next.
