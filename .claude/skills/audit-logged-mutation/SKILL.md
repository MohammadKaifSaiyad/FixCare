---
name: audit-logged-mutation
description: Use when writing any backend operation that moves money or changes financial/trust state in apps/backend — payments, ledger, wallet, settlements, payouts, refunds, cash debt, deposits. Enforces FixCare Golden Rules 1 & 5: money never moves without evidence, and every financial operation writes to the append-only audit log in the same transaction. Money is integer paise.
---

# Audit-Logged Financial Mutation

This skill guards the two Golden Rules that protect FixCare's core promise that
*no one can cheat*. Any code touching money must follow this pattern.

## Golden Rules enforced
1. **Money never moves without evidence** — photos, OTPs, or QR scans gate every
   money-touching state transition. No single party confirms alone (two-sided).
5. **Every financial operation writes to the append-only audit log.**

Plus: **money is integer paise, never floats** — all math via `shared/utils/currency.ts`.

## The required pattern

```ts
// inside a service method — financial mutation
await prisma.$transaction(async (tx) => {
  // 1. GATE: verify the evidence that authorizes this money movement
  //    (e.g. completion OTP entered, required photos present, QR/GPS handshake).
  //    Throw BusinessRuleError if the evidence is missing — do NOT proceed.

  // 2. The mutation itself — amounts in integer paise (currency.ts helpers)
  const ledgerEntry = await tx.ledgerEntry.create({ data: { amountPaise, ... } });

  // 3. AUDIT in the SAME transaction — never a separate write that can drift
  await tx.auditLog.create({
    data: {
      action: 'PAYMENT_CAPTURED',          // specific, enumerated action
      actorId, subjectId, amountPaise,
      evidenceRef,                          // link to the OTP/photo/QR that gated it
      // NO raw PII (phone, UPI VPA, address, Aadhaar) — Golden Rule 7
    },
  });

  return ledgerEntry;
});
```

## Non-negotiables
- **Audit write is in the same `$transaction`** as the mutation — atomic, or neither.
- **Integer paise only.** Never floating-point money. Round only at display, client-side.
- **The evidence gate runs before the mutation.** If asked to "just move the money"
  without the gating evidence, **push back** (it violates Golden Rule 1).
- **Technicians have zero pricing discretion** — amounts come from the catalog, not input.
- **No PII in the audit log or analytics.** Aadhaar masked to last 4 everywhere.
- **The platform holds cash, not the technician.** UPI is default; cash is the
  friction-added exception with its own checks.
- Slow/external steps (e.g. Razorpay calls) go through a BullMQ queue, not inline.

## Process
1. Identify the evidence that must gate this movement (OTP / photos / QR / GPS).
2. Write the failing test first, including the "missing evidence ⇒ rejected" case.
3. Implement the transaction in the shape above; assert the `AuditLog` row in tests.
4. Verify against coding-conventions.md "What Claude Code Should Push Back On".

> Reference: `CLAUDE.md` Golden Rules + Keystone Interactions; `docs/02-product/`
> (pricing-model, fraud-defenses); `docs/05-development/coding-conventions.md` (Money, Database).
