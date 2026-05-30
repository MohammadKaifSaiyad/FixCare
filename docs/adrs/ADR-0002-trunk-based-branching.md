# ADR-0002 — Trunk-based branching

**Status:** Accepted · **Date:** 2026-05-30

## Context

The monorepo (ADR-0001) needs a branching model. Today there is one developer who
is also the test environment; there is no team and no staging environment. The
model must stay simple now but extend cleanly when a team and real releases arrive.

## Decision

**Trunk-based development with short-lived feature branches.**

- `main` is the single always-latest, always-green integration branch for **all**
  components.
- Work happens on `feature/<scope>-<desc>` branches cut from `main`, one per unit
  of work → PR → CI + `/code-review` → merge to `main`.
- Conventional commits with a component scope (`feat(auth):`, `fix(bookings):`),
  which maps cleanly to `apps/*` areas.

No `develop`/staging branch and no GitFlow now — that ceremony has no payoff with a
single developer and no staging env.

## Solo-now caveat

Branch protection cannot "require a second human reviewer" with one developer, so
the review gate is satisfied by the `/code-review` multi-agent pass + self-approval.
When a teammate joins, flip on "require 1 approval from `CODEOWNERS`" — the structure
is unchanged.

## Team-mode upgrade (deferred, additive — do NOT build yet)

When a team forms, add (incrementally, per component as needed):
- **`CODEOWNERS`** mapping each path to its owner/reviewer (`apps/backend/ → founder`,
  `apps/customer/ → mobile dev`, …) so PRs auto-route.
- **Path-filtered CI** so a PR touching only `apps/admin/` runs only admin checks —
  this is what makes components independent in practice.
- **Branch protection** on `main` (PR + passing CI + required approval).
- **Per-component `staging`** branches + staging deploys, added where each component
  needs them (likely backend first — it's the money-touching layer). Because CI is
  already path-filtered, the branching model can differ per path; this is purely
  additive and requires no restructuring.

## Alternatives considered

- **GitFlow (`main` + `develop` + release branches) now** — rejected: premature; no
  releases or staging env to justify it.
- **Feature branches with no protection ever** — rejected as the long-term answer; fine
  solo, but we want the team-readiness seams documented so the upgrade is obvious.

## Consequences

- Simple, fast solo workflow today; the path to team mode is a documented set of
  additive switches, not a migration.
- The `packages/shared-types` package is the one deliberate cross-component
  dependency — an API contract change and its consumers move in one atomic PR
  (a monorepo capability polyrepo lacks).
