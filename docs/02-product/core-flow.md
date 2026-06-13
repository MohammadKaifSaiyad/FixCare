# Core Service Flow

End-to-end journey for a single job, with fraud locks at each phase.

---

## Phase 0 — Onboarding (One-Time Per Actor)

### Technician
- Phone OTP
- Aadhaar verification via DigiLocker (Setu)
- PAN verification (Karza)
- Skill verification:
  - In-person test by ops/ITI partner
  - OR recorded video showing capability
- Bank account + UPI VPA
- **₹500 refundable security deposit**
- Photo + biometric
- Unique QR badge (used for customer verification on arrival)

### Customer
- Phone OTP only
- Name + address
- UPI VPA captured at first booking (optional)
- Aadhaar optional (unlocks AMC plans later)

### Merchant
- GST + shop license + PAN
- Catalog pricing for top 50 SKUs (negotiated with platform)
- UPI + bank account for T+1 settlement
- One onboarding training call

---

## Phase A — Booking & Dispatch

### Customer Flow (3 taps)
1. Pick service category
2. Confirm address + time slot
3. See visit fee, tap "Book"

### Backend Actions
- Determine zone (Vadodara/Padra) → apply geofenced rate
- Calculate labor tier if applicable
- **Broadcast dispatch:** the booking opens to *all eligible technicians* (VERIFIED + matching
  skill). The **first to accept wins** (atomic claim). See ADR
  [`docs/decisions/2026-06-13-dispatch-broadcast-model.md`].
  - _Future (deferred):_ a weighted ranking `rating × proximity × current_load × cash_compliance`
    to order/limit who's offered the job, and a per-offer accept timer — both need the trust-score,
    location, cash, and queue subsystems that don't exist yet.
- Visit fee **authorized** (not charged) via UPI AutoPay _(payment slice — not in dispatch)_

### What Customer Sees
- Technician name, photo, masked phone, QR-badge ID (once a technician has accepted)
- ETA based on technician location _(deferred — needs technician location)_

### What Technician Sees
- The open job in their available list: service, zone, fees, **address with masked customer phone**
- Accept (first-to-accept wins) or skip (hides it from their own list)
  - _Future (deferred):_ a per-offer 30-second accept timer

### 🔒 Fraud Locks at This Phase
- Customer with unsettled payment → blocked from booking
- Technician at cash debt limit → cannot accept
- Technician booking own neighborhood repeatedly → flagged (self-dealing detection)

---

## Phase B — Arrival & Diagnosis

### The Arrival Handshake (Keystone #1)

```
Technician reaches location
  → Tap "Arrived" (GPS validated)
  → Customer scans technician's QR
    OR enters 4-digit code technician shows
  → Visit fee LOCKED
```

**Without this handshake:**
- Technician can't claim visit fee
- Customer can't dispute "no one came"
- Platform has tamper-proof presence proof

### Diagnosis Step
- Technician takes **2 mandatory photos**:
  - Appliance overview
  - Close-up of fault
- Selects diagnosed issue from **structured dropdown** (no free text)
- System auto-suggests parts cart from catalog
- Technician can add/remove items (changes logged)

### Customer Decision
- Sees: diagnosis + parts list + total estimate + visit fee credit applied
- ✅ Approve → flow continues
- ❌ Decline → visit fee charged, technician paid out, job ends cleanly

### 🔒 Fraud Locks at This Phase
- Photos mandatory + geotagged + timestamped
- Diagnosis-to-parts mismatch flagged (e.g., "fan issue" + "AC capacitor")
- Customer sees catalog prices — technician cannot pad
- Free-text diagnosis is impossible (dropdown only)

---

## Phase C — Parts Procurement

### V1 Model: Preferred Merchant Routing (NO Bidding)

```
System routes parts cart to nearest preferred merchant
with stock_confidence > 70%
  → Merchant gets push: "Confirm stock in 90 sec"
  → Tap response:
    ✅ All available → technician picks up
    ⚠ Partial → routes to next merchant
    ❌ Not available → routes to next merchant
```

### Fallback: Open Market Mode

Triggers when:
- 2 merchant rejections, OR
- 5 minutes elapsed

Technician buys from any local shop:
- Uploads photo of bill
- Uploads photo of parts (in original sealed packaging)
- Customer confirms in-app: "Yes, I saw these parts"
- **Price capped at catalog × 1.15** (15% sourcing premium)

### 🔒 Fraud Locks at This Phase
- Open market usage **capped at 20% of technician's monthly jobs**
- Bill photo required (manual sampling for fakes initially, OCR later)
- Customer sees actual bill, not technician-entered amount
- Excessive open-market = collusion alert

---

## Phase D — Repair Execution

### Three Mandatory Photo Checkpoints

| # | Photo | What it proves |
|---|---|---|
| 1 | Old part removed (held next to appliance) | Part was actually replaced |
| 2 | New part packaging (sealed/unsealed) | Genuinely new, not used/fake |
| 3 | New part installed (final state) | Work was completed |

**No photos = no job completion = no payment.**

### Old Part Handling
- Customer can keep old part if they want
- Default: technician takes it (some have scrap value — V3 feature)

### 🔒 Fraud Locks at This Phase
- Phantom parts (charging without replacing) → blocked by photo #1
- Counterfeit/used parts → packaging photo creates accountability
- Incomplete work → installed photo confirms

---

## Phase E — Completion & Payment

### The Completion Handshake (Keystone #2)

```
Customer reviews final bill
  → Taps "Confirm work completed satisfactorily"
  → 4-digit OTP sent to customer phone
  → Customer reads OTP to technician
  → Technician enters OTP in technician app
  → ONLY THEN job marked complete + payment unlocked
```

**Why this is critical:**
- Technician can't unilaterally close jobs
- Customer can't claim "bad work" later without cause (they confirmed)
- Disputes drop dramatically

### Payment Options

**UPI (default, encouraged):**
- Customer pays via UPI Intent
- Money → platform escrow
- Splits queued: merchant T+1, technician T+2, platform commission booked
- Technician sees "✅ Payment received" instantly
- ₹20 discount nudges digital adoption

**Cash (secondary, friction-added):**
- Customer confirms exact amount in-app
- Customer digitally signs (taps confirm)
- Technician confirms receipt via separate OTP
- Technician's cash debt to platform increases
- Technician sees running balance

### 🔒 Fraud Locks at This Phase
- Cash discrepancy (technician says ₹600, customer confirms ₹500) → auto-dispute
- Cash collection **capped at ₹3000 / 24h** regardless of debt limit
- UPI discount makes digital cheaper for customer

---

## Phase F — Post-Job Window

### Customer Side
- 24-hour rating window (stars + photo + comment)
- **7-day rework warranty** — same issue = free return visit
- 30-day complaint window for new issues

### Technician Side
- Earnings credited to wallet at T+2 (after 48-hour dispute window)
- Withdraw to bank instantly after that

### Merchant Side
- Daily settlements consolidated → paid 10 AM T+1
- Returns processed via QR scan (technician scans merchant's QR within return window)

### Return Windows
- Jobs before 6 PM → return parts before shop closing
- Jobs after 6 PM → return by 1 PM next day
- Only QR scan reverses the part charge

---

## The Two Keystones (If You Remember Nothing Else)

1. **QR/OTP Arrival Handshake** — Proves technician showed up
2. **Customer OTP Completion Handshake** — Proves work was done

Plus **3 photo checkpoints** in Phase D.

These 5 micro-interactions kill 90% of the fraud surface area without adding complexity for honest users.

---

## State Machine Reference

Job goes through these states:

```
CREATED → DISPATCHED → ACCEPTED → EN_ROUTE → ARRIVED
  → DIAGNOSED → CUSTOMER_APPROVED → PARTS_REQUESTED
  → PARTS_ACQUIRED → REPAIR_IN_PROGRESS → REPAIR_COMPLETE
  → CUSTOMER_CONFIRMED → PAYMENT_RECEIVED → CLOSED

Branches:
  → CANCELLED_BY_CUSTOMER (anywhere before ARRIVED)
  → CANCELLED_BY_TECHNICIAN (anywhere before ARRIVED)
  → DECLINED_BY_CUSTOMER (after DIAGNOSED) → visit fee only
  → DISPUTED (from CUSTOMER_CONFIRMED → resolved → CLOSED)
```

Each transition triggers events: notifications, ledger entries, audit log writes.
