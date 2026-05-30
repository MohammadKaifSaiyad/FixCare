# Fraud Defenses

Every fraud vector and its specific structural block.

---

## The Master Rule

**No money moves without evidence.** No state transition without two-sided confirmation. No exceptions.

---

## Fraud Vector → Defense Map

### 1. Visit Fee Farming
**Attack:** Technician accepts job, arrives, "diagnoses" something unfixable, takes ₹149, leaves. Repeat 6x/day = ₹900/day with no work.

**Defense:**
- Visit fee credits toward labor if repair done (technician only profits on repairs)
- Technician cancellation rate >25% over 7 days → auto-restricted to repair-only jobs
- Pattern detection: same diagnoses + same outcomes flagged

---

### 2. Phantom Parts
**Attack:** Technician claims part was replaced, charges for it, but nothing actually changed.

**Defense:**
- **3 mandatory photos:**
  1. Old part removed (next to appliance)
  2. New part packaging
  3. New part installed
- No photos = no completion = no payment
- Random ops sampling: 5% of jobs reviewed weekly

---

### 3. Technician-Merchant Collusion
**Attack:** Technician has cousin running merchant account. They split inflated prices.

**Defense:**
- Catalog pricing — merchants quote at platform-set rates
- Merchant onboarding verifies physical shop (visit + license check)
- Same address/PAN/bank between technician and merchant → blocked
- Open market usage capped at 20% of monthly jobs per technician
- Periodic ops audit of high-volume technician-merchant pairs

---

### 4. Self-Dealing
**Attack:** Technician creates fake customer account, books jobs at relative's house, generates fake completions.

**Defense:**
- Multi-account detection: device fingerprint, UPI VPA, bank IFSC, address
- Address-pattern check: technician frequently servicing same/nearby addresses → flagged
- Email/phone reuse blocked
- Manual ops review for repeat patterns

---

### 5. Cash Skim Under the Limit
**Attack:** Technician keeps debt at ₹1800 indefinitely, collects cash, never escalates.

**Defense:**
- Dynamic cash limit based on tenure + GMV (not flat ₹2000)
- Debt aging alerts: any debt >7 days → flagged
- Velocity cap: ₹3000 cash/24h regardless of debt limit
- Customer-side cash confirmation closes the loop

---

### 6. Account Multiplication
**Attack:** Technician's wife/brother registers as a technician. Two cash limits = 2x effective skim.

**Defense:**
- Device fingerprint matching
- Bank account verification — same account = same person
- Aadhaar deduplication
- Family-name + address overlap flagged for manual review

---

### 7. Customer Dispute Griefing
**Attack:** Customer files dispute to freeze payout, then settles with technician offline at discount.

**Defense:**
- Customer dispute frequency tracked: >2 disputes in 30 days → account review
- Disputes require evidence (photo/explanation)
- Technician OTP at completion means customer already confirmed satisfaction
- False dispute history → reduced customer trust → manual review for future disputes

---

### 8. Technician-Customer Collusion Against Merchant
**Attack:** Technician tells customer "say the part was defective" to trigger return + refund split.

**Defense:**
- Returns require physical QR scan at merchant
- Damaged-return reports cross-checked with photos
- High return rates per technician-customer pair → flagged
- Merchant can dispute return (damaged-on-arrival flagged separately)

---

### 9. Bid/Pricing Cartel (Merchants)
**Attack:** Merchants in same zone agree on minimum prices via WhatsApp.

**Defense (V1 — no bidding anyway):**
- Catalog pricing pre-negotiated individually with each merchant
- No real-time auction = no cartel formation
- Per-SKU price variance monitoring across merchants
- Price clustering anomalies flagged

---

### 10. Trust Meter Reset Hopping
**Attack:** Technician hits ₹2000 → pays UPI → immediately starts again. Uses platform as rolling float.

**Defense:**
- Detect cyclical debt-then-pay-then-debt pattern
- Threshold: 3 reset cycles in 14 days → rate-limit OR convert to formal credit
- Cash compliance score drops, reducing limit

---

### 11. Visitation Without Arrival
**Attack:** Technician marks "arrived" from home, never actually goes, customer "doesn't answer," collects fee.

**Defense:**
- GPS validation on "arrived" tap (must be within X meters of customer location)
- Customer QR scan / OTP entry required — proves technician present
- Customer can report "no one came" → triggers investigation

---

### 12. Open Market Bill Fraud
**Attack:** Technician shows fake bill from "any local shop" at inflated price.

**Defense:**
- Bill photo required + parts photo in sealed packaging
- Customer must confirm in-app: "I saw these parts"
- Price capped at catalog × 1.15
- Open market usage capped per technician
- Manual sampling weekly; OCR validation in V2

---

### 13. Disintermediation
**Attack:** Technician says "next time call me direct, 20% cheaper."

**Defense:**
- All technician-customer calls go through Exotel masked numbers (V2)
- In-app chat only (V1)
- Technician repeat-customer rate monitored — drop below cohort baseline = flag
- Customer incentive to book through platform (warranty, rework guarantee, loyalty credits)
- Technician incentive to stay (bonuses, ratings, dispute protection)

---

### 14. KYC Identity Fraud
**Attack:** Bad actor uses someone else's Aadhaar/PAN.

**Defense:**
- DigiLocker integration (Aadhaar pulled from government source, not uploaded)
- Live selfie + face match at onboarding
- Video skill verification (face visible)
- ₹500 deposit from technician's verified bank account
- Periodic re-verification at trust threshold transitions

---

### 15. Fake Service Categories
**Attack:** Admin creates fake category for friend's specialty, manipulates routing.

**Defense:**
- Service category creation requires 2-admin approval
- Audit log on all admin actions
- Category-level revenue tracking (anomalies flagged)

---

## Fraud Detection Rules Engine (V1)

These rules run continuously in background workers:

| Rule | Trigger | Action |
|---|---|---|
| Multi-account | Same device/UPI/IFSC across accounts | Block, manual review |
| Self-dealing | Technician job address frequency anomaly | Flag for review |
| Visit farming | >25% cancellation rate over 7d | Repair-only mode |
| Open market overuse | >20% fallback usage | Pause + audit |
| Cash drift | Debt aging >7 days | Auto-restrict new jobs |
| Disintermediation | Technician repeat rate below baseline | Retention investigation |
| Photo absence | Any of 3 photos missing | Hard block completion |
| OTP bypass attempt | Technician tries to complete without OTP | Hard block + flag |
| Dispute clustering (customer) | >2 disputes in 30 days | Customer review |
| Dispute clustering (technician) | >5% dispute rate | Technician training |
| Debt cycling | 3+ reset cycles in 14 days | Convert to credit OR restrict |
| Cash velocity | >₹3000 in 24h | Block further cash collection |
| GPS spoof | "Arrived" location far from real GPS | Block visit fee claim |

---

## Manual Ops Checks (Weekly)

Even with automation, human eyes catch things rules miss:

- 5% random job sample reviewed against photos
- 1% customer phone audit: "Did you actually pay ₹X cash?"
- Top 10 merchants visited physically each month
- Technician spot-checks: random selfies during job
- Catalog price variance review (per SKU, per zone)

---

## Audit Trail Requirements

Every fraud-relevant action must be logged with:
- Actor (user_id)
- Action type
- Before/after state
- Timestamp (server time, not client)
- Source IP + device fingerprint
- Photos/evidence references

This log:
- Is append-only (no edits)
- Cannot be deleted by admins
- Backed up daily off-server
- Searchable for investigations

---

## Reporting

### Internal Reports (Daily)
- Fraud alerts triggered (by type)
- High-risk accounts identified
- Disputes opened/closed
- Cash debt aging summary
- Top fraud risks by zone

### For Investors/Stakeholders (Monthly)
- Fraud loss ratio (₹ lost / GMV)
- Detection time (avg hours to flag)
- False positive rate
- Account suspensions / reinstatements

---

## The Honest Truth

No system is 100% fraud-proof. The goal is:
1. Make fraud harder than legitimate work
2. Catch most fraud within days, not months
3. Limit per-incident loss to small amounts
4. Build evidence trails for prosecution if needed

If a single fraudster can lose us more than ₹10,000, the system has a hole. Fix it.
