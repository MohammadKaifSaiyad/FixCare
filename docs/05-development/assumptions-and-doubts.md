# Assumptions, Doubts & Risks in the Development Plan

Honest review of where the development plan rests on assumptions or has hidden risks. **Read this before starting Month 0.**

---

## How to Read This Doc

Each item below is one of:
- 🟡 **Assumption** — Something I treated as true that may not be
- 🔴 **Risk** — Real danger I may have underplayed
- 🟠 **Hidden Complexity** — Something more complex than I made it sound
- ⚪ **Unspecified** — Important thing I didn't address

Each item has: what, why it matters, what to do about it.

---

## 🟡 Timeline (10-14 months solo)

### What I Assumed
Solo dev + vibe coding (with Claude Code + Superpowers) can ship V1 in 10-14 months.

### Reality
- Assumes 6 productive hours daily, 5-6 days a week, for 10-14 months
- Doesn't account for: holidays, illness, motivation dips, family obligations, festivals (Diwali/Navratri are 2+ weeks in Gujarat), wedding seasons
- Doesn't account for: learning curve on Flutter (you have no mobile experience)
- Doesn't account for: vendor approval delays (Razorpay, MSG91, WhatsApp BSP, KYC vendors)

### Realistic Range
**12-18 months** is more honest. 10 months is best-case.

### What to Do
- Plan for 14 months mentally; treat earlier ship as bonus
- Build in 2-week buffer per quarter for delays
- Don't promise launch dates externally until Month 8+
- Track velocity weekly; if behind schedule by Month 3, cut scope, don't extend timeline

---

## 🔴 Background Location Tracking on Android (Worker App)

### What I Said
"Background location tracking when worker is online, battery-optimized."

### Hidden Complexity
Android 12+ has notoriously hostile background location restrictions:
- **OEM aggression:** Xiaomi (MIUI), Realme (Realme UI), OPPO (ColorOS), Vivo (FunTouchOS) all aggressively kill background services to save battery — even Google's own guidelines don't help
- **Doze mode + App Standby Buckets:** Even pure Android kills inactive apps
- **Foreground service notification required:** Persistent notification = workers may dismiss/disable
- **Battery optimization permission:** Each user must manually whitelist your app per OEM-specific UI

### Real-World Impact
- Worker comes back from lunch, location stale → can't accept jobs → angry worker
- Worker app killed mid-job → customer tracking screen freezes → angry customer
- Different bug per OEM = hard to reproduce

### What to Do
- Test extensively on **at least these devices:** Xiaomi (Redmi), Realme, Samsung, Motorola, Vivo
- Use `flutter_background_geolocation` (paid for production: ~$199, but worth it) over free alternatives
- Build OEM-specific onboarding screens guiding workers to enable background permissions
- Add server-side stale-location detection: if worker hasn't pinged in 5 min, auto-mark offline
- Accept that some jobs will be missed; SLA can't be 100%
- **Budget extra month for this alone** if doing it right

---

## 🔴 Razorpay Route (Split Payments) Approval

### What I Said
"Use Razorpay Route to split payments to merchant + worker + platform."

### Hidden Complexity
Razorpay Route requires:
- **Marketplace Aggregator approval** from Razorpay (extra KYC tier)
- Approval takes **2-4 weeks beyond regular KYC**
- May need to demonstrate proof of business model
- For some business categories, requires RBI Payment Aggregator (PA) license — though FixCare likely qualifies as a marketplace, not a PA

### Real-World Impact
- Plan assumes you can start splitting payments by Month 3
- Realistic: not before Month 4-5
- Until then: payments go to platform account, manual settlements to merchants/workers

### What to Do
- Apply for Razorpay Route **on Day 1** (parallel with regular KYC)
- Have legal counsel review your marketplace model vs PA license (₹10-20k consultation)
- Plan for manual settlement during first 3 months
- Document settlement reconciliation process even if manual

---

## 🟠 KYC Vendor Integration Is Painful

### What I Said
"Setu for Aadhaar, Karza for PAN. ₹10-30 per verification."

### Hidden Complexity
- **Sandbox ≠ Production:** Sandbox always succeeds; production has edge cases (mismatched names, NSDL downtime, DigiLocker outages)
- **Vendor approval cycles:** Each vendor wants business KYC + use-case justification before granting production keys (1-2 weeks each)
- **Failed verifications still cost money:** ₹10-30 per attempt, success or fail
- **Aadhaar privacy compliance** (UIDAI guidelines + DPDP Act): your data handling must be auditable
- **Aadhaar masking required:** Last 4 digits visible, rest masked in any UI/log
- **Re-verification flows:** When KYC fails, the retry UX is genuinely hard

### What to Do
- Apply for vendor accounts **Day 1**
- Budget ₹5-10k for failed verification costs during development
- Test with multiple real Aadhaar holders (family/friends) before launch
- Build retry flow that handles ambiguous failure states
- Get DPDP-compliant privacy policy reviewed by lawyer

---

## 🟠 MSG91 DLT & WhatsApp Business API Timelines

### What I Said
"MSG91 DLT: 5-7 days. WhatsApp Business API: 2-3 weeks."

### Reality
- **DLT registration via Jio/Vi/Airtel:** 1-2 weeks (PE registration), then template approval per template (1-3 days each)
- **WhatsApp Business API approval via Gupshup:** 3-6 weeks for new businesses
  - Requires Facebook Business Manager verified
  - Requires legal business documents
  - Template approval is separate, per template, 1-2 days each
  - Phone number approval is separate

### Real-World Impact
- Plan assumes WhatsApp ready by Month 10. Realistic: Month 11-12 at earliest, possibly later.
- If MSG91 templates rejected (common reason: too sales-y, missing opt-out), redo cycle

### What to Do
- Apply for everything **Day 1, in parallel**
- WhatsApp: start Facebook Business Manager verification on Day 1
- Have SMS templates pre-drafted to match DLT format requirements
- For WhatsApp BSP: budget month-long approval cycle
- Have SMS-only fallback if WhatsApp delays

---

## 🔴 Cash-Handling May Have Regulatory Implications

### What I Said
"Worker collects cash. Cash creates debt to platform. T+1 settlement."

### Hidden Risk
This model resembles deposit-taking or money-handling in ways that **could trigger RBI scrutiny**:
- Are you holding worker funds? (Their unsettled earnings)
- Are you collecting on behalf of merchants? (Yes, when cash collected by worker is owed to merchant)
- Does this require Payment Aggregator license?
- GST implications on the cash flow chain

### Real-World Risk
- If treated as PA without license: regulatory action, fines
- If misclassified for GST: tax penalties
- If worker absconds with cash: bad debt, potentially significant

### What to Do
- **Mandatory:** Consult a CA + payment-aggregation-aware lawyer before Month 6 (₹25-50k for proper review)
- Structure cash collection as: customer pays worker directly, worker has independent contract with platform to remit fees — this changes legal characterization
- Add Terms of Service that make this clear
- Consider eliminating cash entirely in V2 if regulatory risk too high
- File startup with DPIIT (Department for Promotion of Industry and Internal Trade) for clarity

---

## 🟠 GST Complexity Underplayed

### What I Said
Mentioned GST briefly. Said B2B customers may want invoices.

### Hidden Complexity
- Service component (labor) → 18% GST
- Goods component (parts) → variable rate (5-28% depending on item)
- Platform commission → 18% GST
- **Composite supply vs mixed supply** — affects how GST is calculated on the whole bill
- **GST registration threshold:** ₹20 lakh turnover annually (₹10L in some states)
- **E-invoicing required** at ₹5 crore+ turnover (B2B)
- **GSTR-1, GSTR-3B filings monthly** — accounting overhead
- **TDS deduction on worker payouts** if >₹50k/year per worker (Section 194C)
- **GST on cash transactions:** even cash flows must be GST-reported

### What to Do
- Hire a CA from Day 1 (₹3-5k/month retainer in Vadodara)
- Get GST registration before first transaction
- Set up Zoho Books or TallyPrime for accounting from start
- Don't try to do GST yourself; the rules change quarterly
- For B2B customers (offices/shops), e-invoicing-ready from start

---

## 🔴 Single VPS = Single Point of Failure

### What I Said
"Stage 1: Single Hetzner VPS via Docker Compose. Stage 2: scale out."

### Reality for a Money-Handling Platform
- VPS dies = entire platform down
- Hetzner outages (rare but happen) = you're down
- Disk failure = data loss if backup is older than incident
- A 4-hour outage during evening peak = lost revenue + lost trust + workers idle

### What I Underplayed
- For a platform handling payments, downtime has real cost beyond inconvenience
- Disaster recovery from backup = 1-4 hours minimum
- Postgres corruption with bad backup = potential business-ending event

### What to Do
- **Hot standby Postgres from Month 3** (Hetzner allows VPS-to-VPS replication cheaply)
- Daily backups verified weekly (don't just take backups; restore them)
- Status page from Day 1 (uptime.kuma free, hosted on a *different* provider)
- Document recovery runbook; practice the drill quarterly
- Get domain registrar with auto-renewal (don't lose domain to lapsed payment)
- Accept that V1 will have some downtime; communicate transparently

---

## ⚪ Customer Support Channel Not Specified

### What I Didn't Address
How does a customer reach you when things break?
- Phone? (Who answers? You? At 11 PM?)
- WhatsApp? (Same issue)
- Email? (Slow, but scalable)
- In-app chat? (Need to build it)

### Reality
- Customers will call/message at all hours
- Workers will too (especially when they can't get paid)
- Merchants too (settlement queries)
- Support is the #1 operational job at launch

### What to Do
- **Decide in Month 0:** What's your support strategy?
- Options:
  - WhatsApp Business number with auto-responder + business hours
  - Phone only during business hours, voicemail otherwise
  - In-app chat with you as the responder
  - Hire a part-time support person from Month 11 (~₹15k/month in Vadodara)
- Build expectation-setting into customer experience: "We respond within X hours"
- Track support volume from Day 1; it predicts when you need help

---

## 🟠 Worker App Availability States Underspecified

### What I Said
Worker is "online" or "offline."

### Reality
A worker's day looks like:
- Online (available for jobs)
- En route to current job
- At customer location (diagnosing)
- Buying parts
- Repairing
- Lunch / personal break
- Stuck in traffic
- Bike broke down
- End of day

### What I Missed
- "Online but not currently available" state (e.g., on lunch, on personal errand)
- Auto-offline triggers (no GPS ping for 5 min)
- Mandatory break after X hours of consecutive online time
- End-of-day flow (last job declination criteria)

### What to Do
Add explicit states to worker app:
- Available
- On Job (with current phase)
- On Break (worker-triggered, max 60 min)
- Stuck (worker-triggered, e.g., bike issue, requires support response)
- Offline (end of shift)

Build break detection (don't dispatch to worker on lunch).

---

## 🟠 Returns Logistics Are A Real Operational Hole

### What I Said
"Worker returns parts via QR scan at merchant within return window."

### What I Didn't Address
- **Who pays for transportation back to merchant?** Worker's bike fuel?
- **Time cost:** Worker drives 5 km to return a ₹50 part. Worth it?
- **Worker incentive to return:** Currently zero, since debt only clears when scanned
- **Merchant inconvenience:** Walk-in returns disrupt their day
- **Damaged returns:** Who's at fault when merchant says damaged?

### What to Do
- Build incentive: worker gets bonus per successful return scan (₹10-20)
- Or: returns happen weekly batched, not per-job
- Or: merchant comes to worker (for high-value returns)
- Test this flow with first 50 jobs; iterate based on reality
- Be prepared to redesign by Month 12

---

## 🟠 Photo Upload Reliability on Tier-2 Network

### What I Said
"3 mandatory photos at checkpoints. Upload to R2."

### Reality
- Padra has spotty 4G/3G in places
- Vadodara has good 4G but not perfect
- 3 photos × ~1 MB compressed = 3 MB upload per job
- On 3G: ~30-60 seconds per photo
- Network failures mid-upload = retry needed
- Worker's data costs accumulate

### What to Do
- Aggressive client-side compression (target <500KB per photo)
- Upload queue with retry logic + offline persistence
- Show worker upload progress + retry buttons
- Allow job state to advance with "upload pending" indicator
- Don't block worker from moving to next phase due to upload
- Eventually upload from device-side database when connection returns

---

## 🟠 Old Android Device Performance

### What I Said
"Flutter performance is near-native."

### Reality
- Many tier-2 customers have 3-5 year old phones with 2-3 GB RAM
- Many tier-2 workers have entry-level phones (₹6-10k range)
- Flutter apps with maps + WebSocket + background services = heavy
- App may crash, freeze, or feel sluggish on these devices
- Customers churn fast if app feels broken

### What to Do
- Buy 2-3 cheap Android phones for testing: 
  - Redmi 9A (₹6,500)
  - Realme C30 (₹7,500)
  - Samsung Galaxy M04 (₹8,000)
- Test app on these from Month 3 onwards (not just at launch)
- Set strict app size budget (<25 MB ideally)
- Lazy-load maps only when needed
- Disable animations on low-end devices (detect via RAM)
- Profile memory usage regularly

---

## 🔴 Designer Budget Underestimated

### What I Said
"Hire designer for ₹15-25k for V1."

### Reality for Vadodara/Ahmedabad
- Junior freelance designer: ₹15-25k, but quality varies wildly
- Mid-level designer with mobile app portfolio: ₹40-80k for V1 design system + 2 apps
- Good designer who delivers Figma + design tokens + dark mode: ₹50-1L

### What to Do
- Budget ₹40-60k for designer (not ₹15-25k)
- Get portfolio review before hiring; look for mobile app work specifically
- Define deliverables clearly: 
  - Logo + brand guidelines
  - Design system (colors, typography, spacing, components)
  - Figma file with all customer + worker screens
  - Design tokens exportable to Flutter
  - 2-3 rounds of revisions included
- Consider Topmate.io, Dribbble (Indian designers), or Behance for finding talent

---

## 🟠 Translation Quality (Hindi/Gujarati)

### What I Said
"Support Hindi + Gujarati + English. AI can help generate translations."

### Reality
- AI-translated Hindi/Gujarati often misses register (formal vs colloquial)
- Technical terms ("OTP", "wallet", "settlement") don't translate cleanly
- Direct translations sound robotic to native speakers
- Vadodara Gujarati ≠ Surat Gujarati ≠ Mumbai Gujarati (subtle but matters)

### What to Do
- Get all UI strings reviewed by native Gujarati speaker (Vadodara local)
- Don't try to translate technical terms — use English in transliteration
  - ✅ "OTP daakhal karo" (enter OTP)
  - ❌ "Ekvar-na password daakhal karo" (One-time password — sounds weird)
- Budget ₹10-15k for professional review
- Allow English-only mode for first launch if rushing

---

## 🟠 Skill Verification Without an Ops Team

### What I Said
"Skill verification: in-person test by ops team or partner ITI."

### Reality
- You have no ops team — you ARE the ops team
- ITI partnerships take months to set up
- For first 50 workers, who verifies?

### What to Do
- **Founder personally verifies first 50 workers** (you, in person)
- Use recorded video skill verification as supplement
- Visit workers at their existing job sites or have them demo at your home
- This is necessary slow work, not a bug — it builds judgment
- Document each verification (notes, photos) for audit trail
- Partner with one local ITI by Month 9 for scaling

---

## ⚪ Beta Launch Real-Money Transition

### What I Didn't Address
The first ₹100 of real money flowing through is genuinely terrifying. What if:
- Payment succeeds at Razorpay but fails to record in your DB?
- Webhook arrives twice (duplicate processing)?
- Worker payout calculation is off by ₹1 (audit nightmare)?
- Customer disputes via Razorpay (chargeback) before your dispute flow catches it?

### What to Do
- **Test with your own money first:** Run 10 complete jobs with ₹1 amounts
- **Then friends/family:** 20 jobs with small amounts
- **Then 5-10 real customers** in Vadodara at full pricing
- Monitor every transaction manually for first 100 jobs
- Build reconciliation script: Razorpay payout vs your DB should match daily
- Set up alerts for any mismatch >₹0 (yes, even 1 paisa)
- Have refund-friendly stance during first month — refund first, investigate later

---

## 🟡 Vendor Lock-In Mitigation Wishful Thinking

### What I Said
"All third-party calls go through wrappers; we can switch vendors easily."

### Reality
In practice, switching vendors mid-flight is painful:
- Each vendor has different API shapes, error codes, retry semantics
- Historical data is in vendor's format
- Customer/worker has saved Razorpay-saved card → switching means re-collection
- Switching SMS provider mid-DLT-registration = restart approval

### What to Do
- Wrappers help, but don't believe vendor switches are easy
- Choose primary vendors carefully (they're somewhat sticky)
- Switch only when failure is severe and sustained
- Plan vendor migration windows during low-traffic periods
- Don't waste effort building "switchable" architecture for vendors you'll likely never switch

---

## 🔴 Worker Disintermediation Risk Higher Than I Painted

### What I Said
"Masked calls + warranty + bonuses prevent disintermediation."

### Reality
- Indian customers are price-sensitive; 20% off direct vs platform is huge
- Workers have decades of word-of-mouth networks already
- Trust transfers fast once a customer-worker relationship is established
- Warranty and bonuses only matter for first 1-2 jobs; after that, trust is direct
- Platform commission is a forever-tax customers will try to avoid

### What to Do
- **Accept ~30-40% disintermediation will happen** at some level
- Focus on metrics: % of customers who book again through platform within 6 months
- Build customer loyalty mechanisms beyond just warranty:
  - AMC subscriptions (sticky)
  - Loyalty wallet credits
  - "Trusted FixCare member" status with perks
  - Quarterly reviews of repeat-customer health
- Make repeat-booking radically easier than direct calls
- This is a long-term war, not a one-time fight

---

## ⚪ Founder's Personal Risk Management

### What I Didn't Address
- What if you get sick for 2 weeks?
- What if family emergency?
- What if you lose motivation around Month 7?
- Solo means no cover, no rotation, no support

### What to Do
- **Build in 1 week of intentional buffer per quarter**
- Document everything (good docs = lower bus factor)
- Set up auto-renewals for ALL services (domain, hosting, plugins, SaaS) — don't lose them to a forgotten renewal
- Tell someone (spouse, parent, friend) where credentials are stored (1Password / Bitwarden) for emergencies
- Plan to talk to one other founder per week — outside perspective helps
- Quarterly: write "would future-me thank past-me for this?" review

---

## ⚪ When V1 Launches, Are You Actually Ready For Customers?

### What I Said
"Soft launch in Vadodara with 20-50 customers."

### Reality
- 20 customers × 2 jobs/month = 40 jobs/month
- 40 jobs × 30 min ops time each (issues, support, manual review) = 20 hours/month of ops
- You're already coding 6 hours/day
- Now also: support, marketing, talking to workers, talking to merchants, fixing bugs

### What to Do
- Accept that **launch slows development to a crawl** for 1-2 months
- Plan: Month 11-12 is launch + bug fix + ops, NOT new features
- Month 13+: hire first part-time helper (₹15-20k/month) for support
- Or: limit launch to truly small number (10 customers) for first 6 weeks
- Don't believe you can launch + continue Month-12-pace simultaneously

---

## Summary: What to Add to the Plan

Based on these doubts, additions for safety:

1. **Month 0:** Apply for ALL vendor approvals in parallel (Razorpay, MSG91 DLT, WhatsApp BSP, KYC vendors)
2. **Month 0:** Hire CA + brief lawyer ₹25-50k
3. **Month 1:** Add background location complexity testing to roadmap
4. **Month 2:** Set up status page, basic monitoring on separate provider
5. **Month 3:** Hot standby Postgres + backup verification process
6. **Month 4:** Razorpay Route approval likely complete; plan for manual settlement until then
7. **Month 5:** Buy 2-3 budget Android phones for low-end testing
8. **Month 6:** Designer hired (budget ₹40-60k, not 15-25k)
9. **Month 7:** Translation review by native Gujarati speaker
10. **Month 9:** Customer support strategy decided + tools set up
11. **Month 10:** Test runs with real money (your own + family)
12. **Month 11:** First 5 real customers, manual oversight on every transaction
13. **Month 12:** Soft launch with expectation-setting (10-20 customers max)

---

## Final Honest Take

The plan I gave is **a strong foundation**, but it's optimistic. Reality has more friction:
- Vendor approvals slower than expected
- Background services on Android harder than expected
- Cash regulatory complexity heavier than expected
- Operational support workload higher than expected
- Translation/UX polish takes longer than expected

**Add 3-6 months buffer** for unknown unknowns. Adjust scope down rather than timeline up.

Most solo builds that succeed: shipped less but shipped working. Most that fail: tried to ship everything and shipped nothing.

**Pick courage over completeness.**
