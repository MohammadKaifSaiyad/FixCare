# Next Steps

Concrete actions in priority order. Start at the top.

---

## This Week (Foundation)

### Verify the Name
- [ ] Domain: check `fixcare.in`, `.com`, `.app` (GoDaddy/Namecheap)
- [ ] Trademark: search ipindia.gov.in (Class 37 + Class 42)
- [ ] Play Store: confirm no existing FixCare app in India
- [ ] If taken → fall back to FixCare.app / GetFixCare / SahiHaath

### Apply for Everything With Long Lead Times (DAY 1 — parallel)
These have multi-week approval cycles. Starting late blocks launch.
- [ ] Razorpay account KYC (3-5 days)
- [ ] **Razorpay Route / marketplace approval** (2-4 weeks — start now)
- [ ] MSG91 account + DLT registration (1-2 weeks)
- [ ] WhatsApp Business via Gupshup + Facebook Business Manager verification (3-6 weeks)
- [ ] Setu KYC sandbox + production access request
- [ ] Karza KYC sandbox + production access request

### Set Up Accounts
- [ ] GitHub org: `fixcare`
- [ ] Hetzner Cloud account + first VPS
- [ ] Cloudflare account (DNS + R2)
- [ ] Google Cloud project (Maps API) + billing alerts
- [ ] Firebase project (for OneSignal/FCM)
- [ ] Sentry + PostHog projects

### Engage Professionals
- [ ] Brief a CA (₹3-5k/month retainer) — GST registration + accounting setup
- [ ] One consultation with a payments-aware lawyer (₹25-50k) — cash-handling model + PA license question

### Tooling
- [ ] Install Claude Code + Superpowers plugin (see vibe-coding-workflow.md)
- [ ] Install code-review, typescript-lsp, postgres MCP, github MCP
- [ ] Copy this `docs/` folder into the repo; put `CLAUDE.md` at repo root
- [ ] Create empty `CHANGELOG.md`

---

## Weeks 2-4 (Before Real Coding)

- [ ] Learn Flutter basics (you have no mobile experience) — Code With Andrea, official Flutter docs. 30 min/day.
- [ ] Draft the Prisma schema with Claude Code (use `brainstorming` first)
- [ ] Stand up Docker Compose locally (Postgres + PostGIS + Redis)
- [ ] Get a "Hello World" Fastify API running locally, then deployed to Hetzner
- [ ] Decide customer support channel (WhatsApp business number? business hours?)
- [ ] Buy 2-3 budget Android test phones (Redmi 9A class)

---

## First Real Build Targets (Month 1-2)

In order:
1. [ ] Database schema migrated
2. [ ] Auth: phone OTP → JWT → refresh
3. [ ] User/Worker/Customer/Merchant CRUD
4. [ ] Service categories + labor catalog + parts catalog
5. [ ] Deployed to `api.fixcare.in` with HTTPS

Then follow `05-development/build-sequence.md`.

---

## Decision Still Open (You Need to Settle)

These aren't decided yet — make the call before you hit them:

- [ ] **Customer support channel** — WhatsApp / phone / in-app? (needed by Month 9)
- [ ] **Designer hire** — budget ₹40-60k, find via Dribbble/Behance/Topmate (needed by Month 5)
- [ ] **Cash model legal structure** — direct worker-collects vs platform-collects (legal review)
- [ ] **First-50-worker verification** — you personally? (yes, plan for it)
- [ ] **Co-founder** — actively look while building solo; transition if you find the right person

---

## What NOT to Do Yet

- ❌ Don't build the merchant app (WhatsApp suffices for V1)
- ❌ Don't add iOS (Android-only V1)
- ❌ Don't build merchant bidding (preferred-merchant routing V1)
- ❌ Don't add Kubernetes / microservices / GraphQL
- ❌ Don't promise external launch dates before Month 8
- ❌ Don't try to launch AND keep full dev pace simultaneously

---

## Reminders

- 6-hour daily coding cap. Sundays off.
- Ship less but working. Courage over completeness.
- Update `CLAUDE.md` "Current Phase" + `CHANGELOG.md` every session.
- Re-read `assumptions-and-doubts.md` whenever a vendor/legal/Android-platform decision comes up.
