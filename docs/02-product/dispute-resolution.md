# Dispute Resolution

Tiered workflow by amount + automation where possible.

---

## Why Disputes Matter

Repair services have inherently subjective quality. A 10% dispute rate is normal at start, declining with maturity. Disputes are:
- Inevitable
- A trust signal when handled well
- An operational tax that must be automated

---

## Tier System

| Amount | Resolution Method | SLA |
|---|---|---|
| ≤ ₹500 | Auto-resolve | Immediate |
| ₹500 – ₹2,000 | Human reviewer | 24 hours |
| ₹2,000+ | Senior reviewer + phone | 72 hours |

---

## Tier 1: Auto-Resolve (≤₹500)

### Logic
- Photo evidence reviewed against rules
- If photos complete + customer OTP exists → favor technician
- If photos incomplete OR no customer OTP → favor customer
- If ambiguous → refund customer (cheap insurance)

### Why Auto-Refund Below ₹500
- Support cost of human review > the disputed amount
- Customer trust > marginal fraud loss
- Bad actor patterns caught by frequency tracking (not single-incident)

---

## Tier 2: Human Reviewer (₹500 – ₹2,000)

### Process
1. Reviewer pulls all evidence in dashboard
2. Reviews photos, chat logs, GPS trail, OTP timestamps
3. Decides within 24 hours
4. Both parties notified with reasoning
5. Money moves accordingly

### Standard Evidence Checklist
- Customer arrival OTP recorded?
- 3 repair photos present?
- Customer completion OTP entered?
- Diagnosis matches parts cart?
- Bill matches catalog pricing?
- GPS trail consistent with work timeline?
- Chat logs (if any) reviewed?

### Outcomes
- Technician fully at fault → refund customer, deduct from technician payout
- Partial fault → split refund proportionally
- Customer fully at fault → no refund, warn customer
- No clear fault → refund customer (favor customer when unclear)

---

## Tier 3: Senior Review (>₹2,000)

### Process
1. Senior reviewer assigned
2. Phone call to customer (10-15 min, recorded)
3. Phone call to technician (10-15 min, recorded)
4. Photos + evidence re-examined
5. Decision within 72 hours
6. Both parties notified with detailed reasoning

### Special Cases
- High-value parts dispute: merchant brought into review
- Damage claims (technician broke something): photos + estimate required
- Safety incident: escalated to legal/insurance review

---

## Payout Hold During Dispute

While dispute is open:
- Technician payout for this job: HELD
- Merchant payout for this job: HELD (if part-related)
- Customer's wallet credit: HELD pending resolution
- Platform commission: HELD

Once resolved:
- All hold releases happen simultaneously
- Audit log records resolution + reasoning

---

## Common Dispute Scenarios

### Scenario 1: "Work was bad"
- **Customer claim:** AC still not cooling after repair
- **Resolution:** Free rework within 7 days (covered by warranty)
- **No refund** unless technician refuses to return
- **If recurring issue:** Same-issue rework guarantee triggers automatically

### Scenario 2: "Technician overcharged"
- **Customer claim:** Bill higher than expected
- **Reviewer checks:** Bill itemization matches catalog
- **If catalog matches:** Customer educated, no refund
- **If padding detected:** Refund + technician warning + audit

### Scenario 3: "Part is defective"
- **Customer claim:** New part stopped working in 2 days
- **Resolution:** Free replacement under 30-day part warranty
- **Merchant flagged:** Track defect rate; merchant penalty if high

### Scenario 4: "Technician didn't show up"
- **Customer claim:** No technician arrived
- **Reviewer checks:** Was arrival OTP entered? GPS trail?
- **If no OTP + no GPS at location:** Refund + technician penalty
- **If OTP entered:** Technician present; customer disputes false → warning

### Scenario 5: "Technician damaged appliance"
- **Customer claim:** TV scratched, appliance broken during repair
- **Tier 3 escalation always**
- **Photo evidence (before repair) checked**
- **Technician liability up to ₹5,000 (deductible from earnings + deposit)**
- **Beyond ₹5,000: insurance claim (when we get coverage in V2)**

### Scenario 6: "Cash amount disagreement"
- **Technician says:** ₹600 collected
- **Customer says:** ₹500 paid
- **Auto-resolved:** Lower of two amounts is treated as paid
- **Technician debt adjusts accordingly**
- **If pattern detected:** Technician audit

---

## Dispute Outcomes Tracking

Per-account stats tracked for trust scores:

### Technician Side
- Disputes filed against them
- Disputes resolved in their favor
- Average dispute amount
- Pattern of dispute types

### Customer Side
- Disputes they've filed
- Disputes ruled in their favor
- Frequency
- Pattern of dispute types

---

## Customer Abuse Detection

A customer is flagged if:
- >2 disputes in 30 days
- >5 disputes in 90 days
- Disputes always after work completion
- Disputes always with different technicians
- High refund-receive rate

### Action Tiers
1. **First flag:** Soft warning, dispute review prioritizes technician evidence
2. **Second flag:** Account review, possible suspension
3. **Third flag:** Suspended; deposit any unused credits frozen

---

## Technician Discipline Tiers

| Disputes per 30 days | Action |
|---|---|
| 1 | Tracked, no action |
| 2 | Warning, training video required |
| 3-4 | Suspended for 7 days, ops meeting |
| 5+ | Suspended pending review, possible termination |

---

## Appeals Process

Either party can appeal a Tier 2 or Tier 3 decision once:
- Must submit written reason within 7 days
- Senior reviewer (not original) re-examines
- Decision is final after appeal

No appeal for Tier 1 (auto-resolve) decisions — too low-value.

---

## Dispute Dashboard (Internal)

The admin dashboard shows:
- Open disputes (by tier, SLA status)
- Resolved disputes (last 30 days)
- Top dispute reasons (categorized)
- Technician dispute rates (sorted, color-coded)
- Customer dispute rates (sorted, color-coded)
- Dispute resolution time trends
- Refund amount totals

---

## Cost of Disputes (Planning)

Realistic expectations:

| Metric | Target |
|---|---|
| Dispute rate (V1 launch) | ≤10% |
| Dispute rate (mature) | ≤3% |
| Refund cost as % of GMV | ≤2% |
| Avg resolution time | <24 hours |
| Customer satisfaction post-dispute | ≥70% |

---

## Building This (Implementation Notes)

For solo dev, V1 is:
- Disputes filed in customer/technician app via simple form
- All disputes land in admin dashboard
- You personally review each one for first 6 months
- Track patterns manually
- Refine rules from observations

Don't build complex ML or chatbots in V1. Manual review is fine at <1000 jobs/month and teaches you the patterns.

By V2: structured forms, automated Tier 1, dispute analytics, possibly a part-time ops person.
