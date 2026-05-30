# Pricing Model

Three transparent components. Every rupee visible to every party.

---

## Component 1: Visit Fee

Charged when technician arrives at customer location.

| Zone | Visit Fee |
|---|---|
| Vadodara city | ₹149 |
| Padra / rural | ₹99 |

### Critical Rule
- **If customer proceeds with repair:** Visit fee is **credited toward labor** (not added on top)
- **If customer declines repair:** Technician keeps the visit fee, platform takes small cut

### Why This Design
Kills "visit farming" — technicians no longer earn from showing up + leaving.
Visit fee only becomes real revenue when customer cancels (rare).
Technicians are now incentivized to do the actual repair.

---

## Component 2: Labor Charge

**Catalog-based pricing. Technician cannot change this.**

### Examples (Geofenced)
| Service | Vadodara | Padra |
|---|---|---|
| AC gas refill | ₹600 | ₹500 |
| Capacitor replacement | ₹250 | ₹200 |
| Ceiling fan rewinding | ₹400 | ₹350 |
| Switchboard installation | ₹300 | ₹250 |
| Geyser thermostat replacement | ₹350 | ₹300 |

### Labor Tiers (For Complex Jobs)
- **T1** — Simple (single component, <30 min)
- **T2** — Standard (multiple parts, 30-90 min)
- **T3** — Complex (full assembly, 90+ min)

Technician selects tier; customer approves before work starts.

---

## Component 3: Parts

**Master catalog with ceiling prices. Negotiated merchant rates.**

### How It Works
- Platform maintains 200-300 SKU catalog with MRP-aligned ceiling prices
- Merchants quote their actual cost (negotiated, locked in catalog)
- Customer sees catalog price
- Margin between merchant cost and catalog price = platform's parts revenue
- Technician has **zero discretion** on parts pricing

### Example
- 50mfd Capacitor catalog price: ₹500
- Merchant cost: ₹420
- Platform margin: ₹80

---

## Revenue Split (Per Job)

| Component | Customer Pays | Technician Gets | Merchant Gets | Platform Gets |
|---|---|---|---|---|
| Visit fee (no repair) | ₹149 | ₹120 (80%) | — | ₹29 (20%) |
| Labor (repair done) | ₹600 | ₹480 (80%) | — | ₹120 (20%) |
| Parts | ₹500 catalog | — | ₹420 (84%) | ₹80 (16%) |

### Sample Full Job
- AC gas refill in Vadodara
- Visit fee: ₹149 (credited toward labor)
- Labor: ₹600
- Parts (gas): ₹500
- **Customer pays:** ₹1,100 total (visit fee credited)
- **Technician earns:** ₹480 (labor 80%)
- **Merchant earns:** ₹420 (parts cost)
- **Platform earns:** ₹200 (labor 20% + parts margin)

---

## Bonus Tiers (Trust Loop)

### Technician Bonuses
- ₹50 per job after 5 jobs/day
- ₹100 per job after 25 jobs/week with rating ≥4.5
- ₹500 monthly retention bonus at 50+ jobs with <2 disputes

### Merchant Bonuses
- 1% of monthly GMV bonus if:
  - Return rate <5%
  - Stock confirmation rate >90%

### Customer Incentives
- ₹50 wallet credit after first completed job
- ₹100 credit per successful referral
- AMC plan: ₹999/year for 4 appliances at ~30% discount on labor

---

## UPI vs Cash Pricing

| Payment Method | Customer Pays | Why |
|---|---|---|
| UPI | Total amount | Default, no friction |
| UPI (with discount) | Total minus ₹20 | Nudge toward digital |
| Cash | Total amount | Higher friction (in-app confirm, OTP, debt accrual) |

---

## Open Market Premium

When technician buys from non-preferred merchant (fallback mode):

- Technician pays retail price at any shop
- Customer charged: catalog price × 1.15 (15% premium for sourcing effort)
- Difference covers technician's time/effort
- **Capped at 20% of technician's monthly jobs** to prevent abuse

---

## Refund/Reversal Logic

| Scenario | Customer Refund |
|---|---|
| Job cancelled before technician dispatched | 100% |
| Technician dispatched but didn't arrive | 100% + ₹50 inconvenience credit |
| Technician arrived, customer declined diagnosis | Visit fee NOT refunded |
| Work done but customer disputes (within 24h) | Held in escrow until resolved |
| Rework needed (within 7 days, same issue) | Free return visit, no refund |
| Defective part (within 30 days) | Part cost refunded, replacement free |

---

## Cost-of-Living Indexing (For Future Scaling)

When scaling beyond Gujarat, **all prices indexed by city tier:**

- Tier 1 (Mumbai, Bangalore, Delhi): 1.5x base
- Tier 2 (Vadodara, Ahmedabad, Pune): 1.0x base
- Tier 3 (Padra, smaller towns): 0.8x base

This avoids the ₹2000 cash limit problem (meaningless in Mumbai, excessive in Padra).

---

## Why This Pricing Model Wins

1. **Transparent** — Every rupee is itemized for customer
2. **Fraud-resistant** — Technician has no discretion to inflate
3. **Aligned incentives** — Technician earns from completion, not visits
4. **Predictable** — Customer knows cost before booking
5. **Scalable** — Catalog-driven means new services add easily
6. **Defensible** — Platform margin on every component
