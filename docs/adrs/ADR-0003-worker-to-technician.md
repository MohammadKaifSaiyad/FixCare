# ADR-0003 — "Worker" → "Technician" naming

**Status:** Accepted · **Date:** 2026-05-30

## Context

The original docs called the verified person who performs repairs a **"Worker"**.
That term reads as low-status in public/branding scope and felt off for both
customers (trust signal) and the people doing the work. We needed one name used
everywhere — public branding, app folder, code, DB, and docs — to avoid the
confusion of branding one way ("Pro") while coding another ("worker").

## Decision

Use **"Technician"** everywhere for the human repair professional:

- App / folder: `apps/technician`
- Code & DB: `model Technician`, `UserRole.TECHNICIAN`, `technicians/` module,
  `techniciansService`, `technician_id`, state `CANCELLED_BY_TECHNICIAN`
- Docs & prose: "Technician" throughout

Considered and rejected: **Pro** (generic; collides with "prod/production" in code),
**Partner** (less specific about the skill), **Expert** (overpromises for entry-level).
"Technician" is honest, professional, and reads cleanly as both a public term and a
code identifier.

## Disambiguation rule (CRITICAL — do not over-apply the rename)

The word **"worker" in the background-job / queue sense is a different concept and
KEEPS the "worker" term.** Never rename these to "technician":

| Keep as "worker" (background-job sense) | Rename to "technician" (human sense) |
|---|---|
| `workers/` folder (BullMQ entry), `workers/index.ts` | `technicians/` feature module |
| `*.worker.ts` (e.g. `notifications.worker.ts`, `dispatch.worker.ts`) | `Technician` Prisma model |
| "BullMQ workers", "background workers", "worker process" | `UserRole.TECHNICIAN` |
| docker-compose `workers:` service | `technician_id`, `techniciansService`, `technicianId` |
| Hetzner "API + workers separated" | prose: "the technician", "technician app" |

When in doubt: is it a *person performing repairs* (→ Technician) or a *process
running queued jobs* (→ worker)?

## Consequences

- All existing docs were updated in one pass; this ADR is the record so the
  rename isn't re-litigated and the disambiguation rule is applied consistently in
  future code (the upcoming Prisma schema, modules, and both apps).
- Any new code must follow the table above. Misnaming a BullMQ worker as
  "technician" (or vice-versa) is a review-blocking error.
