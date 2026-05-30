# Backend Stack

Node.js + Fastify + Prisma + Postgres. Self-hosted, containerized.

---

## Core Stack

```
Runtime:         Node.js 22 LTS
Framework:       Fastify 5.x
Language:        TypeScript 5.x (strict mode)
ORM:             Prisma 6.x
Database:        PostgreSQL 16 + PostGIS extension
Cache:           Redis 7
Queue:           BullMQ (built on Redis)
Validation:      Zod 3.x
Logger:          Pino (Fastify native)
```

---

## Why Fastify (Not Express or NestJS)

| Aspect | Express | Fastify | NestJS |
|---|---|---|---|
| Setup complexity | Low | Medium | High |
| Boilerplate | Low | Low | High |
| Performance | Baseline | 2-3x faster | Same as Express |
| Schema validation | Manual | Built-in (Zod-friendly) | Decorator-based |
| TypeScript support | Manual setup | Excellent | Excellent (heavy) |
| Plugin system | Middleware chain | First-class plugins | Modules |
| AI codegen quality | High | High | Medium (decorator confusion) |
| Solo-dev suitability | OK | Best | Overkill |

**Fastify hits the mid-complexity sweet spot.**

---

## Project Setup

```bash
# Initial setup
mkdir fixcare-api && cd fixcare-api
pnpm init
pnpm add fastify @fastify/cors @fastify/helmet @fastify/rate-limit
pnpm add @fastify/jwt @fastify/multipart @fastify/websocket
pnpm add prisma @prisma/client zod
pnpm add bullmq ioredis
pnpm add argon2 jsonwebtoken
pnpm add pino-pretty  # dev dependency for logs
pnpm add -D typescript @types/node tsx prisma
```

### Use pnpm, not npm or yarn
- Faster
- Disk-efficient (symlinked node_modules)
- Better dependency resolution
- Industry standard now

---

## TypeScript Configuration

`tsconfig.json` essentials:
```
"strict": true,
"noUncheckedIndexedAccess": true,
"target": "ES2022",
"module": "NodeNext",
"moduleResolution": "NodeNext",
"esModuleInterop": true,
"skipLibCheck": true
```

### Why Strict Mode
- Catches AI-generated errors at compile time
- Forces null/undefined handling
- Industry standard for production
- Saves hours of debugging

---

## Folder Structure

```
src/
├── server.ts                 # Fastify app entry
├── workers/
│   └── index.ts              # BullMQ workers entry
├── modules/
│   ├── auth/
│   │   ├── auth.routes.ts
│   │   ├── auth.service.ts
│   │   ├── auth.schemas.ts   # Zod schemas
│   │   └── auth.types.ts
│   ├── users/
│   ├── customers/
│   ├── workers/
│   ├── merchants/
│   ├── services/
│   ├── bookings/
│   ├── dispatch/
│   ├── catalog/
│   ├── payments/
│   ├── wallet/
│   ├── disputes/
│   ├── notifications/
│   ├── fraud/
│   └── admin/
├── shared/
│   ├── database/
│   │   └── prisma.ts         # Prisma client singleton
│   ├── redis/
│   │   └── client.ts
│   ├── storage/
│   │   └── r2.ts             # Cloudflare R2 wrapper
│   ├── queue/
│   │   └── bullmq.ts
│   ├── utils/
│   │   ├── jwt.ts
│   │   ├── otp.ts
│   │   └── geo.ts            # PostGIS query helpers
│   └── middleware/
│       ├── auth.ts
│       └── errorHandler.ts
└── plugins/                  # Fastify plugins
    ├── cors.ts
    ├── helmet.ts
    └── ratelimit.ts

prisma/
├── schema.prisma
└── migrations/
```

### Module Pattern (Per Feature)
- `*.routes.ts` — Fastify route registration
- `*.service.ts` — Business logic
- `*.schemas.ts` — Zod request/response schemas
- `*.types.ts` — TypeScript types (Prisma-derived + custom)

---

## Database with Prisma

### Why Prisma
- Type-safe queries (auto-generated TypeScript types)
- Best migration system in Node ecosystem
- Excellent AI codegen support
- Prisma Studio for visual DB browsing
- Supports PostGIS via raw queries when needed

### Schema Highlights

```prisma
// prisma/schema.prisma (conceptual)
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id            String   @id @default(uuid())
  phone         String   @unique
  role          UserRole
  createdAt     DateTime @default(now())
  // ... more fields
}

enum UserRole {
  CUSTOMER
  TECHNICIAN
  MERCHANT
  ADMIN
}
```

### PostGIS via Raw SQL
Prisma doesn't natively support PostGIS, so:
- Define location as `Unsupported("geography(Point, 4326)")`
- Use `$queryRaw` for spatial queries
- Wrap in service functions for type safety

```ts
// Example: find nearest technicians
const technicians = await prisma.$queryRaw`
  SELECT id, full_name,
    ST_Distance(location, ST_MakePoint(${lng}, ${lat})::geography) as distance
  FROM technicians
  WHERE ST_DWithin(location, ST_MakePoint(${lng}, ${lat})::geography, 5000)
  ORDER BY distance
  LIMIT 10
`;
```

---

## Authentication Strategy

### Phone OTP + JWT

**Flow:**
1. User enters phone → POST `/auth/otp/send`
2. Backend generates 6-digit OTP, stores in Redis with 5-min TTL
3. Backend sends OTP via MSG91
4. User enters OTP → POST `/auth/otp/verify`
5. Backend validates, creates user if new
6. Issue access token (15 min) + refresh token (30 days)
7. Refresh token stored in Redis (revocable)

### Tokens
- **Access token:** JWT, 15-minute expiry, signed with HS256
- **Refresh token:** Opaque random string, 30-day expiry, stored in Redis
- **Refresh rotation:** New refresh token issued on each refresh

### Why Argon2id for Passwords (Admin Only)
- Argon2 is the modern password hashing standard
- Bcrypt is older, slower, less memory-hard
- Customers/technicians don't have passwords (OTP only)
- Admins use email + password for dashboard

### Auth Plugin Pattern
```ts
// Pseudocode
fastify.decorate('authenticate', async (request, reply) => {
  const token = request.headers.authorization?.replace('Bearer ', '');
  const payload = await verifyJWT(token);
  request.user = await fetchUser(payload.userId);
});

// Use on protected routes
fastify.get('/bookings', { preHandler: [fastify.authenticate] }, handler);
```

---

## Validation with Zod

### Pattern
```ts
// auth.schemas.ts
import { z } from 'zod';

export const sendOtpSchema = z.object({
  phone: z.string().regex(/^[6-9]\d{9}$/, 'Invalid Indian phone'),
});

export type SendOtpInput = z.infer<typeof sendOtpSchema>;

// auth.routes.ts
fastify.post('/auth/otp/send', {
  schema: { body: sendOtpSchema },
}, async (request, reply) => {
  const { phone } = request.body as SendOtpInput;
  // ... logic
});
```

### Why Zod
- Single source of truth for runtime validation + TS types
- Works seamlessly with Fastify
- Excellent error messages
- AI generates correct Zod schemas reliably

---

## Real-time with WebSockets

### Use Cases
- Technician location updates → customer's tracking screen
- Job status changes → both technician + customer
- Cash debt updates → technician dashboard

### Pattern
- Separate Fastify process for WebSocket (port 3001)
- Auth via JWT in connection query param
- Rooms by job ID: `job:{jobId}` subscribed to by relevant users
- Server pushes events from BullMQ → WebSocket clients

### When NOT to Use WebSocket
- Booking creation (regular REST POST)
- Payment initiation (regular REST POST)
- Profile updates (regular REST)
- Anything that's not "live"

**Rule:** WebSocket only for genuinely real-time data. Everything else is REST.

---

## Background Jobs with BullMQ

### Queue Types

| Queue Name | Purpose | Concurrency |
|---|---|---|
| `notifications` | Push, SMS, WhatsApp | 10 |
| `payments` | Razorpay webhook processing | 5 |
| `kyc` | KYC vendor API calls | 3 |
| `fraud` | Rule evaluation | 5 |
| `settlements` | T+1 merchant payouts | 1 (daily) |
| `trust-scores` | Recalculate scores | 1 (nightly) |
| `dispatch` | Technician matching | 5 |

### Pattern
```ts
// Producer
import { Queue } from 'bullmq';
const notificationQueue = new Queue('notifications', { connection: redis });

await notificationQueue.add('push', {
  userId,
  title: 'New job available',
  body: '...',
});

// Technician (separate process)
import { Technician } from 'bullmq';
new Technician('notifications', async (job) => {
  if (job.name === 'push') {
    await sendPush(job.data);
  }
}, { connection: redis });
```

### Why BullMQ
- Built on Redis (already using it)
- Excellent reliability (retries, dead letter queues)
- Job scheduling (cron-style for settlements)
- Easy monitoring with Bull Board

---

## File Storage with Cloudflare R2

### Setup
- S3-compatible API
- No egress fees (huge for mobile app downloads)
- Use `@aws-sdk/client-s3` (works with R2)
- Pre-signed URLs for direct uploads from mobile

### Upload Pattern
1. Mobile app → POST `/uploads/sign` → returns pre-signed URL
2. Mobile app uploads directly to R2 (no backend bandwidth)
3. Mobile app → POST `/jobs/:id/photos` with R2 URL
4. Backend stores URL in database

### Folder Structure in R2
```
fixcare-prod/
  ├── kyc/                  # KYC documents (Aadhaar, PAN)
  │   └── {technician_id}/
  ├── jobs/                 # Job photos
  │   └── {job_id}/
  │       ├── diagnosis-1.jpg
  │       ├── diagnosis-2.jpg
  │       ├── old-part.jpg
  │       ├── new-part-package.jpg
  │       └── installed.jpg
  ├── bills/                # Open market bills
  │   └── {job_id}/
  └── profile/              # Profile pics
      └── {user_id}/
```

### Security
- KYC bucket: private, signed URLs with 1-hour expiry
- Job photos: private, signed URLs with 24-hour expiry
- Profile pics: public (read), authenticated write
- All uploads scanned for malware (when budget allows)

---

## API Patterns

### REST Conventions
- Plural nouns: `/bookings`, `/technicians`
- Standard verbs: GET, POST, PATCH, DELETE
- Nested resources: `/bookings/:id/photos`
- Filter via query string: `/bookings?status=active&technician_id=xxx`
- Pagination: `?limit=20&cursor=xxx` (cursor-based)

### Response Envelope
```json
{
  "data": { ... },
  "meta": {
    "pagination": { "cursor": "..." }
  }
}
```

Or for errors:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Invalid phone number",
    "details": { ... }
  }
}
```

### Versioning
- URL prefix: `/v1/bookings`
- Bump major version when breaking changes
- Maintain v1 for 6 months after v2 launches

---

## Error Handling

### Hierarchy
```ts
class AppError extends Error {
  constructor(
    public code: string,
    public statusCode: number,
    message: string,
    public details?: any
  ) {
    super(message);
  }
}

class ValidationError extends AppError { ... }
class NotFoundError extends AppError { ... }
class UnauthorizedError extends AppError { ... }
class BusinessRuleError extends AppError { ... }  // e.g., "Cash limit exceeded"
class ExternalServiceError extends AppError { ... }  // e.g., Razorpay down
```

### Global Error Handler
```ts
fastify.setErrorHandler((error, request, reply) => {
  // Log to Sentry
  // Map to user-friendly response
  // Never leak internal details to client
});
```

---

## Logging

### Pino Configuration
- Structured JSON logs in production
- Pretty-printed in development
- Levels: trace, debug, info, warn, error, fatal
- Include: request_id, user_id, timestamp, module

### What to Log
- All API requests (sanitized)
- All errors with stack traces
- Background job start/complete/fail
- External API calls (Razorpay, MSG91, KYC)
- Auth events (login, refresh, logout)

### What NOT to Log
- Passwords, OTPs, tokens
- Aadhaar numbers
- UPI IDs
- Photo contents

---

## API Documentation

### Auto-generated with Fastify
- `@fastify/swagger` + Zod schemas
- Available at `/docs` in dev, password-protected in prod
- Generate Dart API client from OpenAPI spec → reduces mobile work

---

## Security Layer

### Built into Stack
- HTTPS via Caddy (auto Let's Encrypt)
- Helmet for security headers
- CORS strictly configured
- Rate limiting via `@fastify/rate-limit`
- SQL injection: impossible with Prisma
- Argon2id for password hashing
- JWT signed with strong secret

### Custom Adds
- IP-based rate limits on auth endpoints
- Per-user rate limits on booking endpoints
- Audit log on all financial transactions
- Encryption at rest for sensitive fields (Aadhaar)

---

## Testing Strategy

```
Unit tests:      Vitest (faster than Jest)
Integration:     Vitest + supertest
E2E:             Postman/Bruno collections (manual + CI)
```

### Priority Coverage
- Payment flow (must have)
- Auth flow (must have)
- Job state machine (must have)
- Ledger calculations (must have)
- Dispatch algorithm (should have)

### Skip in V1
- UI E2E tests (manual QA enough)
- Performance tests (until scale problems)

---

## Deployment Build

```dockerfile
# Multi-stage Dockerfile (conceptual)
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY . .
RUN pnpm prisma generate && pnpm build

FROM node:22-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

---

## Environment Variables

Critical env vars (use `.env` locally, secrets manager in prod):

```
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
JWT_SECRET=...
JWT_REFRESH_SECRET=...
R2_ACCESS_KEY=...
R2_SECRET_KEY=...
R2_BUCKET=...
RAZORPAY_KEY_ID=...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...
MSG91_AUTH_KEY=...
ONESIGNAL_APP_ID=...
ONESIGNAL_API_KEY=...
SETU_CLIENT_ID=...
KARZA_API_KEY=...
SENTRY_DSN=...
NODE_ENV=production
PORT=3000
```

**Never commit `.env`.** Use `.env.example` as template.

---

## What NOT to Do

- ❌ Don't add unused dependencies
- ❌ Don't add ORM features without need (no Prisma views, etc.)
- ❌ Don't use Express middleware patterns in Fastify
- ❌ Don't write SQL strings; use Prisma
- ❌ Don't return raw Prisma objects from API (always map to DTOs)
- ❌ Don't trust client-provided data (always validate)
- ❌ Don't catch errors silently; log them all
- ❌ Don't use `any` type (use `unknown` if needed)
