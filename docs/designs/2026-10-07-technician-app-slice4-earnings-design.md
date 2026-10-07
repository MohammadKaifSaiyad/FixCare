# Technician App Slice 4 — Earnings, Cash Debt + Payout Requests (Design)

**Date:** 2026-10-07
**Branch:** `feature/technician-app-slice4-earnings` (cut from `main` @ `ffee299`, Slice 3 merged #39)
**Status:** Approved design → ready for plan
**Builds on:** B6b cash (`docs/plans/2026-07-19-booking-b6b-cash.md`), B6c settlement + ledger (`apps/backend/src/modules/settlements/`),
B7 disputes, technician Slices 1–3.

---

## Problem

The backend already keeps an append-only money ledger per technician — `EARNING_CREDIT` (80% of the job's labor / visit
fee, booked by the settlement sweep after the 48 h dispute window), `COMMISSION` (FixCare's 20%), `CASH_COLLECTED` (cash
the technician received from a customer — owed to FixCare), `CASH_DEBT_OFFSET` (settlement auto-pays cash debt from new
earnings), `PAYOUT` / `DEBT_REPAYMENT` (recorded by ops by hand) and `DISPUTE_REVERSAL` (a customer refund, informational).
Above `CASH_DEBT_LIMIT_PAISE` (₹500) of cash debt, accepting new jobs is refused.

The technician app shows none of it. A technician can't see what they've earned, what FixCare owes them, what is still
in the dispute window, or that they hold FixCare's cash — they only meet the 422 "Settle your cash debt to accept new
jobs" when an accept fails. Getting paid means chasing ops by phone.

## Goal & success criteria

FixCare's "fair pay, nobody can cheat" promise made visible:
- A technician sees **what FixCare owes them**, **what is pending** (and when it releases), **their cash debt vs the
  limit** (and whether new jobs are paused), and a **per-job history** where every money movement — including FixCare's
  20% fee — is listed and the totals add up.
- A technician can **request a payout** of everything owed (net of cash debt) in one tap and see its status; ops pays by
  hand (no gateway yet), marks it paid or rejects it with a reason. A payout can never be recorded twice or overdraw.

## Decisions (agreed in brainstorming)

1. **Scope:** see money + request payout (not read-only; not balance-only).
2. **Payout rule:** the request is for the **whole net balance** at that moment; **one open request per technician**; a
   **minimum** (`PAYOUT_MIN_PAISE`, default ₹100) on the net amount. Ops **marks paid** (records the payout) or
   **rejects with a reason**.
3. **Approach 1 — ledger-backed statement + a `PayoutRequest` record** (chosen over a per-job view built from bookings,
   which can't reconcile payouts / repayments / reversals, and over a "nudge ops" request with no status).
4. **Cash debt is netted before paying out** (Golden Rule 3 — the platform holds cash): at pay time the technician's cash
   debt is first offset against what is owed, then the remainder is paid out. The technician sees the net figure up
   front.
5. **Commission is shown** on the statement (transparency is the point).
6. **Payout destination (bank / UPI) stays with ops offline** this slice — in-app bank capture is its own later slice
   (PII, Golden Rule 7).
7. **Any technician status can see earnings and request a payout** — a suspended technician is still owed their money.

---

## Backend (settlements module — it owns the ledger)

### Data (one additive migration)

```prisma
enum PayoutRequestStatus { REQUESTED PAID REJECTED }

model PayoutRequest {
  id            String              @id @default(uuid())
  technicianId  String
  technician    Technician          @relation(fields: [technicianId], references: [id])
  amountPaise   Int                 // the net amount the technician saw when requesting (positive)
  status        PayoutRequestStatus @default(REQUESTED)
  reviewNote    String?             // ops' reject reason (shown to the technician)
  reviewedBy    String?             // admin user id
  reviewedAt    DateTime?
  payoutEntryId String?             @unique // the PAYOUT LedgerEntry written when marked paid
  createdAt     DateTime            @default(now())
  updatedAt     DateTime            @updatedAt
  @@index([technicianId, createdAt])
  @@index([status, createdAt])
}
```

- **One open request per technician** — enforced in the request transaction by locking the technician row
  (`SELECT … FOR UPDATE`, the same pattern `recordPayout` uses) and then checking for an existing `REQUESTED` row. No
  partial unique index (Prisma would fight it).
- Config: `PAYOUT_MIN_PAISE` (int, positive, default `10000`).
- Money is integer paise everywhere. Audit: `SETTLEMENT_EVENT` rows with `event: payout_requested |
  payout_request_paid | payout_request_rejected` (ids, paise and the reason only — no PII), in the same transaction.

### Shared figures

- `owedPaise` = ledger payable = `EARNING_CREDIT − CASH_DEBT_OFFSET − PAYOUT` (existing `payableBalancePaise`).
- `cashDebtPaise` = cached `Technician.cashDebtPaise` (what the gates enforce; existing).
- `netPayoutPaise` = `max(0, owedPaise − cashDebtPaise)`.
- `acceptBlocked` = `cashDebtPaise > CASH_DEBT_LIMIT_PAISE` (the exact rule `acceptJob` uses).

### Technician endpoints (`requireAuth` + technician role; any technician status)

- **`GET /technician/me/earnings`** →
  ```
  { owedPaise, netPayoutPaise, pendingPaise, cashDebtPaise, cashDebtLimitPaise, acceptBlocked, payoutMinPaise,
    pending: [{ bookingId, bookingNumber, serviceName, amountPaise, releasesAt, onHold }],
    latestPayoutRequest: { id, status, amountPaise, requestedAt, reviewedAt, reviewNote } | null }
  ```
  `pending` = this technician's bookings in `PAYMENT_RECEIVED` (expected share = `splitPaise(base).earningPaise`, base =
  visit fee if declined else labor — the sweep's exact formula; `releasesAt = paidAt + DISPUTE_WINDOW_HOURS`) and in
  `DISPUTED` (`onHold: true`, `releasesAt: null`; amount shown as the full expected share, labelled "on hold").
  `pendingPaise` = sum of the non-on-hold amounts. Read in one transaction (consistent snapshot).
- **`GET /technician/me/ledger?before=<cursor>&limit=<1..50, default 20>`** → `{ entries: [{ id, type, amountPaise,
  bookingNumber?, serviceName?, createdAt }], nextCursor | null }`, newest first. Cursor = opaque string encoding
  `(createdAt, id)` so ties never repeat or skip. Zod-validated query.
- **`POST /technician/me/payout-requests`** (bodyless) → in one tx: lock the technician row; 409
  `PAYOUT_ALREADY_REQUESTED` *"You already have a payout request in progress"* if one is `REQUESTED`; compute
  `netPayoutPaise`; 422 `PAYOUT_BELOW_MINIMUM` *"Payouts start at ₹100"* (formatted from the config) if below the
  minimum; create `REQUESTED` with `amountPaise = netPayoutPaise`; audit. Returns the request DTO.

### Ops endpoints (`[requireAuth, requireAdminLevel('MANAGER')]`)

- **`GET /admin/payout-requests?status=`** → oldest first: `{ id, technicianId, technicianName, maskedPhone,
  amountPaise, status, requestedAt, reviewedAt, reviewNote, currentOwedPaise, currentCashDebtPaise }`.
- **`POST /admin/payout-requests/:id/pay`** — ops has already transferred the money by hand. One tx: lock the technician
  row; request must be `REQUESTED` (else 409 `PAYOUT_REQUEST_NOT_OPEN`); `offset = min(owed, cashDebt)` → if > 0 write
  `CASH_DEBT_OFFSET` + decrement `cashDebtPaise` (same as the sweep); `pay = owed − offset`; if `pay ≤ 0` → 409
  `NOTHING_TO_PAY` *"Nothing is owed after settling cash debt — reject this request instead"* (tx rolls back); write
  `PAYOUT` for `pay`; mark `PAID`, `payoutEntryId`, `reviewedBy/At`; audit `{ requestedPaise, offsetPaise, paidPaise }`.
  Returns the request DTO (with the paid amount). The paid amount may differ from the requested amount if money moved in
  between; the audit records both.
- **`POST /admin/payout-requests/:id/reject {reason}`** — reason rules from Slice 3 (1–500 chars, no 10+-digit runs after
  stripping separators — reuse `reasonBody`); request must be `REQUESTED` (409 otherwise); mark `REJECTED` + note; audit.

All `:id` params and bodies Zod-validated; missing request → 404. Full phone never appears in any response.

---

## Technician app (`apps/technician`)

### Data (`lib/features/earnings/data/`)

- `EarningsRepository` (dio via `dioProvider`): `summary()` (bodyless GET), `ledger({String? before, int limit = 20})`
  (bodyless GET), `requestPayout()` (bodyless POST). Freezed DTOs: `EarningsSummaryDto`, `PendingReleaseDto`,
  `PayoutRequestDto`, `LedgerEntryDto`, `LedgerPageDto`. Failures keep `{code, message}`.

### State

- `earningsSummaryProvider` — loads on first watch; no auto-retry on a definitive (4xx) failure (Riverpod 3 retry rule);
  `refresh()`.
- `LedgerController` — first page on build; `loadMore()` (no-op while loading or when `nextCursor == null`; drops a late
  response after a refresh via a request sequence); `refresh()`.

### Jobs home — money card (top of the list)

- **"Owed to you ₹X"** (+ "₹Y pending" when > 0); if `cashDebtPaise > 0` → **"Cash to hand over ₹D"**; if
  `acceptBlocked` → a red line **"New jobs are paused until your cash is settled (₹D of ₹500 limit)"** (limit from the
  summary). Tap → `/earnings`. Reloads with the jobs pull-to-refresh and when returning from `/earnings`. A failed
  summary shows a compact "Couldn't load earnings · Retry" row (never blocks the job lists).

### Earnings screen (`/earnings`)

1. **Summary** — owed, pending total, cash debt vs limit (with the paused note when blocked).
2. **Payout** — one of:
   - eligible (`netPayoutPaise ≥ payoutMinPaise` and no open request) → **"Request payout of ₹N"** → confirm dialog
     *"Request ₹N? FixCare transfers it and confirms here. Your ₹D cash is settled first."* (cash clause only when
     debt > 0) → `requestPayout()` → refresh summary;
   - below minimum → disabled button + *"Payouts start at ₹100"*;
   - open request → *"₹N requested on 3 Oct — FixCare will transfer it soon"*;
   - latest paid → *"₹N paid on 4 Oct"* (and the button when eligible again);
   - latest rejected → *"Not paid: «reason»"* (and the button when eligible).
   409 `PAYOUT_ALREADY_REQUESTED` / 422 → message verbatim in a SnackBar + refresh summary.
3. **Pending** — booking number + service + amount + *"Releases 5 Oct, 2:00 pm"* or **"On hold — under dispute"**.
4. **History** — each row names its effect on one of two running totals:

   | Ledger type | Label | Effect |
   |---|---|---|
   | `EARNING_CREDIT` | Earned · FC-1234 · service | Owed **+₹** |
   | `COMMISSION` | FixCare fee (20%) · FC-1234 | Info |
   | `CASH_COLLECTED` | Cash collected · FC-1234 | Cash to hand over **+₹** |
   | `CASH_DEBT_OFFSET` | Cash settled from earnings | Owed **−₹** · Cash **−₹** |
   | `PAYOUT` | Paid to you | Owed **−₹** |
   | `DEBT_REPAYMENT` | Cash handed over | Cash **−₹** |
   | `DISPUTE_REVERSAL` | Customer refunded after a dispute · FC-1234 | Info |

   "Load more" at the bottom; pull-to-refresh reloads summary + first page. Errors: message verbatim + Retry.

### Suspended technicians

The Suspended screen gains an **"Earnings"** button → `/earnings`. The router's non-verified redirect stays limited to
`/job/*`, so `/earnings` is reachable from any signed-in status.

### Conventions

Riverpod + repositories only; no global dio content-type; busy flags in `try/finally`; `mounted` after every await;
money only via `rupees()`; dates via the existing local-time helpers (add a `formatShortDateTime` if needed); no PII in
`FlutterError.reportError`; layouts wrap at 320 px.

---

## Testing

**Backend (vitest, real Postgres):** earnings summary (owed matches the ledger; pending = only own PAYMENT_RECEIVED with
the sweep's share and `paidAt + 48 h`, DISPUTED → on hold; debt/limit/`acceptBlocked` boundary at exactly the limit;
latest request in each status; another technician's data never leaks; non-technician 403); ledger (newest first, booking
number + service on job rows only, cursor pagination with tied timestamps, limit bounds 400); payout request (net
amount; 422 below minimum after netting; 409 when one is open; two concurrent requests → exactly one; audited; allowed
when SUSPENDED); pay (offset then payout; `PAID` + linked entry; cached debt == ledger debt afterwards; 409 when nothing
left after netting, and when not open; concurrent pay of the same request → one payout); reject (reason rules, audited,
409 when not open); ops walls (401 / 403 SUPPORT / customer / technician on every route); list masks the phone. The
existing settlement + dispute suites stay green unchanged.

**Technician app (flutter, hermetic `http_mock_adapter`):** request contracts (bodyless GETs/POST, query params, DTO
parsing); money card (owed / pending / cash / paused line / error row / tap → `/earnings`); Earnings screen (every payout
state, confirm dialog, 409/422 → snack + refresh, pending rows, a history row per ledger type, Load more without
duplicate requests, pull-to-refresh, error + Retry, 320 px wrapping); Suspended screen Earnings button; router —
`/earnings` reachable when not verified, `/job/*` still redirected. `flutter analyze` 0.

**Review gates:** per-task spec + quality → `prisma-migration-reviewer` → whole-branch review + golden-rules-auditor +
fraud-vector-checker (payout abuse, double payout, netting) + flutter-widget-reviewer → `/code-review` → one fix wave
each → run both apps on the simulator.

## Rollout

One additive migration (`PayoutRequest` + enum); no backfill. `PAYOUT_MIN_PAISE` defaults to ₹100. Deploy the backend
first; an older app build simply doesn't show earnings. Docs: a payout section in
`docs/06-operations/technician-review-runbook.md` (queue → transfer by hand → mark paid; reject with a reason);
STATUS (Slice 3 merged #39; this slice active; follow-ups); CHANGELOG; a fraud-defenses note if the fraud reviewer
surfaces a new vector.

## Out of scope (tracked)

In-app bank / UPI capture; automatic payouts (Razorpay Route); technician-cancelled requests; push notification on
paid; trust score; per-period statements / CSV export; online/offline mode.
