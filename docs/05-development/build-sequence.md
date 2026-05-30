# Build Sequence

Month-by-month roadmap for solo developer with vibe coding.

---

## Reality Check Before You Start

- **Solo + vibe coding = 10-14 months to V1**
- Skip iOS in V1 (saves ~40% time)
- Skip dedicated merchant app in V1 (WhatsApp bot suffices)
- Build backend before mobile
- Build admin dashboard before customer app
- Build customer app before worker app

---

## Month 0: Foundation Week (Days 1-7)

### Before Writing Any Code
- [ ] Verify FixCare domain + trademark
- [ ] Register `fixcare.in` (₹800/year)
- [ ] GitHub org created: `fixcare`
- [ ] Hetzner account + first VPS provisioned
- [ ] Cloudflare account + DNS configured
- [ ] Razorpay account application started (3-5 day KYC)
- [ ] MSG91 account + DLT registration started (5-7 days)
- [ ] Setu KYC sandbox access requested
- [ ] Karza KYC sandbox access requested
- [ ] Google Cloud project for Maps API
- [ ] Firebase project for OneSignal
- [ ] Cursor IDE installed + Claude configured
- [ ] PROJECT.md drafted (paste from these docs)

### Local Setup
- [ ] Node 22 LTS installed
- [ ] pnpm installed
- [ ] Docker Desktop installed
- [ ] Flutter SDK installed
- [ ] PostgreSQL client installed (TablePlus or DBeaver)
- [ ] VS Code or Cursor as IDE

### Deliverable
- Working local environment
- `Hello World` Fastify API serving on localhost
- All external services have accounts in pipeline

---

## Months 1-2: Backend Foundation

### Goals
- Schema designed and migrated
- Auth working
- Core CRUD operations for all entities
- Docker Compose for local dev
- Deployment to Hetzner VPS

### Tasks

**Week 1-2: Database & Project Structure**
- [ ] Prisma schema for all entities (users, customers, workers, merchants, services, bookings, etc.)
- [ ] Initial migration run
- [ ] Project structure setup (modules folder)
- [ ] Seed scripts for test data
- [ ] Postgres + Redis in Docker Compose

**Week 3-4: Auth Module**
- [ ] Phone OTP send/verify (with MSG91 test integration)
- [ ] JWT access + refresh tokens
- [ ] Refresh token rotation
- [ ] Auth middleware/plugin
- [ ] Test all flows with Postman/Bruno

**Week 5-6: User Management**
- [ ] Customer CRUD
- [ ] Worker CRUD (basic, KYC later)
- [ ] Merchant CRUD
- [ ] Admin CRUD
- [ ] Role-based access control

**Week 7-8: Service Catalog + Deployment**
- [ ] Service categories CRUD (dynamic)
- [ ] Labor catalog with geofenced pricing
- [ ] Parts master catalog
- [ ] Caddy + Docker Compose deployment to Hetzner
- [ ] HTTPS working with Let's Encrypt

### Deliverable
- Backend deployed at `api.fixcare.in`
- Auth + core CRUD functional
- Documented in Postman/Bruno collection

---

## Month 3: Core Business Logic

### Goals
- Booking lifecycle works end-to-end
- Worker dispatch algorithm functional
- Payment integration with Razorpay test mode

### Tasks

**Week 9-10: Booking State Machine**
- [ ] Booking entity + state transitions
- [ ] State machine guards (can't skip states)
- [ ] Audit log for every transition
- [ ] Tests for state machine

**Week 11-12: Dispatch Algorithm**
- [ ] PostGIS setup for location queries
- [ ] Worker availability tracking (online/offline)
- [ ] Matching algorithm: rating × proximity × load × trust
- [ ] Assignment endpoint
- [ ] Reject/accept flow

**Week 13: Payment Integration**
- [ ] Razorpay test mode setup
- [ ] Payment intent creation
- [ ] UPI Intent flow
- [ ] Webhook handler
- [ ] Refund endpoint

### Deliverable
- Create booking → dispatch → accept → complete flow works via API
- Razorpay test payments succeed
- Comprehensive integration test suite

---

## Month 4: Admin Dashboard

### Goals
- Manage everything from web before mobile apps exist
- Manual job creation, worker assignment, dispute resolution

### Tasks

**Week 14-15: Next.js Setup**
- [ ] Next.js 14 project with TypeScript
- [ ] shadcn/ui + Tailwind setup
- [ ] Auth with backend
- [ ] Layout, sidebar, navigation
- [ ] Deployed at `admin.fixcare.in`

**Week 16: Core Pages**
- [ ] Users list (filter by role)
- [ ] Worker management (verify KYC manually)
- [ ] Merchant management
- [ ] Booking list + detail view

**Week 17: Operations**
- [ ] Manual booking creation
- [ ] Dispute resolution UI
- [ ] Catalog management
- [ ] Service category management
- [ ] Financial reports (basic)

### Deliverable
- Admin can run entire platform from dashboard
- Useful for ops before mobile apps exist
- Test workers/customers manageable

---

## Months 5-6: Customer App

### Goals
- Customer can book → track → pay → rate from mobile
- Real-time updates during job
- Production-ready UX

### Tasks

**Week 18-19: Foundation**
- [ ] Flutter project setup
- [ ] Riverpod + go_router architecture
- [ ] API client with auth
- [ ] Splash + onboarding screens
- [ ] Phone OTP flow

**Week 20-21: Booking Flow**
- [ ] Service browsing
- [ ] Address picker with Google Maps
- [ ] Booking creation
- [ ] Visit fee display
- [ ] Confirmation screen

**Week 22-23: Job Tracking**
- [ ] WebSocket connection
- [ ] Worker location on map
- [ ] Worker arrival confirmation (QR scan + OTP)
- [ ] Diagnosis approval screen
- [ ] Live status updates

**Week 24-25: Payment + Rating**
- [ ] Final bill review
- [ ] Razorpay integration
- [ ] Cash payment confirmation
- [ ] Completion OTP entry
- [ ] Rating submission
- [ ] History screens

**Week 26: Polish**
- [ ] Loading states
- [ ] Error handling
- [ ] Empty states
- [ ] Push notifications via OneSignal
- [ ] Sentry integration
- [ ] Beta build distributed

### Deliverable
- Customer app functional end-to-end
- 5-10 internal testers using it daily
- Beta deployed via Firebase App Distribution

---

## Months 7-9: Worker App

### Goals
- Worker can onboard, accept jobs, complete with photo evidence
- KYC, cash tracking, wallet all working

### Tasks

**Week 27-28: Onboarding**
- [ ] Phone OTP
- [ ] Personal details
- [ ] Skill selection
- [ ] DigiLocker integration (Setu)
- [ ] PAN verification (Karza)
- [ ] Skill video upload
- [ ] Bank account capture
- [ ] Security deposit payment

**Week 29-30: Home + Online Mode**
- [ ] Go online/offline toggle
- [ ] Background location service
- [ ] Foreground notification for Android
- [ ] Earnings dashboard
- [ ] Cash debt indicator

**Week 31-32: Job Flow**
- [ ] Incoming job alert
- [ ] Accept/reject
- [ ] Navigation to customer
- [ ] Arrived confirmation
- [ ] QR badge display
- [ ] Diagnosis form
- [ ] Parts cart builder

**Week 33-34: Repair + Completion**
- [ ] Camera integration (camera only, no gallery)
- [ ] Photo upload to R2
- [ ] 3 photo checkpoints
- [ ] Bill review
- [ ] Customer OTP entry
- [ ] Payment receiving

**Week 35: Wallet**
- [ ] Earnings history
- [ ] Withdrawals
- [ ] Cash debt details
- [ ] Trust score display

**Week 36: Polish & Beta**
- [ ] Performance optimization (low-end Android testing)
- [ ] Offline mode handling
- [ ] Edge cases
- [ ] Beta distributed to 5 real workers

### Deliverable
- Worker app functional end-to-end
- Real workers testing in Vadodara
- Iterating based on feedback

---

## Month 10: Merchant Flow (Web + WhatsApp)

### Goals
- Merchants can onboard, manage catalog, confirm stock — WITHOUT a dedicated app

### Tasks

**Week 37-38: Web Onboarding**
- [ ] Public landing page for merchants
- [ ] Onboarding form (GST, license, catalog)
- [ ] Catalog management in admin dashboard
- [ ] Merchant login + simple dashboard

**Week 39-40: WhatsApp Integration**
- [ ] Gupshup BSP setup
- [ ] Stock confirmation message template
- [ ] Button-based responses (Yes/Partial/No)
- [ ] Webhook handler for responses
- [ ] Notification on settlement
- [ ] QR scan for returns (via worker app)

### Deliverable
- 5-10 merchants onboarded in Vadodara
- WhatsApp flow tested with real merchants
- Settlement working

---

## Months 11-12: Polish, Test, Launch

### Goals
- Soft launch in Vadodara with real customers
- Iterate based on real-world feedback
- Build operational muscle

### Tasks

**Week 41-42: Hardening**
- [ ] Fraud detection rules engine V1
- [ ] Trust scores recalculating nightly
- [ ] Dispute workflow polished
- [ ] Audit log comprehensive
- [ ] Backup tested (full restore drill)
- [ ] Security review (OWASP top 10)

**Week 43-44: Internal Testing**
- [ ] Test workers + test customers do 50 jobs
- [ ] Document every issue
- [ ] Fix critical bugs
- [ ] Performance test (load 100 concurrent users)

**Week 45-46: Beta Launch**
- [ ] 20-50 real customers in Vadodara
- [ ] 10-15 real workers
- [ ] 5-10 merchants
- [ ] Daily monitoring
- [ ] Daily customer calls (first 2 weeks)

**Week 47-48: Iterate & Soft Launch**
- [ ] Fix based on real feedback
- [ ] Marketing push starts (organic)
- [ ] PR/local media outreach
- [ ] Official launch

### Deliverable
- 100+ customers in Vadodara
- 30+ active workers
- Real revenue flowing
- Lessons documented for V2 planning

---

## What Comes After (V1.5 to V2)

Not in this roadmap, but worth knowing:

### V1.5 (Months 13-15)
- AMC subscription plans
- iOS apps
- Dedicated merchant app
- Better fraud detection (ML-assisted)

### V2 (Months 16-20)
- Expand to Ahmedabad
- Add plumbing service category
- Worker insurance partnership
- Loyalty program

### V3 (Year 2+)
- Multi-city (rest of Gujarat)
- B2B offerings (offices, societies)
- Old parts scrap marketplace
- Hire first employees

---

## Critical Milestones (Don't Miss)

| Milestone | When | Why |
|---|---|---|
| Razorpay live keys | Month 1 | KYC takes 3-5 days, start early |
| MSG91 DLT approved | Month 1 | 5-7 days for approval |
| Backend deployed to Hetzner | End of Month 2 | Real environment matters |
| First end-to-end test booking | Month 4 | Validates architecture |
| Designer hired for V1 | Month 5 | Mobile UX matters |
| First real worker onboarded | Month 9 | Real KYC test |
| First paying customer | Month 11-12 | Product-market fit signal |

---

## When You're Behind Schedule

### Realistic responses
- **2 weeks behind:** Ignore, normal variance
- **1 month behind:** Re-prioritize, cut non-essential
- **2 months behind:** Major scope cut needed
- **3+ months behind:** Hire help OR major rethink

### What to Cut When Behind
1. iOS support (was already out — keep it out)
2. WhatsApp merchant flow (use admin dashboard only)
3. Multiple service categories (launch with 2: AC + electrical)
4. Polish (ship ugly, fix later)
5. AMC plans (V1.5)
6. Advanced fraud rules (ship 5 instead of 13)

### What NOT to Cut
- Photo evidence checkpoints (security-critical)
- OTP handshakes (security-critical)
- Payment integration (no business without it)
- Worker KYC (legal requirement)
- Backup/disaster recovery (existential)

---

## Weekly Rhythm

Sustainable solo dev pattern:

**Mon-Fri:** Building (6 hours focused)
**Sat morning:** Review week, plan next week
**Sat afternoon:** Off
**Sun:** Off entirely

**Don't break this rhythm.** Burnout kills projects, not slow weeks.

---

## Tracking Progress

### Tools
- GitHub Projects board (free)
- Notion for docs (free)
- Calendar blocks for focused work
- Weekly retrospective in `weekly-notes/YYYY-MM-DD.md`

### Metrics to Track Weekly
- Hours worked
- Tasks completed
- Tasks added (scope growth signal)
- Tech debt accumulated
- Bugs fixed
- Mood/energy 1-10

If mood/energy drops below 5 for 2+ weeks, take a real break.
