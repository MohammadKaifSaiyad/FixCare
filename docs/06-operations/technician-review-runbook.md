# Technician review runbook

How ops onboards, verifies, edits, suspends and reinstates technicians until the admin dashboard exists
(ADR-0004: operate via direct API calls). Design: `docs/designs/2026-10-02-technician-app-slice3-onboarding-design.md`.

Every command below needs a **MANAGER** admin token. Bruno/Postman equivalents are the same requests.

```bash
BASE=http://localhost:3000        # the backend base URL
ADMIN=$(curl -s -X POST "$BASE/admin/auth/login" -H 'content-type: application/json' \
  -d '{"email":"<admin email>","password":"<admin password>"}' | jq -r .accessToken)
```

The access token lives 15 minutes; log in again when you get a 401.

## Golden rules for ops (read first)

- **Reasons are shown to the technician in the app AND stored in the audit log.** A reason must never contain a
  phone number, Aadhaar number, address, UPI VPA, document number or any other identifier (Golden Rules 6-7).
  Write "Skills could not be confirmed in person", not "Aadhaar 1234... did not match".
- **No document images or Aadhaar numbers are collected** in this flow. Do not photograph, copy or type them
  anywhere (reason, chat, notes). Ops looks at the original in person and records only the decision.
- Reasons are 1..500 characters. Only the fields below are accepted (strict bodies).

## Lifecycle

| From | Action | To | Actor | Notes |
|---|---|---|---|---|
| PENDING | submit | KYC_SUBMITTED | technician | needs name, at least 1 skill, at least 1 ACTIVE zone; locks the profile |
| KYC_SUBMITTED | verify | VERIFIED | ops | clears any earlier review note |
| KYC_SUBMITTED | send back + reason | PENDING | ops | reason shown to the technician; profile unlocks for edits |
| VERIFIED | suspend + reason | SUSPENDED | ops | refused while the technician has an active job |
| SUSPENDED | reinstate | VERIFIED | ops | |

Any other transition returns 409 `INVALID_TECHNICIAN_TRANSITION`. DEACTIVATED has no transitions in this slice.
Each transition writes a `TECHNICIAN_STATUS_CHANGED` audit row (from, to, reason).
The technician app learns of the decision by polling; there is no push or SMS yet.

## 1. In-person check (before verifying)

The technician comes to the ops contact. Before verifying, confirm:

1. The person in front of you is the person who registered (identity seen in person; nothing copied or stored).
2. The skills they selected are real (a short practical or conversational check).
3. The zones they selected are where they actually work.

If skills or zones need correcting, fix them first (section 4) or send the profile back (section 3).

## 2. Review queue and verify

```bash
# technicians waiting for review (also: PENDING, VERIFIED, SUSPENDED, DEACTIVATED; omit status for all)
curl -s "$BASE/admin/technicians?status=KYC_SUBMITTED" -H "authorization: Bearer $ADMIN" | jq

TECH=<technician id from the list>
curl -s -X POST "$BASE/admin/technicians/$TECH/verify" -H "authorization: Bearer $ADMIN" | jq
```

Errors: 409 `INVALID_TECHNICIAN_TRANSITION` = the technician is not KYC_SUBMITTED (already reviewed by someone
else, or never submitted). Re-list and check the current status.

## 3. Send back

```bash
curl -s -X POST "$BASE/admin/technicians/$TECH/send-back" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"reason":"Please add the zone you actually work in and resubmit."}' | jq
```

The technician sees the reason, edits their profile and resubmits. 409 `INVALID_TECHNICIAN_TRANSITION` = not
KYC_SUBMITTED. No identifiers in the reason — the API rejects (400) any reason containing a run of 10 or more
digits ("Don't include phone or ID numbers in the reason"); short numbers such as "Visit 2 of 3" are fine. The same
rule applies to the suspend reason.

## 4. Edit skills / zones

```bash
curl -s "$BASE/catalog/zones" -H "authorization: Bearer $ADMIN" | jq     # zone ids
curl -s -X PATCH "$BASE/admin/technicians/$TECH" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"skills":["AC","FAN"],"zoneIds":["<zone uuid>"]}' | jq
```

Either field may be sent alone; zones are replaced, not merged. Skills: `AC FAN ELECTRICAL WIRING APPLIANCE`.
Errors: an unknown technician id → 404; a malformed (non-uuid) technician or zone id → 400; a well-formed zone id
that is unknown or inactive → 422. The audit log records who/when, which fields changed, and the before/after
values of the edited fields (skills; zone ids, sorted).

**A VERIFIED technician with no zones sees no jobs** (the deploy backfill, section 6, gives existing technicians every
active zone, so this applies to technicians verified after it). Dispatch is in-zone: a technician only sees and can accept
jobs in their own zones (403 `JOB_OUT_OF_ZONE` otherwise).

## 5. Suspend / reinstate

```bash
curl -s -X POST "$BASE/admin/technicians/$TECH/suspend" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"reason":"Suspended pending a conduct review."}' | jq
curl -s -X POST "$BASE/admin/technicians/$TECH/reinstate" -H "authorization: Bearer $ADMIN" | jq
```

- 409 `TECHNICIAN_HAS_ACTIVE_JOB` on suspend: the technician has a job in ACCEPTED, EN_ROUTE, ARRIVED, DIAGNOSED,
  CUSTOMER_APPROVED, PARTS_REQUESTED, PARTS_ACQUIRED, REPAIR_IN_PROGRESS or REPAIR_COMPLETE. Suspending mid-job
  would strand the customer with a locked visit fee, and the suspend stays blocked until that job moves on.
  **There is no ops cancel/close endpoint.** Interim procedure: escalate to the engineer, who intervenes manually
  in the database (audited by hand). Jobs waiting only on payment (CUSTOMER_CONFIRMED, DECLINED_BY_CUSTOMER) no
  longer block: the technician's work is done, a suspended technician can't collect cash, and the customer's cash
  option falls back to UPI, so the platform keeps the money.
- 409 `INVALID_TECHNICIAN_TRANSITION`: suspend needs VERIFIED, reinstate needs SUSPENDED.
- 409 `TECHNICIAN_COLLECTING_CASH` on suspend: a customer has a cash payment in progress with this technician
  (a CASH attempt created in the last ~10 minutes, the life of the receipt code). Wait about 10 minutes and retry.
- The suspend/accept race is closed: suspend and accept serialize on the technician row, so a suspend either sees the
  just-accepted job (and answers `TECHNICIAN_HAS_ACTIVE_JOB`) or the accept is refused.
- Suspended and non-verified technicians get 403 `TECHNICIAN_NOT_VERIFIED` from job routes.

## 6. After a deploy: existing technicians were backfilled to every active zone

Before zones existed a VERIFIED technician was offered every zone's jobs. The migration
`technician_zone_backfill` preserves that: every existing VERIFIED or SUSPENDED technician was given every ACTIVE zone,
so nobody loses jobs at deploy. Ops should then narrow each technician to the zones they actually work in, using
section 4 (`PATCH ... {"zoneIds":[...]}`). Technicians who onboard after the deploy choose their own zones.

## 7. Payout requests

A technician of **any status** (including SUSPENDED) taps "Request payout" in the app. The request asks for everything
currently owed **minus the cash they hold** (cash debt), and must be at least `PAYOUT_MIN_PAISE` (default 10000 paise =
₹100; below it the app gets 422 `PAYOUT_BELOW_MINIMUM`). One open request per technician (409
`PAYOUT_ALREADY_REQUESTED`). Bank/UPI details are **collected in person, not in the app** — the platform never stores
them. Money is paid by hand. The request, the pay and the reject all write audit rows (Golden Rule 5).

### The queue

```bash
curl -s "$BASE/admin/payout-requests?status=REQUESTED" -H "authorization: Bearer $ADMIN" | jq
# status is optional: REQUESTED | PAID | REJECTED (omit for all). Oldest first.
```

Each row: `id`, `status`, `amountPaise` (what the technician asked for), `technicianName`, `maskedPhone`,
`technicianStatus`, `currentOwedPaise`, `currentCashDebtPaise` and **`currentNetPaise` = owed − cash debt = what to
transfer right now** (it can differ from `amountPaise` if money moved since the request), and `transferReference`
(null until PAID). All amounts are integer paise (10000 = ₹100).

### Paying — order of operations

1. Check `currentNetPaise` **and `technicianStatus`**. A SUSPENDED technician needs a second look (why were they
   suspended? is anything unresolved?) before you pay.
2. Transfer exactly `currentNetPaise` **by hand**, to the details collected in person. Note the bank/UPI transaction
   reference of that transfer.
3. Mark it paid with the amount and the reference:

```bash
REQ=<payout request id from the queue>
curl -s -X POST "$BASE/admin/payout-requests/$REQ/pay" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' \
  -d '{"amountPaise": <currentNetPaise you transferred>, "transferReference": "<bank/UPI transaction reference>"}' | jq
```

The body is required and strict: `amountPaise` (positive integer paise) and `transferReference` (4-64 characters,
letters, digits, `-` and `/` only, e.g. `UTR-2026-10-0001`; leading/trailing spaces are trimmed). Anything else is 400.
Under the technician lock the server recomputes the figure. **Cash debt is netted first** (a `CASH_DEBT_OFFSET` ledger
entry clears the debt from what is owed), then a `PAYOUT` entry is written for the rest and the request closes as PAID,
with the reference stored on the request and in the audit row. The response has `status: "PAID"` and **`paidPaise`** =
the amount actually paid, which the technician sees in the app. The technician never sees the reference.

Errors (all 409; nothing is written):
- `PAYOUT_AMOUNT_CHANGED` — "The amount to pay is now ₹X — check it before marking paid".
- `NOTHING_TO_PAY` — cash debt now covers everything owed.
- `PAYOUT_REQUEST_NOT_OPEN` — already paid or rejected (maybe by another admin).
- 404 — unknown id; 400 — malformed id or body.

**If you get `NOTHING_TO_PAY` or `PAYOUT_AMOUNT_CHANGED` BEFORE you transferred anything:** re-read the queue; adjust
and retry with the new amount, or reject the request. **If you already transferred and then get
`PAYOUT_AMOUNT_CHANGED` or `PAYOUT_REQUEST_NOT_OPEN`: stop and escalate to the engineer** (manual reconciliation).
Never transfer again.

### Rejecting

```bash
curl -s -X POST "$BASE/admin/payout-requests/$REQ/reject" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"reason":"Please visit the ops desk to confirm your payout details."}' | jq
```

The reason is 1-500 characters, **shown to the technician in the app and stored in the audit log**: never include a
phone number, account/ID/document number (the API refuses any 10+-digit run, separators ignored) or a UPI ID / email
address (the API refuses any `@`). Same 409 `PAYOUT_REQUEST_NOT_OPEN` if the request is already closed. A rejected
request can be re-raised by the technician.

### The payout queue is the only payout path

The old `POST /admin/settlements/payouts` endpoint has been **removed** (it returns 404). A `PAYOUT` ledger entry can
only be written by marking a payout request paid, which nets cash debt and requires the transfer reference.

### Deploy note

Three additive migrations (`technician_payout_requests`, `payout_request_entry_fk`,
`payout_request_transfer_reference`); deploy the backend before the app. Callers of `POST …/pay` must now send
`transferReference`.
