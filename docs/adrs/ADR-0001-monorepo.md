# ADR-0001 — Monorepo over separate repos

**Status:** Accepted · **Date:** 2026-05-30

## Context

FixCare has four deployable components (backend API, admin dashboard, customer
app, technician app) plus shared API-contract types. We had to decide between a
single monorepo and one git repo per component. The deploy target is a single
Hetzner VPS running Docker Compose; the builder is a solo founder using Claude
Code, who may add a small team later.

## Decision

**One monorepo** at the FixCare root, trunk = `main`, with components under
`apps/` (`backend`, `admin`, `customer`, `technician`) and shared TS code under
`packages/` (`shared-types`). `CLAUDE.md`, `STATUS.md`, `CHANGELOG.md`, and
`docs/` live at the root.

## Rationale (against the criteria that mattered)

- **Ease of development** — one clone, atomic cross-component commits, one
  `/code-review` over the whole change.
- **Running locally** — one `docker compose up` brings up the shared data stack;
  one place for env config.
- **Deploying** — one path-filtered CI; matches the single-host Docker Compose target.
- **Docs/CLAUDE.md tracking** — the context Claude auto-reads stays welded to the
  code it describes, versioned in lockstep.
- **Claude Code works better in one tree** — session-start context, worktrees, and
  multi-agent review all operate over a single repo.

A monorepo is not a small-team-only pattern; large orgs run huge monorepos. Adding
teammates does not force a split — branches + `CODEOWNERS` + path-filtered CI cover
team needs (see ADR-0002).

## Alternatives considered

- **4 separate repos** — rejected: coordination overhead (version-pinning,
  multi-repo PRs) lands entirely on a solo dev; docs detach from code; fights the
  single-host deploy. The benefits (independent ownership/access) are organizational
  problems we don't have yet.
- **3 repos (apps share one)** / **5 repos (+shared)** — same downsides, less or more sprawl.

## Consequences

- **Escape hatch:** if a real need appears (e.g. an external contractor who must not
  see payments code), `git subtree split` / `git filter-repo` extracts one folder
  into its own repo **with history preserved** — an afternoon's work. The asymmetry
  favors starting consolidated: splitting later is cheap, merging polyrepos later is not.
- **Flutter is outside the pnpm workspace.** `apps/customer` and `apps/technician`
  use their own Dart/`pubspec.yaml` toolchain; `pnpm-workspace.yaml` covers only
  `apps/backend`, `apps/admin`, `packages/*`. This is expected, not a workaround.
- The `apps/*` + `packages/*` seams are exactly where a future split would happen,
  so we are not boxed in either way.
