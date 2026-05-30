---
name: prisma-schema-model
description: Use when adding or changing a Prisma model in apps/backend/prisma/schema.prisma — any new entity, money/financial field, or PII field. Enforces FixCare data rules: integer-paise money, masked-Aadhaar storage, soft-delete on users/financial records, audit relations, and the migrate workflow. Backend only.
---

# Prisma Schema Model (FixCare)

Model entities the FixCare way. The schema is the foundation every Golden Rule
rests on — get the field types and delete/audit semantics right here.

## Rules baked in (from coding-conventions.md + Golden Rules)

- **Money is integer paise.** Money columns are `Int` (or `BigInt` if it can exceed
  ~21M paise) named `*Paise` (e.g. `amountPaise`, `visitFeePaise`). **Never** `Float`/
  `Decimal` for currency. (Golden rule: floats for money is a push-back item.)
- **Never store raw Aadhaar.** Store only `aadhaarLast4 String` + a separate
  verified-hash (in the KYC store), never the full number. Mask everywhere (Golden Rule 6).
- **Soft-delete** users and all financial records — add `deletedAt DateTime?`; never
  hard-delete (audit trail). Filter `deletedAt: null` in queries.
- **Audit relations.** Financial models relate to `AuditLog`; every financial
  mutation writes an audit row in the same transaction (Golden Rule 5 — see the
  `audit-logged-mutation` skill).
- **Timestamps** on every model: `createdAt DateTime @default(now())`,
  `updatedAt DateTime @updatedAt`.
- **No PII in indexes/logs.** Don't index raw phone/VPA/Aadhaar.
- **PostGIS** location columns use the documented raw-SQL/`Unsupported` pattern, queried
  only via `shared/geo/` helpers — never inline raw SQL in services.
- **Naming:** the technician actor is `model Technician` / `TECHNICIAN` (never "Worker"
  — that word is reserved for BullMQ background jobs; see ADR-0003).

## Pattern

```prisma
// =============================================================================
// <SECTION>  (logical comment sections per module-structure.md)
// =============================================================================
model Payout {
  id            String    @id @default(cuid())
  technicianId  String
  technician    Technician @relation(fields: [technicianId], references: [id])
  amountPaise   Int                       // integer paise — NEVER Float
  status        PayoutStatus
  auditLogs     AuditLog[]                // audit relation
  createdAt     DateTime  @default(now())
  updatedAt     DateTime  @updatedAt
  deletedAt     DateTime?                 // soft-delete (financial record)
}
```

## Migrate workflow
- All schema changes via `prisma migrate dev` (dev) / `prisma migrate deploy` (prod).
- **Never** hand-edit prod SQL. Review migrations with the `prisma-migration-reviewer` agent.
- Keep one `schema.prisma` for V1 with logical comment sections; split via `multiSchema`
  only past ~1500 lines.

## Process
1. Place the model in the right logical section; add timestamps + (if user/financial)
   `deletedAt` + audit relation.
2. Use `*Paise Int` for money, `aadhaarLast4` for Aadhaar.
3. `prisma migrate dev --name <change>`; review the generated migration.
4. Run `prisma-migration-reviewer` before merge.

> Reference: `docs/05-development/coding-conventions.md` (Database, Money), `docs/04-architecture/module-structure.md` (schema files), `CLAUDE.md` Golden Rules 5-6, ADR-0003.
