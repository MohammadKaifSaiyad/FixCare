# Decision — V1 dispatch is broadcast / first-to-accept (not weighted push)

_Date: 2026-06-13 · Status: accepted · Scope: booking dispatch (module B2a)_

## Context

`core-flow.md` originally described a **push** dispatch model: a dispatch algorithm
`rating × proximity × current_load × cash_compliance` picks **one** technician, who gets a
30-second accept/reject offer. When building the dispatch slice (B2a) we found that **none of those
four ranking inputs exist** in the data model, and they belong to subsystems that aren't built yet:

- **rating** → trust-score system (not built)
- **proximity** → technician live location (not built; address lat/lng optional, PostGIS deferred)
- **current_load** → active-job tracking (not built)
- **cash_compliance** → cash/ledger/debt model (not built)

Plus there is no BullMQ/queue infrastructure for an accept timer.

## Decision

V1 dispatch is **broadcast / first-to-accept**:

- When a customer books, the booking **auto-opens to the pool** (`CREATED → DISPATCHED`).
- It becomes visible to **all eligible technicians** — `status: VERIFIED` AND the booking's
  `service.requiredSkill` ∈ the technician's `skills[]`.
- **The first eligible technician to accept wins**, atomically (`DISPATCHED → ACCEPTED` via the
  optimistic-locked `transitionBooking`; a concurrent loser gets 409). A technician can **skip** a
  job to hide it from their own list.
- Zone-coverage filtering is deferred (all VERIFIED technicians serve both V1 zones).

## Consequences / deferred

- **Weighted matching algorithm (B2c)** — `rating × proximity × current_load × cash_compliance` to
  rank/limit who is offered a job — deferred until trust-score, location, and cash models exist.
- **Per-offer 30-second accept timer (B2b)** — deferred until BullMQ/queue infrastructure is stood up.
- **Phase-A fraud locks** (customer-with-unsettled-payment blocked from booking; technician-at-cash-
  debt-limit cannot accept; self-dealing address-frequency flag) — **deferred, not dropped**; they
  need the payment/cash and trust subsystems. Tracked for those slices.

## References

Design: `docs/designs/2026-06-13-booking-b2a-dispatch-design.md`. Updates `docs/02-product/core-flow.md`
Phase A. Builds on the booking state machine (`docs/designs/2026-06-07-booking-b1-creation-design.md`).
