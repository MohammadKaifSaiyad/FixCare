# Backend Module Structure

Detailed backend folder organization. Reference when adding new features.

---

## Top-Level Layout

```
fixcare-api/
├── src/
│   ├── server.ts                    # Fastify API entry point
│   ├── websocket.ts                 # WebSocket server entry
│   ├── workers/
│   │   └── index.ts                 # BullMQ workers entry
│   ├── modules/                     # Feature modules (see below)
│   ├── shared/                      # Cross-module utilities
│   └── plugins/                     # Fastify plugins
├── prisma/
│   ├── schema.prisma
│   ├── migrations/
│   └── seed.ts
├── tests/                           # Integration tests
├── docker-compose.yml
├── Dockerfile
├── .env.example
├── package.json
└── tsconfig.json
```

---

## Module Pattern

Every module follows this structure:

```
modules/<feature>/
├── <feature>.routes.ts          # Fastify route registration
├── <feature>.service.ts         # Business logic
├── <feature>.repository.ts      # DB queries (if complex)
├── <feature>.schemas.ts         # Zod schemas
├── <feature>.types.ts           # TS types
├── <feature>.events.ts          # BullMQ events emitted
└── __tests__/
    └── <feature>.test.ts
```

### Example: Bookings Module

```
modules/bookings/
├── bookings.routes.ts           # POST /v1/bookings, GET, etc.
├── bookings.service.ts          # createBooking(), cancelBooking()
├── bookings.repository.ts       # Prisma queries
├── bookings.schemas.ts          # createBookingSchema, etc.
├── bookings.types.ts            # BookingState enum, etc.
├── bookings.events.ts           # booking.created, booking.cancelled
└── __tests__/
    └── bookings.test.ts
```

---

## All Modules

### Core User Modules
- `auth/` — OTP, JWT, refresh tokens
- `users/` — Base user model
- `customers/` — Customer-specific
- `technicians/` — Technician-specific, KYC, location, trust
- `merchants/` — Merchant-specific, catalog
- `admins/` — Admin users

### Service/Catalog Modules
- `services/` — Service categories (AC, Fan, Electrical, etc.)
- `service-pricing/` — Geofenced labor rates
- `parts-catalog/` — Master parts catalog with ceiling prices
- `merchant-catalog/` — Per-merchant catalog with negotiated prices

### Booking Modules
- `bookings/` — Booking lifecycle, state machine
- `dispatch/` — Technician matching algorithm
- `addresses/` — Customer addresses, geofence zones

### Operation Modules
- `jobs/` — Active job tracking (after dispatch)
- `job-photos/` — Photo evidence management
- `job-otps/` — Arrival + completion OTPs
- `parts-procurement/` — Merchant routing, open market

### Financial Modules
- `payments/` — Razorpay integration
- `ledger/` — Double-entry ledger
- `wallet/` — Technician earnings + cash debt
- `settlements/` — T+1 merchant settlements
- `payouts/` — Technician withdrawals
- `refunds/` — Refund processing

### Trust & Compliance Modules
- `trust-scores/` — Service trust + cash compliance
- `kyc/` — Aadhaar + PAN verification
- `audit-log/` — Append-only audit trail
- `fraud/` — Rules engine

### Support Modules
- `disputes/` — Dispute workflow
- `notifications/` — Push/SMS/WhatsApp dispatch
- `events/` — Event emission/handling

### Admin Modules
- `admin/` — Admin endpoints
- `reports/` — Analytics queries

---

## Shared Layer

```
shared/
├── database/
│   ├── prisma.ts                # Prisma singleton
│   └── transactions.ts          # Transaction helpers
├── redis/
│   └── client.ts                # Redis singleton
├── storage/
│   ├── r2.ts                    # R2 client
│   └── presigned.ts             # URL signing
├── queue/
│   ├── bullmq.ts                # BullMQ setup
│   └── queues.ts                # All queue instances
├── auth/
│   ├── jwt.ts
│   ├── otp.ts
│   └── argon2.ts
├── geo/
│   └── postgis.ts               # PostGIS query helpers
├── third-party/
│   ├── razorpay.ts
│   ├── msg91.ts
│   ├── setu.ts
│   ├── karza.ts
│   ├── onesignal.ts
│   └── gupshup.ts
├── utils/
│   ├── currency.ts              # Money handling (no floats!)
│   ├── dates.ts                 # Timezone-aware dates
│   ├── phones.ts                # Indian phone validation
│   └── errors.ts                # Error classes
├── middleware/
│   ├── auth.ts                  # JWT verification
│   ├── rbac.ts                  # Role-based access
│   └── errorHandler.ts          # Global error handler
└── types/
    └── shared.ts                # Cross-module types
```

---

## Fastify Plugins

```
plugins/
├── cors.ts                      # CORS configuration
├── helmet.ts                    # Security headers
├── ratelimit.ts                 # Rate limiting
├── swagger.ts                   # OpenAPI docs
├── multipart.ts                 # File uploads
├── websocket.ts                 # WS support
└── sentry.ts                    # Error tracking
```

---

## Workers (Background Jobs)

```
workers/
├── index.ts                     # Worker entry point
├── notifications.worker.ts      # Push/SMS/WhatsApp
├── payments.worker.ts           # Razorpay webhooks
├── kyc.worker.ts                # KYC API calls
├── fraud.worker.ts              # Fraud rule evaluation
├── settlements.worker.ts        # Daily settlements
├── trust-scores.worker.ts       # Nightly trust recalc
└── dispatch.worker.ts           # Async technician matching
```

---

## Inter-Module Communication Rules

### ✅ Allowed

**Service-to-service calls within module:**
```ts
// bookings.service.ts
import { dispatchService } from '../dispatch/dispatch.service';
const technician = await dispatchService.findBestTechnician(booking);
```

**Event emission:**
```ts
// bookings.service.ts
await eventQueue.add('booking.created', { bookingId });
// Other modules listen if interested
```

### ❌ Forbidden

**Direct DB query into another module's tables:**
```ts
// bookings.service.ts — BAD
const technician = await prisma.technician.findUnique({ ... });  // Use techniciansService instead
```

**Importing routes from another module:**
```ts
// admin.routes.ts — BAD
import { bookingsRoutes } from '../bookings/bookings.routes';  // Use services
```

---

## File Naming Conventions

| Pattern | Example | Purpose |
|---|---|---|
| `<feature>.routes.ts` | `bookings.routes.ts` | Fastify routes |
| `<feature>.service.ts` | `bookings.service.ts` | Business logic |
| `<feature>.repository.ts` | `bookings.repository.ts` | Complex queries (optional) |
| `<feature>.schemas.ts` | `bookings.schemas.ts` | Zod schemas |
| `<feature>.types.ts` | `bookings.types.ts` | TypeScript types |
| `<feature>.events.ts` | `bookings.events.ts` | Event constants |
| `<feature>.worker.ts` | `notifications.worker.ts` | BullMQ workers |
| `<feature>.test.ts` | `bookings.test.ts` | Tests |

---

## Database Schema Files

Single `schema.prisma` for V1. Logical sections via comments:

```prisma
// =============================================================================
// AUTH
// =============================================================================
model User { ... }
model RefreshToken { ... }

// =============================================================================
// USERS & ROLES
// =============================================================================
model Customer { ... }
model Technician { ... }
model Merchant { ... }
model Admin { ... }

// =============================================================================
// CATALOG
// =============================================================================
model ServiceCategory { ... }
model PartsCatalog { ... }

// =============================================================================
// BOOKINGS
// =============================================================================
model Booking { ... }
model BookingState { ... }
model JobPhoto { ... }

// =============================================================================
// FINANCIAL
// =============================================================================
model LedgerEntry { ... }
model Settlement { ... }
model Payout { ... }
model AuditLog { ... }

// (Continue for all modules)
```

When schema grows beyond ~1500 lines, consider splitting via Prisma's `multiSchema` feature.

---

## When to Add a New Module

Add a new module when:
- You have 3+ related endpoints
- You have distinct business logic that doesn't fit existing modules
- You have a different consumer or audience

Don't add a module for:
- Single endpoint (put it in admin or relevant existing module)
- Pure utility code (use shared/)
- Wrapper around third-party (use shared/third-party/)
