# ADR-0004 — Build order: apps before admin

**Status:** Accepted · **Date:** 2026-05-30 · **Supersedes:** the component order in `build-sequence.md`

## Context

The original `build-sequence.md` ordered components: backend → **admin (Month 4)**
→ customer app (5-6) → technician app (7-9) → merchant. Admin-second was chosen so
the founder could operate the platform via a UI before the apps existed.

The founder has chosen to reorder, building the customer and technician apps before
the admin dashboard.

## Decision

Build order is now:

1. **Backend** (foundation + core business logic)
2. **Customer app**
3. **Technician app**
4. **Admin dashboard**
5. **Merchant** (WhatsApp + web)

Customer-before-technician is **kept** from the original sequence (validate demand
before investing in the harder supply-side app). The change is **admin moves from
2nd to 4th** — after both apps.

## Consequence (accepted trade-off)

Until the admin dashboard exists, there is **no operations UI**. The platform is
operated entirely via **direct API calls** (Bruno/Postman/curl): creating bookings,
verifying technician KYC, inspecting the ledger, resolving stuck states, managing the
catalog. The founder has explicitly accepted operating this way through the backend,
customer, and technician phases.

Risks to watch:
- **Technician onboarding/KYC** (real workers, ~Month 9 in the old numbering) will
  have no admin UI for manual KYC verification — it must be done via API until admin
  is built. If this becomes painful, build a **thin admin shim** (KYC-verify +
  booking-view) at that point rather than waiting for the full admin.
- Beta operations without an admin control panel are slower; budget for it.

## Alternatives considered

- **Keep admin 2nd (original):** rejected by the founder in favor of getting the apps
  (the user-facing product) into testable shape sooner.
- **Technician before customer:** considered and rejected — customer-first validates
  demand before building the hardest, least-familiar component.

## Notes

`build-sequence.md` still contains month-by-month sections written for the old order
(Month 4 Admin, 5-6 Customer, 7-9 Technician). Those month *numbers/sections* are now
out of date; this ADR is the authoritative order. Renumber the month sections when the
schedule is next revised — not retrofitted speculatively before the backend is built.
