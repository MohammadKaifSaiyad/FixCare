# CLAUDE.md — FixCare Master Context

> This file is auto-read by Claude Code on session start. It is the single source
> of truth for how to work on this project. Keep it under ~400 lines. Detailed
> docs live in `docs/` and are referenced below — do not duplicate them here.

---

## What FixCare Is

A trusted marketplace for **home appliance repair and electrical services** in
**Vadodara and Padra**, connecting three actors:

- **Customers** — homeowners/businesses needing repair
- **Workers** — verified technicians with trust scores
- **Merchants** — local hardware shops supplying parts

Core promise: honest service, transparent catalog pricing, fair pay, no one can cheat.

Built by a **solo founder-developer** using **Claude Code** for nearly all work.
Timeline: V1 in ~12-18 months. Android-first. Two apps (customer + worker); merchant
runs on WhatsApp + web for V1.

---

## Golden Rules (Never Violate)

1. **Money never moves without evidence.** Photos, OTPs, or QR scans gate every
   state transition that touches money.
2. **No single party confirms a transaction alone.** Two-sided confirmation always
   (worker GPS + customer OTP; worker photos + customer OTP).
3. **The platform holds cash, not the worker.** UPI is default; cash is the friction-added exception.
4. **Catalog prices only.** Workers have zero pricing discretion on labor or parts.
5. **Every financial operation writes to the append-only audit log.**
6. **Never store raw Aadhaar.** Mask all but last 4 digits everywhere (UI, logs, DB).
7. **No PII in logs or analytics events** (phone, UPI VPA, address, Aadhaar, photos).

---

## Tech Stack (Locked)

| Layer | Choice |
|---|---|
| Mobile | Flutter 3.x, Riverpod, go_router, dio (Android only V1) |
| Backend | Node.js 22 LTS + Fastify 5 + TypeScript (strict) |
| ORM / DB | Prisma 6 + PostgreSQL 16 + PostGIS |
| Cache/Queue | Redis 7 + BullMQ |
| Validation | Zod |
| Auth | Phone OTP + JWT (access 15m / refresh 30d), argon2id for admin pw |
| Realtime | Fastify WebSocket (live tracking + job status only) |
| Storage | Cloudflare R2 (no egress fees) |
| Infra | Docker Compose on Hetzner, Caddy reverse proxy (auto HTTPS) |
| Admin | Next.js 14 + shadcn/ui + Tailwind |
| Payments | Razorpay (+ Razorpay Route for splits) |
| KYC | Setu (Aadhaar/DigiLocker) + Karza (PAN) |
| Push / SMS / WhatsApp | OneSignal / MSG91 / Gupshup |
| Maps | Google Maps Platform |

Full reasoning: `docs/03-tech-stack/stack-decisions.md`.
**Do not introduce new tech without an ADR** in `docs/adrs/`.

---

## Coding Conventions (Enforce Every Session)

Full detail: `docs/05-development/coding-conventions.md`. The non-negotiables:

- **All route inputs validated with Zod.** No unvalidated `request.body`.
- **DB writes go through a service layer**, never directly in route handlers.
- **Prisma for all queries.** Raw SQL only for PostGIS, wrapped in a typed helper.
- **No `any`.** Use `unknown` and narrow.
- **Money is integer paise**, never floats. Use `shared/utils/currency.ts`.
- **All async has explicit error handling**; never swallow errors silently.
- **Never return raw Prisma objects** from the API — map to DTOs.
- **Auth check is the first line** of every protected route.
- **A user can only access their own data** — verify ownership, not just authentication.
- **Inter-module communication via service calls or events**, never cross-module DB queries.

---

## Methodology (Superpowers — Follow the Lifecycle)

This repo uses the Superpowers plugin. Respect its workflow; do not skip phases:

1. **brainstorming** — For any new feature, refine the idea via questions BEFORE coding.
   Save the design to `docs/designs/<feature>.md`.
2. **writing-plans** — Break approved design into 2-5 min tasks with exact paths + code.
   Save to `docs/plans/<date>-<feature>.md`.
3. **test-driven-development** — RED → GREEN → REFACTOR. Write the failing test first.
   Delete any code written before its test.
4. **subagent-driven-development** — One subagent per task, two-stage review.
5. **systematic-debugging** — On bugs, do 4-phase root-cause, not guess-and-check.
6. **requesting-code-review** — Run multi-agent review before any merge.
7. **verification-before-completion** — Prove it's actually fixed before claiming done.

Workflow detail: `docs/05-development/vibe-coding-workflow.md`.

---

## Current Phase

> Update this section as the project progresses. Claude Code reads it to know where we are.

**Phase:** Month 0 — Foundation / pre-development
**Active task:** [set this each session, e.g. "Building OTP auth endpoint"]
**Last shipped:** [nothing yet]
**Blocked on:** [vendor approvals: Razorpay, MSG91 DLT, KYC — all applied for]

Recent changes: see `CHANGELOG.md`.

---

## Build Order (Don't Reorder)

Backend foundation → core business logic → admin dashboard → customer app →
worker app → merchant (WhatsApp) flow → polish/launch.

Rationale and month-by-month: `docs/05-development/build-sequence.md`.

Reason for order: admin dashboard lets you run the platform manually before apps
exist; customer app validates demand before you invest in supply-side worker app.

---

## Known Risks to Keep in Mind

Read `docs/05-development/assumptions-and-doubts.md` before major decisions. Top risks:

- **Android background location** is genuinely hard (OEM battery-killing). Budget extra time.
- **Razorpay Route approval** takes 2-4 weeks beyond KYC — apply day 1.
- **Cash-handling model may have RBI/GST implications** — legal review required before Month 6.
- **Worker disintermediation** is the existential business threat — design for stickiness.
- **Solo dev burnout** — 6 hour/day hard cap, Sundays off, ship less but working.

---

## The Two Keystone Interactions

If the codebase forgets everything else, these must hold:

1. **Arrival handshake** — worker taps "Arrived" (GPS-validated) + customer scans
   worker QR or enters worker's code. Locks visit fee. Proves presence.
2. **Completion handshake** — customer confirms work done → OTP to customer →
   customer reads OTP to worker → worker enters it. Unlocks payment. Proves completion.

Plus **3 mandatory repair photos**: old part removed, new part packaging, new part installed.

---

## Documentation Map

```
docs/
├── 01-overview/        vision-and-scope, naming-and-branding
├── 02-product/         core-flow, pricing-model, trust-system,
│                       fraud-defenses, dispute-resolution
├── 03-tech-stack/      stack-decisions, mobile-stack, backend-stack,
│                       infrastructure, third-party-services
├── 04-architecture/    system-architecture, module-structure
├── 05-development/     build-sequence, vibe-coding-workflow,
│                       coding-conventions, assumptions-and-doubts
├── 06-operations/      security-checklist (see README for status)
├── 07-reference/       decision-summary, next-steps
├── adrs/               architecture decision records (create as needed)
├── designs/            brainstorming outputs (Superpowers)
├── plans/              implementation plans (Superpowers)
└── CHANGELOG.md        last 30 days of significant changes
```

---

## When Starting a Session

1. Read this file (auto) + `CHANGELOG.md`.
2. State the goal: "Today: build X."
3. If new feature → let `brainstorming` run. If continuing → `executing-plans`.
4. Build via subagents, review chunks, TDD throughout.
5. Run `/code-review` before merge.
6. Update "Current Phase" above + `CHANGELOG.md` at end of session.
