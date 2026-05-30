# Tech Stack Decisions

Final picks with reasoning. **Self-hosted, solo-dev friendly, scale-ready.**

---

## Summary Table

| Layer | Pick | Why |
|---|---|---|
| Mobile | Flutter 3.x | Single codebase, great AI codegen |
| OS for V1 | Android only | 95%+ of target market |
| Backend Runtime | Node.js 22 LTS | Best real-time, abundant AI examples |
| Backend Framework | Fastify 5.x | Mid-complexity sweet spot |
| Language | TypeScript (strict) | Type safety, AI-friendly |
| Database | PostgreSQL 16 + PostGIS | Standard, portable, geospatial-ready |
| ORM | Prisma 6.x | Type-safe, great DX, migration-friendly |
| Cache & Queue | Redis 7 + BullMQ | Industry standard |
| Validation | Zod | Works with Prisma + Fastify cleanly |
| Auth | Custom OTP + JWT (argon2id) | Full control, security |
| Real-time | Fastify WebSocket | Built-in, fast |
| File Storage | Cloudflare R2 | No egress fees, S3-compatible |
| Containers | Docker + Compose | Dev = prod parity |
| Reverse Proxy | Caddy | Auto HTTPS, simpler than Nginx |
| Hosting | Hetzner Cloud | 3-5x cheaper than AWS at our scale |
| Admin Dashboard | Next.js + shadcn/ui + Tailwind | Standard, fast |
| Payments | Razorpay | Only viable India option |
| KYC | Setu + Karza | Best India coverage |
| Push | OneSignal | Easier than raw FCM |
| SMS | MSG91 | Cheapest for India |
| WhatsApp | Gupshup | BSP, scales |
| Maps | Google Maps Platform | $200/month free credit |
| Monitoring | Sentry + Uptime Kuma | Free tiers |
| IDE | Cursor + Claude | Best vibe coding setup |

---

## Why NOT These (Considered & Rejected)

### Backend Alternatives
- **Express:** Too bare, plugin chaos, lower performance
- **NestJS:** Too opinionated, heavy decorators, overkill solo
- **FastAPI (Python):** Great, but Node has better real-time + more Razorpay examples
- **Go:** Best at scale, but hiring hard in Vadodara

### Database Alternatives
- **MongoDB:** Wrong fit (we need relational + transactions)
- **MySQL:** Postgres is just better, especially with PostGIS
- **Supabase:** Vendor lock-in concern, owner wants control

### Mobile Alternatives
- **React Native:** Performance issues on mid-range Android, bridge overhead
- **Native (Kotlin/Swift):** 6 codebases instead of 2 — suicidal solo

### Hosting Alternatives
- **AWS Mumbai:** 3-5x more expensive, complex pricing
- **GCP/Azure:** Same problem as AWS
- **DigitalOcean Bangalore:** Good fallback, but Hetzner cheaper

### Storage Alternatives
- **AWS S3:** Egress fees kill mobile-heavy app
- **MinIO self-hosted:** Adds ops burden V1 doesn't need

---

## The Three Hardest Decisions

### 1. Node vs Python
**Picked:** Node.js + Fastify

**Trade-off:**
- Lose: Better ML ecosystem for fraud (Python wins)
- Gain: Better real-time, more Indian fintech examples, single mental model with TypeScript

**When to reconsider:** When fraud ML becomes critical (V2+), can add Python microservice for that one purpose.

---

### 2. Self-hosted vs Supabase
**Picked:** Self-hosted

**Trade-off:**
- Lose: ~2 months of dev time (building auth, real-time, etc. yourself)
- Gain: Full control, deeper learning, no vendor lock-in, lower long-term cost

**When to reconsider:** If burnout looms in month 3-4, falling back to Supabase isn't shame — it's survival.

---

### 3. Modular Monolith vs Microservices
**Picked:** Modular monolith (V1 + V2)

**Trade-off:**
- Lose: Independent scaling of components
- Gain: One codebase, one deployment, faster iteration, simpler debugging

**When to reconsider:** When >50K daily active users OR when a specific module needs different scaling (e.g., notification service handling 1M/day).

---

## Stack Constraints

### Things This Stack Does Well
- CRUD with strong type safety
- Real-time updates (technician location, job status)
- Background jobs (notifications, settlements, fraud rules)
- Geospatial queries (PostGIS for nearest technician/merchant)
- File uploads with thumbnailing
- Webhooks (Razorpay, KYC vendors)
- Auto-generated API docs (Fastify + OpenAPI)

### Things This Stack Will Struggle With
- Heavy ML/AI workloads (use Python microservice if needed)
- Massive concurrent users (need horizontal scaling work at 10K+ concurrent)
- Complex video processing (offload to specialized service)
- Real-time collaborative editing (not our use case anyway)

---

## Upgrade Paths (Future)

### Database Scaling
- Stage 1: Single Postgres on Hetzner
- Stage 2: Managed Postgres (DigitalOcean Bangalore) with read replicas
- Stage 3: Sharded by city/region
- Stage 4: Separate OLTP/OLAP (add Clickhouse for analytics)

### Service Splits
When monolith strains (10K+ DAU):
- Notification service (highest volume, easy to split)
- Payment/ledger service (compliance isolation)
- Fraud detection (Python microservice)

### Mobile Expansion
- V1: Flutter Android only
- V2: Add iOS (same codebase)
- V3: Add merchant app (defer until WhatsApp insufficient)
- V4: Web customer app (for desktop bookers)

---

## Vendor Risk Mitigation

For each third-party service, document the migration path:

| Service | If they fail, we use |
|---|---|
| Razorpay | Paytm Payment Gateway, Cashfree |
| MSG91 | Twilio, Gupshup SMS |
| Setu (KYC) | Karza, IDfy, Signzy |
| Karza (KYC) | Setu, IDfy, Signzy |
| Google Maps | Mapbox, OpenStreetMap |
| OneSignal | Direct FCM, AWS SNS |
| Cloudflare R2 | AWS S3, MinIO |
| Hetzner | DigitalOcean, AWS |

**None of these is a single point of failure.** All have viable alternatives.

---

## The "Don't Add" List

Resist adding these to V1, even if tempting:

- ❌ Kubernetes (Docker Compose is enough)
- ❌ GraphQL (REST is simpler, AI-friendlier)
- ❌ Event sourcing (overkill for V1)
- ❌ CQRS (overkill)
- ❌ Service mesh (no need)
- ❌ Multiple databases (one Postgres rules all)
- ❌ Message brokers like Kafka (BullMQ is enough)
- ❌ Custom analytics infra (use PostHog free tier)
- ❌ AI chatbots (humans handle support V1)

If you find yourself wanting any of these, ask: "Will this be in production within 90 days?" If no, defer.
