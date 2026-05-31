# Changelog

Significant changes, most recent first. Rolling ~30-day window — older entries
can be trimmed. The *live* project state lives in [`STATUS.md`](STATUS.md);
this is the history of how it got there.

Format: `## YYYY-MM-DD` headers, bullet entries. Update every session.

---

## 2026-05-31

- **Backend auth + users schema slice (first real code).** Scaffolded `apps/backend`
  (Fastify 5 + TypeScript strict + Prisma 6 + Vitest, Node 22 / pnpm 9.15.2) and
  implemented the auth+users Prisma schema test-first: `User` (one-role-per-phone),
  `RefreshToken` (hashed, rotation chain, sliding-expiry field), `Customer`/`Technician`/
  `Merchant`/`Admin` 1:1 profiles, append-only `AuditLog`. 11 TDD invariant tests green;
  first migration `20260531052019_auth_users_slice` applied to `fixcare_dev`. Built via
  subagent-driven development with per-task spec+quality review; migration passed the
  migration-safety review (no blocking issues). On `feature/auth-users-schema` — pending merge.
  Design: `docs/designs/2026-05-30-auth-users-schema-design.md`; plan:
  `docs/plans/2026-05-30-auth-users-schema.md`.

## 2026-05-30

- **Build order changed (ADR-0004).** New order: Backend → Customer app → Technician
  app → Admin → Merchant (admin moved from 2nd to 4th). Trade-off: operate the platform
  via direct API calls until admin is built. Updated `CLAUDE.md` Build Order,
  `build-sequence.md` (reality-check bullets + month-section banner), `STATUS.md`.
- **Enforced commit authorship via hooks.** `.githooks/commit-msg` (via `core.hooksPath`)
  + a Claude Code PreToolUse hook reject commits with a Claude co-author trailer or a
  non-`saiyedkgn6@gmail.com` author. Rewrote the prior 11 commits to the correct author.

- **Added project skills + custom agents.** Expanded `.claude/` with FixCare-specific
  automation (generic workflow stays with Superpowers):
  - 4 new backend skills: `prisma-schema-model`, `keystone-handshake`,
    `bullmq-worker` (backend-only — apps use in-app retry, not BullMQ),
    `third-party-wrapper`. (Now 7 backend skills total.)
  - 4 new Flutter/apps skills (first app-side skills): `flutter-feature`,
    `api-repository`, `camera-evidence-capture`, `riverpod-provider`.
  - 4 read-only review agents in `.claude/agents/`: `golden-rules-auditor`,
    `prisma-migration-reviewer`, `flutter-widget-reviewer`, `fraud-vector-checker`.
  - Listed them in `CLAUDE.md` → "Project Skills & Agents". Each cites its source doc.

- **Project setup (pre-development).** Established the working structure so the
  documented Claude-Code + Superpowers workflow can actually run:
  - Initialized git (single **monorepo**, trunk = `main`) and committed the
    existing planning docs.
  - Scaffolded `apps/{backend,admin,customer,technician}` + `packages/shared-types`
    with purpose READMEs; stub `pnpm-workspace.yaml` + `docker-compose.yml`.
  - Created the missing docs folders (`06-operations`, `adrs`, `designs`,
    `plans`, `decisions`, `progress/weekly-notes`) with index READMEs.
  - Reconciled conflicting artifact paths → `docs/designs` + `docs/plans`;
    pinned Superpowers brainstorming output to `docs/designs`.
  - Renamed the technician actor **"Worker" → "Technician"** across all docs
    (preserving BullMQ/background-job "worker" terminology).
  - Added the progress-tracking system: `STATUS.md` + weekly-notes template,
    wired into the session ritual in `CLAUDE.md`.
  - Added 3 project-level skills: `scaffold-module`, `zod-validated-route`,
    `audit-logged-mutation`.
  - Wrote ADR-0001 (monorepo), ADR-0002 (trunk-based branching),
    ADR-0003 (worker→technician).
