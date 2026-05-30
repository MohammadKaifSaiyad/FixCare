# Vision & Scope

## What FixCare Is

A trusted marketplace for **home appliance repair and electrical services** in Vadodara and Padra, connecting:

- **Customers** — homeowners/businesses needing repair
- **Technicians** — verified repair professionals with trust scores
- **Merchants** — local hardware shops supplying parts

## Core Promise

> "Customers get honest service at fair prices. Technicians get fair pay and steady work. Merchants get steady customers and on-time payouts. The platform watches everything — no one can cheat."

## Three Pillars

1. **Trust** — Verified technicians, transparent pricing, photo evidence
2. **Transparency** — Catalog pricing, no hidden charges, customer sees everything
3. **Fair money flow** — Technicians paid quickly, merchants settled T+1, platform earns predictably

---

## In Scope (V1)

### Services
- Home appliance repair (AC, fan, geyser, washing machine, refrigerator)
- Electrical work (wiring, switches, fittings)
- Service categories are **dynamic** (admin creates them, not hardcoded)

### Geography
- **Vadodara city** (urban pricing)
- **Padra** (rural pricing)
- Geofenced labor rates

### Apps (V1)
- **FixCare** — Customer app (Android only)
- **FixCare Pro** — Technician app (Android only)
- **Admin Dashboard** — Web (Next.js)
- **Merchant flow** — WhatsApp bot + web form (NO dedicated app in V1)

### Key Features
- Phone OTP authentication
- Service catalog & booking
- Technician dispatch & live tracking
- 3-photo evidence checkpoints
- QR/OTP arrival & completion handshakes
- Visit fee + labor + parts pricing
- Preferred merchant routing (no bidding)
- UPI default + cash secondary
- Trust meter (2 scores)
- Cash debt limits (graduated)
- T+1 merchant settlement
- 7-day rework warranty
- Tiered dispute resolution

---

## Out of Scope (V1)

Will tackle after V1 ships:

- **iOS apps** (V2 — after Android traction)
- **Dedicated merchant app** (V2 — WhatsApp suffices)
- **Merchant bidding auctions** (V2 — need density first)
- **OCR bill scanning** (V2)
- **AMC subscription plans** (V1.5)
- **Old parts scrap resale** (V3)
- **Other cities beyond Vadodara/Padra** (after PMF)
- **Multi-language UI** (Hindi/Gujarati only initially, both in Devanagari/Latin script)
- **Advanced fraud ML models** (rules-based engine in V1)
- **Instant merchant payouts** (T+1 only)

---

## Who Is the Customer

**Primary:** Homeowners aged 30-60 in Vadodara/Padra
- Frustrated with unreliable local technicians
- Has smartphone, uses UPI
- Pays ₹500-5000 per repair job
- Values: trust, transparency, no haggling

**Secondary:** Small businesses, shops, offices
- Higher frequency
- May need GST invoices
- AMC potential

---

## Success Criteria for V1

- 100 active customers in Vadodara within 3 months of launch
- 30 active technicians onboarded and rated 4.0+
- 5 active merchants per service zone
- Dispute rate <5%
- Cash debt aging issues <10% of technicians
- Repeat customer rate >25% within 6 months
- Technician retention >60% at 6 months

---

## What Could Kill This

Be honest about risks:

1. **Technician disintermediation** — Customer takes technician's number, calls direct next time
2. **Low repair frequency** — Most homes need 2-4 jobs/year only
3. **Cash leakage** — Technicians under-report cash collections
4. **Merchant disengagement** — Hardware shops ignore platform requests
5. **Competition** — UrbanCompany expands to Vadodara
6. **Solo dev burnout** — 10-14 months is long

Each of these is addressed in `02-product/` and `06-operations/`.
