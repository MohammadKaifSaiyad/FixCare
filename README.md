# FixCare — Project Documentation

Trusted home appliance repair & electrical services marketplace.
Launching in Vadodara & Padra. Solo founder, Claude Code-assisted build.

---

## Start Here

1. **`CLAUDE.md`** (repo root) — keystone context, auto-read by Claude Code every session.
2. **`07-reference/decision-summary.md`** — every locked decision on one page.
3. **`07-reference/next-steps.md`** — what to actually do first.
4. **`05-development/assumptions-and-doubts.md`** — honest risks before you commit.

---

## How These Docs Are Organized

Split by concern so you (and Claude Code) find things fast.

### 📁 (root) CLAUDE.md
Master context Claude Code reads automatically. Golden rules, stack, conventions,
methodology, current phase. Keep it updated.

### 📁 01-overview
- `vision-and-scope.md` — what FixCare is, who it serves, in/out of V1
- `naming-and-branding.md` — why "FixCare", app naming

### 📁 02-product
- `core-flow.md` — end-to-end customer/technician/merchant journey + fraud locks
- `pricing-model.md` — visit fee, labor, parts, revenue splits
- `trust-system.md` — two-score model, graduated cash limits
- `fraud-defenses.md` — every fraud vector and its block
- `dispute-resolution.md` — tiered dispute workflow

### 📁 03-tech-stack
- `stack-decisions.md` — final picks + rejected alternatives
- `mobile-stack.md` — Flutter setup & libraries
- `backend-stack.md` — Node + Fastify + Prisma + Postgres
- `infrastructure.md` — Hetzner, Docker, Caddy, R2, backups
- `third-party-services.md` — Razorpay, MSG91, KYC, Maps, fallbacks

### 📁 04-architecture
- `system-architecture.md` — modular monolith, request flows, scaling path
- `module-structure.md` — backend folder organization & rules

### 📁 05-development
- `build-sequence.md` — month-by-month roadmap
- `vibe-coding-workflow.md` — Claude Code + Superpowers methodology
- `coding-conventions.md` — patterns to enforce every session
- `assumptions-and-doubts.md` — honest risks & hidden complexity (READ FIRST)

### 📁 07-reference
- `decision-summary.md` — one-page lookup of all decisions
- `next-steps.md` — prioritized action list

### 📁 06-operations
Runbooks, monitoring, security checklist, backups. Currently stubs — operational
detail still lives inside `infrastructure.md` until these files grow.

### 📁 adrs / designs / plans / decisions / progress
- `adrs/` — Architecture Decision Records (expensive-to-reverse decisions)
- `designs/` — Superpowers brainstorming specs
- `plans/` — Superpowers implementation plans
- `decisions/` — lightweight decisions (smaller than an ADR)
- `progress/weekly-notes/` — weekly retros

> `CLAUDE.md`, `STATUS.md`, and `CHANGELOG.md` live at the **repo root** (not under
> `docs/`), because Claude Code auto-reads the root `CLAUDE.md` on session start.

---

## Quick Reference

| Need | File |
|---|---|
| Set up Claude Code for this project | `CLAUDE.md` + `05-development/vibe-coding-workflow.md` |
| Forgot a decision | `07-reference/decision-summary.md` |
| What to do first | `07-reference/next-steps.md` |
| What could go wrong | `05-development/assumptions-and-doubts.md` |
| Adding a feature | `02-product/core-flow.md` + `04-architecture/module-structure.md` |
| Fraud question | `02-product/fraud-defenses.md` |
| Money flow | `02-product/pricing-model.md` |
| Build order | `05-development/build-sequence.md` |
| Coding rules | `05-development/coding-conventions.md` |

---

## Using This With Claude Code

This repo **is** the monorepo (single git repo, trunk = `main`). `CLAUDE.md` is
already at the repo root and auto-read every session.

1. Install Superpowers + code-review + typescript-lsp plugins (see vibe-coding-workflow.md).
2. Start each session: read `STATUS.md`, state your goal, cut a `feature/*` branch,
   let the methodology run.
3. End each session: update `STATUS.md` + `CHANGELOG.md` (weekly: a `progress/weekly-notes/` retro).
4. Run `/code-review` before merging any branch to `main`.

Component apps live under `apps/` (`backend`, `admin`, `customer`, `technician`);
shared TS contracts under `packages/`. See `CLAUDE.md` → "Repository Layout".

---

## Status

- **Stage:** Pre-development (planning complete)
- **Build:** Solo founder + Claude Code (vibe coding)
- **Launch target:** Vadodara + Padra, V1 in ~12-18 months
- **Stack:** Flutter (Android) + Node/Fastify + Postgres + Hetzner

---

## Living Docs Policy

These are living documents. Outdated docs are worse than none.

1. Change a decision → update the relevant file the same day.
2. Add `Last updated: YYYY-MM-DD` when you change something.
3. Major architectural changes → an ADR in `docs/adrs/`.
4. Every coding session → update `CHANGELOG.md` + `CLAUDE.md` "Current Phase".
