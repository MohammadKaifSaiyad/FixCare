---
name: keystone-handshake
description: Use when implementing or modifying the arrival handshake or completion handshake in apps/backend — the two-sided confirmations that lock the visit fee and unlock payment. Enforces Golden Rules 1-2 (money never moves without evidence; no single party confirms alone). Touch this and you are touching the product's core integrity.
---

# Keystone Handshakes (FixCare)

These are the two interactions that, per CLAUDE.md, *must hold even if the codebase
forgets everything else*. Both are **two-sided** — never confirmable by one party.

## 1. Arrival handshake — locks the visit fee, proves presence
Required evidence (BOTH sides):
- **Technician side:** taps "Arrived" with a **GPS reading validated** against the
  customer's address geofence. Reject if outside the geofence radius.
- **Customer side:** scans the technician's **QR** (technician badge) OR enters the
  technician's short **code**.

Only when both are present → transition booking to `ARRIVED` and **lock the visit fee**.
Write the transition + evidence refs to `AuditLog` in the same transaction.

## 2. Completion handshake — unlocks payment, proves completion
Required sequence:
1. Customer confirms work done.
2. System generates a **completion OTP** and sends it to the **customer**.
3. Customer reads the OTP to the technician; **technician enters it**.
4. Backend verifies the OTP → only then unlock payment.

Plus **3 mandatory repair photos** must exist (old part removed, new part packaging,
new part installed — see `camera-evidence-capture` skill) before completion is allowed.

## Non-negotiables (Golden Rules 1-2)
- **No single party can complete either handshake.** Always require both sides' evidence.
- **The money transition is gated by the evidence** — if GPS/QR/OTP/photos are missing
  or invalid, the transition is rejected (throw `BusinessRuleError`). Never "trust" one side.
- GPS validation has a tolerance; spoofing/edge cases are fraud vectors — cross-check
  with the `fraud-vector-checker` agent.
- Every state transition writes to `AuditLog` in the same transaction (use
  `audit-logged-mutation`). OTPs are short-lived, single-use, rate-limited.
- No PII (phone, exact coordinates) in logs or analytics.

## Process
1. Model the booking state machine so these transitions cannot be skipped (guards).
2. Write failing tests FIRST, including the "one side missing ⇒ rejected" cases.
3. Implement the gate → transition → audit-log in a transaction.
4. Run `golden-rules-auditor` + `fraud-vector-checker` before merge.

> Reference: `CLAUDE.md` (Two Keystone Interactions, Golden Rules 1-2), `docs/02-product/core-flow.md`, `docs/02-product/fraud-defenses.md`.
