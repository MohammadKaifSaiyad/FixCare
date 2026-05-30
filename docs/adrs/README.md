# Architecture Decision Records (ADRs)

One file per significant architectural decision. An ADR captures **what** was
decided, **why**, the **alternatives** rejected, and the **consequences** — so
future-you (and Claude Code) understands the reasoning, not just the outcome.

Write a new ADR whenever you make a decision that is expensive to reverse:
introducing a technology, changing a structural pattern, a cross-cutting naming
or boundary decision. (Per CLAUDE.md: *"Do not introduce new tech without an ADR."*)

## Format
`ADR-NNNN-short-title.md` — Status (Proposed/Accepted/Superseded), Context,
Decision, Alternatives Considered, Consequences.

## Index
- [ADR-0001 — Monorepo over separate repos](ADR-0001-monorepo.md)
- [ADR-0002 — Trunk-based branching](ADR-0002-trunk-based-branching.md)
- [ADR-0003 — "Worker" → "Technician" naming](ADR-0003-worker-to-technician.md)
