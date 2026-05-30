---
name: scaffold-module
description: Use when creating a new backend feature module in apps/backend (e.g. "add a disputes module", "scaffold the payments module"). Generates the canonical 7-file module structure with auth-first, ownership-check, and service-layer rules pre-wired. Backend (Fastify/Prisma) only — not for Flutter or admin.
---

# Scaffold a Backend Module

Generate a new feature module under `apps/backend/src/modules/<feature>/` following
the **exact** pattern in `docs/04-architecture/module-structure.md`. Do not invent a
different layout.

## When to use
- A new backend feature with 3+ related endpoints, or distinct business logic that
  doesn't fit an existing module (per module-structure.md "When to Add a New Module").
- NOT for: a single endpoint (put it in an existing module), pure utilities (use
  `shared/`), or third-party wrappers (use `shared/third-party/`).

## The 7-file structure (create all that apply)

```
modules/<feature>/
├── <feature>.routes.ts          # Fastify route registration ONLY
├── <feature>.service.ts         # ALL business logic, orchestration, transactions
├── <feature>.repository.ts      # Prisma access (only if queries are complex)
├── <feature>.schemas.ts         # Zod schemas; infer TS types via z.infer
├── <feature>.types.ts           # Enums / TS types not derived from Zod or Prisma
├── <feature>.events.ts          # BullMQ event-name constants this module emits
└── __tests__/
    └── <feature>.test.ts        # written FIRST, via test-driven-development
```

## Rules baked into every generated module (from coding-conventions.md)

- **Route handlers** parse/validate input (Zod), call the service, shape the DTO
  response. **No business logic, no Prisma** in routes.
- **Auth check is the first line** of every protected handler. Then an **ownership
  check** — a user may only access their own resources (verify, don't just authenticate).
- **Services** hold all logic. Multi-step financial operations run in a transaction.
- **Never return raw Prisma objects** — map to an explicit DTO type.
- **Inter-module communication** via service calls or events only — never a
  cross-module DB query, never importing another module's routes.
- **No `any`** — use `unknown` and narrow.
- If the feature touches money: every financial mutation writes an `AuditLog` entry
  in the same transaction (see the `audit-logged-mutation` skill) and uses integer
  paise via `shared/utils/currency.ts`.

## Process
1. Confirm the module name and which of the 7 files it actually needs (skip
   `repository.ts` if queries are simple; skip `events.ts` if it emits none).
2. Follow `test-driven-development`: write `__tests__/<feature>.test.ts` FIRST (RED).
3. Generate the route → service → (repository) skeleton to make tests pass (GREEN).
4. Register the module's routes in the Fastify app following existing registration.
5. Cross-check against the "What Claude Code Should Push Back On" list in
   coding-conventions.md before claiming done.

> Reference: `docs/04-architecture/module-structure.md`, `docs/05-development/coding-conventions.md`.
