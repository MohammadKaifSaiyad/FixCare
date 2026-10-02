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
KYC_SUBMITTED. No identifiers in the reason.

## 4. Edit skills / zones

```bash
curl -s "$BASE/catalog/zones" -H "authorization: Bearer $ADMIN" | jq     # zone ids
curl -s -X PATCH "$BASE/admin/technicians/$TECH" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"skills":["AC","FAN"],"zoneIds":["<zone uuid>"]}' | jq
```

Either field may be sent alone; zones are replaced, not merged. Skills: `AC FAN ELECTRICAL WIRING APPLIANCE`.
Invalid or inactive zone ids return 422. The audit log records which field names changed and who/when, not the
before/after values.

**A VERIFIED technician with no zones sees no jobs.** Dispatch is in-zone: a technician only sees and can accept
jobs in their own zones (403 `JOB_OUT_OF_ZONE` otherwise).

## 5. Suspend / reinstate

```bash
curl -s -X POST "$BASE/admin/technicians/$TECH/suspend" -H "authorization: Bearer $ADMIN" \
  -H 'content-type: application/json' -d '{"reason":"Suspended pending a conduct review."}' | jq
curl -s -X POST "$BASE/admin/technicians/$TECH/reinstate" -H "authorization: Bearer $ADMIN" | jq
```

- 409 `TECHNICIAN_HAS_ACTIVE_JOB` on suspend: the technician has a job between ACCEPTED and CUSTOMER_CONFIRMED (or
  DECLINED_BY_CUSTOMER). Suspending mid-job would strand the customer with a locked visit fee. Resolve the job
  first (let it complete, or cancel through the booking process), then suspend.
- 409 `INVALID_TECHNICIAN_TRANSITION`: suspend needs VERIFIED, reinstate needs SUSPENDED.
- Known race: a technician who accepts a job in the instant ops suspends them can end up SUSPENDED with one active
  job. Reinstate them; money still needs the customer's OTP, so nothing can move unconfirmed.
- Suspended and non-verified technicians get 403 `TECHNICIAN_NOT_VERIFIED` from job routes.

## 6. After a deploy: existing VERIFIED technicians have no zones

The zone migration is additive; technicians verified before it have no zones and see no jobs. Before announcing the
release, give each one zones with section 4 (`PATCH ... {"zoneIds":[...]}`).
