# System Architecture

Modular monolith. Single deployable. Scales to V2 without rewrite.

---

## High-Level View

```
┌──────────────────────────────────────────────────────────┐
│                     CLIENT LAYER                          │
│                                                            │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│   │  FixCare     │  │  FixCare     │  │   Admin      │  │
│   │  Customer    │  │  Pro         │  │   Dashboard  │  │
│   │  (Android)   │  │  (Android)   │  │  (Next.js)   │  │
│   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│          │                  │                  │          │
└──────────┼──────────────────┼──────────────────┼──────────┘
           │                  │                  │
           │                  │                  │
           ▼                  ▼                  ▼
┌──────────────────────────────────────────────────────────┐
│              EDGE: Cloudflare CDN + DDoS                  │
└──────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│              REVERSE PROXY: Caddy (HTTPS)                 │
└──────────────────────────────────────────────────────────┘
                │           │           │
                ▼           ▼           ▼
┌─────────────────────────────────────────────────────────┐
│              APPLICATION LAYER (Hetzner VPS)              │
│                                                            │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Fastify   │  │  Fastify     │  │  BullMQ         │  │
│  │  API       │  │  WebSocket   │  │  Technicians        │  │
│  │  :3000     │  │  :3001       │  │  (background)   │  │
│  └─────┬──────┘  └──────┬───────┘  └────────┬────────┘  │
│        │                 │                    │          │
└────────┼─────────────────┼────────────────────┼──────────┘
         │                 │                    │
         ▼                 ▼                    ▼
┌──────────────────────────────────────────────────────────┐
│                  DATA LAYER                               │
│  ┌──────────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │ PostgreSQL   │  │  Redis   │  │  Cloudflare R2   │   │
│  │ + PostGIS    │  │  + Queue │  │  (Photos, KYC)   │   │
│  └──────────────┘  └──────────┘  └──────────────────┘   │
└──────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────┐
│              EXTERNAL SERVICES                            │
│                                                            │
│   Razorpay  │  MSG91  │  Setu  │  Karza  │  Google Maps  │
│   Gupshup   │  OneSignal  │  Sentry  │  PostHog          │
└──────────────────────────────────────────────────────────┘
```

---

## Architectural Principles

### 1. Modular Monolith
- ONE codebase
- ONE deployable
- INTERNAL boundaries between modules
- Each module owns its tables, services, schemas
- No cross-module DB queries (modules talk via services)

### 2. Separation of Concerns
- API server: handles HTTP requests
- WebSocket server: handles real-time
- Technicians: handle async/background work
- All share the same code, different entry points

### 3. Stateless API
- API servers store nothing in memory
- All state in Postgres or Redis
- Allows horizontal scaling later
- Failure of any server = no data loss

### 4. Event-Driven Background
- HTTP requests do minimum work, queue the rest
- E.g., booking endpoint creates record, queues notification dispatch
- Technicians handle slow/external calls async

### 5. Two-Sided Confirmations
- No financial state changes without dual confirmation
- Technician arrives → both technician (GPS) + customer (QR/OTP) confirm
- Job completes → both technician (photos) + customer (OTP) confirm
- Payment received → both customer (in-app) + technician (confirmation) confirm

---

## Request Flow Examples

### Example 1: Booking Creation
```
1. Customer app → POST /v1/bookings
2. Caddy routes to API server
3. API validates JWT
4. API validates request via Zod
5. API checks business rules (no pending payments, etc.)
6. API creates booking in Postgres (transaction)
7. API queues dispatch job in BullMQ
8. API returns 201 Created (<100ms)
9. [Async] Dispatch technician picks job
10. [Async] Technician matches technician via algorithm
11. [Async] Technician creates assignment in DB
12. [Async] Technician queues push notification
13. [Async] Notification technician sends push to technician via OneSignal
14. [Async] Notification technician pushes WebSocket event to customer app
15. Customer app updates UI in real-time
```

### Example 2: Job Completion
```
1. Customer enters OTP in app → POST /v1/jobs/{id}/complete
2. API validates JWT (technician's token)
3. API verifies OTP matches Redis
4. API validates all photos uploaded
5. API begins transaction:
   - Update job status → COMPLETED
   - Create ledger entries (technician earning, platform commission, merchant share)
   - Update technician cash debt (if cash)
   - Update technician trust score
6. API commits transaction
7. API queues:
   - Settlement job (T+1 to merchant)
   - Technician payout job (T+2)
   - Receipt SMS to customer
   - Push notification to all parties
8. API returns 200 OK
9. WebSocket broadcasts status update to all watchers
```

---

## Module Boundaries

### Auth Module
- OTP send/verify
- JWT generation/refresh
- Session management
- Password (admin only)

### Users Module
- Base user model
- Role assignment
- Profile management

### Customers Module
- Customer-specific fields
- Address book
- Booking history view

### Technicians Module
- Technician-specific fields
- KYC status
- Skill assignments
- Location tracking
- Trust scores
- Cash debt tracking

### Merchants Module
- Merchant-specific fields
- Catalog management
- Stock confirmations
- Settlement tracking

### Services Module
- Service category CRUD (admin)
- Service catalog
- Labor pricing (geofenced)

### Catalog Module
- Parts master catalog
- Per-merchant pricing
- Stock confidence scores
- Returns tracking

### Bookings Module
- Booking lifecycle state machine
- Dispatch coordination
- Status transitions

### Dispatch Module
- Technician matching algorithm
- Geofence calculations
- Priority scoring

### Payments Module
- Razorpay integration
- Payment intent creation
- Webhook processing
- Refund handling

### Wallet Module
- Technician earnings
- Cash debt ledger
- Settlement calculations
- Withdrawal processing

### Disputes Module
- Dispute creation
- Tier routing
- Evidence collection
- Resolution workflow

### Notifications Module
- Push notification dispatch
- SMS dispatch
- WhatsApp dispatch
- Email dispatch

### Fraud Module
- Rules engine
- Pattern detection
- Alert generation

### Admin Module
- Admin-only endpoints
- Reporting queries
- Manual interventions

---

## Inter-Module Communication

### Pattern: Service Calls
```ts
// Bad: direct DB query across modules
const technician = await prisma.technician.findUnique({ ... });

// Good: call the module's service
const technician = await techniciansService.getById(technicianId);
```

### Pattern: Events
For one-way notifications between modules:
```ts
// bookings.service.ts
async function completeBooking(id: string) {
  await prisma.booking.update({ ... });
  
  // Queue events
  await eventQueue.add('booking.completed', { bookingId: id });
}

// notifications.worker.ts
eventWorker.on('booking.completed', async (event) => {
  await sendCompletionNotifications(event.bookingId);
});
```

### Why This Matters
- Modules can be split into microservices later
- Tests can mock module boundaries
- Code stays organized as it grows

---

## Scaling Path (When Needed)

### Stage 1: Single VPS (V1)
All services on one Hetzner VPS via Docker Compose.

### Stage 2: Service Split
When CPU/memory pressure builds:
1. Move technicians to separate VPS (most likely first to need scaling)
2. Move WebSocket to separate VPS (if real-time traffic grows)
3. Keep API + DB on original VPS

### Stage 3: Database Separation
- Postgres → managed service (DO Bangalore)
- Redis → managed service or dedicated VPS

### Stage 4: Read Replicas
- Read-heavy endpoints (browsing, history) → read replicas
- Writes go to primary
- Adds eventual consistency for some reads

### Stage 5: Service Extraction
Most likely candidates for becoming microservices:
- Notifications (high volume, simple)
- Fraud detection (heavy compute, batchable)
- Payment/ledger (compliance isolation)

**Don't do any of this prematurely.** Stage 1 handles a lot.

---

## High Availability (Future)

Not for V1. For reference when needed:

### Stage 5+: Multi-AZ
- Multiple VPS instances behind load balancer
- DB with sync replica
- Redis cluster
- Stateless API allows seamless scaling

### Stage 6: Multi-Region
- Different cities served by different regional clusters
- Multi-master DB or per-region DB with sync
- Heavy complexity, only when justified by latency

---

## Why This Architecture Wins for Solo Dev

1. **One mental model** — Same TypeScript codebase everywhere
2. **One deployable** — `docker-compose up` and you're running
3. **Scales gracefully** — No rewrite needed for 10x growth
4. **Standard patterns** — AI generates correct code
5. **Boring tech** — Predictable, debuggable
6. **Vendor-portable** — Postgres + Redis + Docker = run anywhere
7. **Cheap to start** — ₹1500/month total infra

---

## Anti-Patterns to Avoid

- ❌ **Premature microservices** — Don't split until pain forces it
- ❌ **Shared databases between modules** — Use service calls
- ❌ **God services** — Each module focused, not omnibus
- ❌ **Direct vendor coupling** — Always wrap third-parties
- ❌ **Sync calls to slow external APIs** — Always async via queue
- ❌ **Tight UI-API coupling** — Mobile contract must be stable
- ❌ **Magic frameworks** — Prefer boring over clever

---

## Architecture Decision Records (ADRs)

For major decisions, create `docs/adrs/` with one file per decision:
- ADR-001: Why modular monolith
- ADR-002: Why self-hosted over Supabase
- ADR-003: Why Fastify over NestJS
- etc.

Each ADR: context, decision, alternatives, consequences.
Helps future you (and future hires) understand "why" not just "what."
