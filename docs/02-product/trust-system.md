# Trust System

Replace single "Trust Meter" with **two separate scores + one dynamic limit**.

---

## The Problem with a Single Trust Meter

Original design conflated two different things:
- Cash discipline (paying back debts)
- Service quality (good work)

A technician with ₹0 cash debt and terrible ratings would look "trusted."
A great technician with temporary debt would be punished.

**Solution:** Separate them.

---

## Score 1: Service Trust

**Visible to customers as a star rating.**

### Inputs
| Factor | Weight |
|---|---|
| Customer rating average | 40% |
| Job completion rate | 20% |
| On-time arrival rate | 15% |
| Photo-evidence compliance | 15% |
| Dispute rate (inverse) | 10% |

### Calculation
Rolling 30-day window, recalculated nightly.

```
service_trust = (
  0.40 × avg_rating +
  0.20 × completion_rate +
  0.15 × on_time_rate +
  0.15 × photo_compliance +
  0.10 × (1 - dispute_rate)
) × 5  // Scale to 5 stars
```

### Display
Customer sees 1-5 stars + total job count.

---

## Score 2: Cash Compliance

**Internal-only. Drives the cash debt limit.**

### Inputs
- Debt-to-GMV ratio
- Speed of cash settlement (days)
- Frequency of hitting debt limit
- UPI vs cash collection ratio

### Calculation
Rolling 60-day window.

```
cash_compliance = (
  0.40 × upi_collection_ratio +
  0.30 × (1 - avg_debt_aging_days / 30) +
  0.20 × settlement_speed_score +
  0.10 × (1 - limit_hit_frequency)
) × 100  // Scale 0-100
```

### Display
Technician sees in their app: "Cash Compliance: 87/100"
Not shown to customers.

---

## Dynamic Cash Limit

**Graduated trust ladder.** Technicians earn higher cash capacity by behaving well.

| Stage | Conditions | Cash Limit |
|---|---|---|
| New technician | 0-19 jobs | ₹500 |
| Established | 20+ jobs | ₹1,500 |
| Trusted | 50+ jobs, ≥4.0 rating, ≤2 disputes | ₹3,000 |
| Senior | 100+ jobs, ≥4.5 rating, ≥90% cash compliance | ₹5,000 |

### Reset Conditions
- Any pending dispute → limit drops to ₹0 immediately
- Resolved in technician's favor → limit restored
- Resolved against technician → limit drops one tier

---

## Cash Velocity Cap

**Independent of debt limit.**

Max ₹3,000 cash collected per 24-hour window.

Why: Prevents single-day blowup scenarios.
A technician can have ₹5,000 limit but still can't collect ₹4,000 cash in one day.

---

## Customer Cash Confirmation

For every cash transaction:

1. Customer sees in-app: "I will pay ₹[X] cash"
2. Customer taps confirm
3. Technician confirms receipt via separate OTP
4. If amounts mismatch → auto-dispute

This kills "technician says ₹600, customer paid ₹500" disputes.

---

## Technician Security Deposit

**₹500 refundable** collected at onboarding.

- Held by platform
- Refunded after 50 successful jobs (or on exit)
- Forfeited if technician disappears with cash debt
- Acts as skin-in-the-game

---

## Trust Score Decay

Technicians inactive for 30+ days:
- Service Trust frozen at last value
- Returning technicians get a "Verification Check" — must re-confirm identity before going online

Prevents account sale/transfer to bad actors.

---

## Service Trust Display Examples

| Technician Profile | Customer Sees |
|---|---|
| 5 jobs, 5.0 rating | "★★★★★ (5 jobs) — New technician" |
| 50 jobs, 4.7 rating | "★★★★★ (50 jobs)" |
| 200 jobs, 4.3 rating, ⚡Fast response | "★★★★ (200 jobs) — Verified Pro" |
| 100 jobs, 3.8 rating | "★★★★ (100 jobs)" |
| Newly onboarded | "New — Verified by FixCare" |

---

## Anti-Gaming Protections

### Detect Multi-Account Technicians
- Same device fingerprint
- Same UPI VPA / bank IFSC
- Same family address
- Same emergency contact

→ Flag for manual review, suspend if confirmed.

### Detect Rating Manipulation
- Technician creates customer accounts to self-rate
- Same device, low job-completion friction, perfect ratings → flag
- Multi-account detection above handles most of this

### Detect Debt Cycling
- Technician hits ₹2000 → pays UPI → immediately hits again
- Pattern flagged: "Using platform as working capital"
- Action: Convert to formal credit product OR restrict cash payments for this technician

---

## What Trust Earns You

Higher Service Trust unlocks:
- Priority in dispatch algorithm
- Premium job categories (high-value repairs)
- Early access to new service categories
- "Verified Pro" badge in customer app
- Lower platform commission tiers (long-term)

Higher Cash Compliance unlocks:
- Higher cash debt limit
- Faster payout windows (T+1 instead of T+2)
- Reduced security deposit hold

---

## What Distrust Costs You

Lower scores trigger:
- Reduced dispatch priority
- Mandatory training video re-watch
- Mandatory in-person ops meeting
- Suspended until improvement plan completed
- Account terminated + deposit forfeited

Tiered response, not binary banning.
