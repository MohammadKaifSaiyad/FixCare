# Booking B6a — UPI Payment via Razorpay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The first money-moving slice — customer initiates a UPI charge (Razorpay order), the signature-verified `payment.captured` webhook drives CUSTOMER_CONFIRMED→PAYMENT_RECEIVED as SYSTEM; declined bookings charge their locked visit fee.

**Architecture:** A `Payment` attempt model (append-only evidence), a lazy-cred `PaymentGateway` third-party wrapper (Dev fake + real Razorpay SDK), a customer `pay` endpoint (idempotent order creation), and an unauthenticated webhook route whose raw-body HMAC signature IS the auth — amount-verified, duplicate-safe, transitioning via `transitionBooking`. `chargeAmountFor` is the single amount source (approved total OR visit fee).

**Tech Stack:** Node 22, Fastify 5 (raw-body content parser for one route), Prisma 6, Zod 4, `razorpay` npm SDK, node:crypto HMAC-SHA256, Vitest.

## Global Constraints

- Commit author MUST be `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` with NO Co-Authored-By/Claude trailer: `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."`.
- Backend commands from `apps/backend` with env sourced: `set -a && source .env && set +a` before `pnpm vitest run` / `pnpm tsc --noEmit`. Docker stack up.
- Money is integer paise ONLY. The charge amount comes from snapshots via `chargeAmountFor` — never recomputed from live catalog (Golden Rule 4).
- Rule 1: PAYMENT_RECEIVED requires the gateway's signed capture of the EXACT ordered amount. Rule 2: SYSTEM-only transition. Rule 3: funds land in the platform Razorpay account. Rule 5: Payment mutation + transition + audit in ONE tx. Rule 7: no card/UPI-VPA details stored or logged; webhook bodies never logged raw; secrets never logged.
- Razorpay creds (`RAZORPAY_KEY_ID/KEY_SECRET/WEBHOOK_SECRET`) are optional in config; the real gateway checks them LAZILY on first use (R2 posture — production boots before keys exist). Signature compare must be timing-safe (`crypto.timingSafeEqual`).
- No `any`; TS strict; ESM `.js` imports; Zod-validated bodies; service-layer writes; DTOs only.
- Design (source of truth): `docs/designs/2026-07-18-booking-b6a-upi-payment-design.md`.
- Baseline: 262 tests green on `feature/booking-b6-payment` (fresh off main `d2f54e5`).

---

### Task 1: Schema — Payment model + PAYMENT_EVENT + state-machine entries

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AuditAction ~line 197; Booking relations ~line 339; new enums+model after PhotoEvidence)
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts` (ALLOWED_TRANSITIONS line 22; ALLOWED_ACTORS)
- Modify: `apps/backend/tests/schema/helpers.ts` (TRUNCATE list)
- Test: `apps/backend/tests/schema/payment-schema.test.ts` + extend `apps/backend/tests/bookings/booking-actor-unit.test.ts`

**Interfaces:**
- Produces: `PaymentMethod` (`UPI`), `PaymentStatus` (`CREATED|CAPTURED|FAILED`), `prisma.payment` (fields exactly: `id, bookingId, method, status @default(CREATED), amountPaise Int, razorpayOrderId @unique, razorpayPaymentId? @unique, failureReason?, capturedAt?, createdAt, updatedAt`, `@@index([bookingId])`), `Booking.payments Payment[]`, `AuditAction.PAYMENT_EVENT`; `ALLOWED_TRANSITIONS.DECLINED_BY_CUSTOMER = ['PAYMENT_RECEIVED']`; `ALLOWED_ACTORS.PAYMENT_RECEIVED = ['SYSTEM']`.

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/schema/payment-schema.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

// Mirrors tests/schema/repair-schema.test.ts's seed — copy that file's seedBooking VERBATIM
// (it has the correct required fields: LaborTier 'T1', Address label, etc.).
async function seedBooking() {
  const user = await prisma.user.create({ data: { phone: `98${Math.floor(Math.random() * 1e8)}`, role: 'CUSTOMER' } });
  const customer = await prisma.customer.create({ data: { userId: user.id, name: 'C' } });
  const zone = await prisma.zone.create({ data: { name: `Z-${Math.random().toString(36).slice(2, 8)}`, visitFeePaise: 9900 } });
  const cat = await prisma.serviceCategory.create({ data: { name: `Cat-${Math.random().toString(36).slice(2, 8)}` } });
  const service = await prisma.service.create({ data: { name: 'S', categoryId: cat.id, tier: 'T1', requiredSkill: 'AC' } });
  const address = await prisma.address.create({ data: { customerId: customer.id, label: 'Home', line1: 'L1', pincode: '390001', zoneId: zone.id } });
  return prisma.booking.create({
    data: {
      bookingNumber: `FC-${Math.random().toString(36).slice(2, 8)}`,
      customerId: customer.id, addressId: address.id, serviceId: service.id,
      zoneId: zone.id, zoneName: zone.name, serviceName: service.name,
      visitFeePaise: 9900, laborPaise: 50000, laborTier: 'T1',
      scheduledSlot: new Date(Date.now() + 86_400_000),
    },
  });
}

describe('Payment model', () => {
  it('creates a UPI payment attempt and reads back via Booking.payments', async () => {
    const b = await seedBooking();
    await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 45100, razorpayOrderId: 'order_test_1' } });
    const withPayments = await prisma.booking.findUnique({ where: { id: b.id }, include: { payments: true } });
    expect(withPayments!.payments).toHaveLength(1);
    expect(withPayments!.payments[0]!.status).toBe('CREATED');
    expect(withPayments!.payments[0]!.razorpayPaymentId).toBeNull();
  });

  it('razorpayOrderId and razorpayPaymentId are unique (idempotency anchors)', async () => {
    const b = await seedBooking();
    await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 100, razorpayOrderId: 'order_dup' } });
    await expect(
      prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', amountPaise: 100, razorpayOrderId: 'order_dup' } }),
    ).rejects.toThrow();
  });

  it('PAYMENT_EVENT is a valid audit action', async () => {
    const log = await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'order_created' } } });
    expect(log.action).toBe('PAYMENT_EVENT');
  });
});
```

And APPEND to `apps/backend/tests/bookings/booking-actor-unit.test.ts` (before the DEFAULT-DENY block):

```ts
  it('PAYMENT_RECEIVED is SYSTEM-only (the gateway drives it, never a party)', () => {
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'TECHNICIAN')).toBe(false);
  });
```

and change the DEFAULT-DENY block's `PAYMENT_RECEIVED` example (now mapped) to `CLOSED`:

```ts
  it('DEFAULT-DENY: still-unmapped to-states are rejected for every actor', () => {
    expect(actorAllowedFor('CANCELLED_BY_TECHNICIAN', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('CLOSED', 'SYSTEM')).toBe(false); // B6c/B7 wires the dispute-window close
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/payment-schema.test.ts tests/bookings/booking-actor-unit.test.ts`
Expected: FAIL — `prisma.payment` undefined / `PAYMENT_EVENT` invalid / SYSTEM not allowed for PAYMENT_RECEIVED.

- [ ] **Step 3: Schema edits.** In `apps/backend/prisma/schema.prisma`: `AuditAction` += `PAYMENT_EVENT` (after `PHOTO_UPLOADED`); `Booking` += `payments Payment[]` (next to `photos`); after the PhotoEvidence block add:

```prisma
enum PaymentMethod {
  UPI
  // B6b appends: CASH
}

enum PaymentStatus {
  CREATED // order created, awaiting the customer's UPI approval
  CAPTURED // gateway confirmed capture — the money moved
  FAILED // gateway reported failure — customer may retry (new order)
}

// Payment attempts are append-only EVIDENCE (no soft-delete; status is the lifecycle).
// amountPaise snapshots the charge at order time — the ONLY amount we accept capture for.
model Payment {
  id                String        @id @default(uuid())
  bookingId         String
  booking           Booking       @relation(fields: [bookingId], references: [id])
  method            PaymentMethod
  status            PaymentStatus @default(CREATED)
  amountPaise       Int
  razorpayOrderId   String        @unique
  razorpayPaymentId String?       @unique // set on capture; the webhook idempotency anchor
  failureReason     String?
  capturedAt        DateTime?
  createdAt         DateTime      @default(now())
  updatedAt         DateTime      @updatedAt

  @@index([bookingId])
}
```

- [ ] **Step 4: State machine.** In `bookings.state.ts`: change line 22 `DECLINED_BY_CUSTOMER:    [],` to:

```ts
  DECLINED_BY_CUSTOMER:    ['PAYMENT_RECEIVED'], // the locked visit fee is still owed (B6a)
```

and `ALLOWED_ACTORS` += `PAYMENT_RECEIVED: ['SYSTEM'], // the gateway's signed capture drives this — never a party`.

- [ ] **Step 5: Migrate BOTH DBs + TRUNCATE list**

```bash
pnpm prisma migrate dev --name payment_upi
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Add `"Payment"` to the front of the TRUNCATE list in `tests/schema/helpers.ts`.

- [ ] **Step 6: Green + typecheck + commit**

Run: `pnpm vitest run tests/schema tests/bookings/booking-actor-unit.test.ts` → PASS; `pnpm tsc --noEmit` → clean.

```bash
git add prisma/schema.prisma prisma/migrations src/modules/bookings/bookings.state.ts tests/schema/payment-schema.test.ts tests/schema/helpers.ts tests/bookings/booking-actor-unit.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): Payment model + PAYMENT_EVENT + PAYMENT_RECEIVED wiring (B6a schema)"
```

---

### Task 2: PaymentGateway wrapper (Dev + Razorpay) + config keys

**Files:**
- Create: `apps/backend/src/shared/third-party/razorpay.ts`
- Modify: `apps/backend/src/shared/config.ts` (3 optional keys after the R2 block)
- Modify: `apps/backend/.env.example`
- Modify: `apps/backend/package.json` (`pnpm add razorpay`)
- Test: `apps/backend/tests/shared/razorpay.test.ts`

**Interfaces:**
- Produces (Task 3 imports verbatim): `interface PaymentGateway { createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }>; verifyWebhookSignature(rawBody: string, signature: string): boolean; }`; `class DevPaymentGateway implements PaymentGateway` with test hook `signPayload(rawBody: string): string`; `const paymentGateway: PaymentGateway` singleton via `makePaymentGateway()`.

- [ ] **Step 1: Install the SDK**

```bash
cd apps/backend && pnpm add razorpay
```

- [ ] **Step 2: Write the failing tests** (`apps/backend/tests/shared/razorpay.test.ts`)

```ts
import { describe, expect, it } from 'vitest';
import { DevPaymentGateway, RazorpayGateway, paymentGateway } from '../../src/shared/third-party/razorpay.js';

describe('DevPaymentGateway', () => {
  it('creates deterministic dev order ids', async () => {
    const g = new DevPaymentGateway();
    const a = await g.createOrder(45100, 'booking-1');
    const b = await g.createOrder(45100, 'booking-1');
    expect(a.orderId).toMatch(/^order_dev_/);
    expect(a.orderId).not.toBe(b.orderId); // each call is a NEW order
  });

  it('signPayload produces a signature that verifyWebhookSignature accepts; tampering rejects', () => {
    const g = new DevPaymentGateway();
    const body = JSON.stringify({ event: 'payment.captured' });
    const sig = g.signPayload(body);
    expect(g.verifyWebhookSignature(body, sig)).toBe(true);
    expect(g.verifyWebhookSignature(body + 'x', sig)).toBe(false);
    expect(g.verifyWebhookSignature(body, 'deadbeef')).toBe(false);
  });

  it('the module singleton is the Dev impl outside production', () => {
    expect(paymentGateway).toBeInstanceOf(DevPaymentGateway);
  });
});

describe('RazorpayGateway boot safety', () => {
  it('constructs WITHOUT creds; first USE fails with a clear config error (lazy, R2 posture)', async () => {
    const g = new RazorpayGateway();
    await expect(g.createOrder(100, 'x')).rejects.toThrow(/Razorpay is not configured/);
    expect(() => g.verifyWebhookSignature('{}', 'sig')).toThrow(/Razorpay is not configured/);
  });
});
```

- [ ] **Step 3: Run to verify they fail** → cannot find module.

- [ ] **Step 4: Config + env.** `config.ts` after the R2 block:

```ts
  // Razorpay (UPI payments). Optional until KYC approval — the gateway wrapper stays inert
  // (Dev stub) without them; live keys swap in with zero code change.
  RAZORPAY_KEY_ID: z.string().optional(),
  RAZORPAY_KEY_SECRET: z.string().optional(),
  RAZORPAY_WEBHOOK_SECRET: z.string().optional(),
```

`.env.example` after the R2 block:

```
# Razorpay (UPI payments) — leave empty until KYC approval; test keys work in dev
RAZORPAY_KEY_ID=""
RAZORPAY_KEY_SECRET=""
RAZORPAY_WEBHOOK_SECRET=""
```

- [ ] **Step 5: The wrapper** (`apps/backend/src/shared/third-party/razorpay.ts`)

```ts
import { createHmac, timingSafeEqual, randomUUID } from 'node:crypto';
import Razorpay from 'razorpay';
import { config } from '../config.js';

/** Abstraction over the payment gateway. The rest of the code depends on this, not the SDK. */
export interface PaymentGateway {
  /** Create a gateway order for exactly amountPaise (INR). `receipt` carries the bookingId. */
  createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }>;
  /** HMAC-SHA256 of the RAW request body with the webhook secret; timing-safe compare. */
  verifyWebhookSignature(rawBody: string, signature: string): boolean;
}

const DEV_WEBHOOK_SECRET = 'dev-webhook-secret';

function hmacHex(secret: string, rawBody: string): string {
  return createHmac('sha256', secret).update(rawBody).digest('hex');
}

function safeCompareHex(expected: string, given: string): boolean {
  const a = Buffer.from(expected, 'utf8');
  const b = Buffer.from(given, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

/** Dev/test gateway: no network. `signPayload` lets tests produce VALID webhook signatures. */
export class DevPaymentGateway implements PaymentGateway {
  async createOrder(_amountPaise: number, _receipt: string): Promise<{ orderId: string }> {
    return { orderId: `order_dev_${randomUUID().slice(0, 12)}` };
  }
  verifyWebhookSignature(rawBody: string, signature: string): boolean {
    return safeCompareHex(hmacHex(DEV_WEBHOOK_SECRET, rawBody), signature);
  }
  /** Test hook: sign a payload the way the gateway would. */
  signPayload(rawBody: string): string {
    return hmacHex(DEV_WEBHOOK_SECRET, rawBody);
  }
}

/** Real Razorpay. Creds checked LAZILY on first use — production must boot before KYC
 *  approval provisions the keys (same posture as R2PhotoStorage). */
export class RazorpayGateway implements PaymentGateway {
  private lazy: { client: Razorpay; webhookSecret: string } | null = null;
  private rz(): { client: Razorpay; webhookSecret: string } {
    if (this.lazy) return this.lazy;
    if (!config.RAZORPAY_KEY_ID || !config.RAZORPAY_KEY_SECRET || !config.RAZORPAY_WEBHOOK_SECRET) {
      throw new Error('Razorpay is not configured (RAZORPAY_KEY_ID/RAZORPAY_KEY_SECRET/RAZORPAY_WEBHOOK_SECRET)');
    }
    this.lazy = {
      client: new Razorpay({ key_id: config.RAZORPAY_KEY_ID, key_secret: config.RAZORPAY_KEY_SECRET }),
      webhookSecret: config.RAZORPAY_WEBHOOK_SECRET,
    };
    return this.lazy;
  }
  async createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }> {
    const { client } = this.rz();
    try {
      const order = await client.orders.create({ amount: amountPaise, currency: 'INR', receipt });
      return { orderId: order.id };
    } catch {
      throw new Error('Razorpay createOrder failed'); // typed boundary: never leak raw SDK errors
    }
  }
  verifyWebhookSignature(rawBody: string, signature: string): boolean {
    const { webhookSecret } = this.rz();
    return safeCompareHex(hmacHex(webhookSecret, rawBody), signature);
  }
}

/** Factory: dev stub everywhere except production (same posture as makeOtpSender/makePhotoStorage). */
export function makePaymentGateway(): PaymentGateway {
  return config.NODE_ENV === 'production' ? new RazorpayGateway() : new DevPaymentGateway();
}

/** Module singleton — services import this; tests reach the Dev impl through it. */
export const paymentGateway: PaymentGateway = makePaymentGateway();
```

- [ ] **Step 6: Green + typecheck + commit**

Run the test file → PASS (4 tests); `pnpm tsc --noEmit` → clean.

```bash
git add src/shared/third-party/razorpay.ts src/shared/config.ts .env.example package.json ../../pnpm-lock.yaml tests/shared/razorpay.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): PaymentGateway third-party wrapper (Dev + Razorpay, lazy creds)"
```

---

### Task 3: `chargeAmountFor` + `POST /me/bookings/:id/pay` (idempotent)

**Files:**
- Create: `apps/backend/src/modules/bookings/charge.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (+`initiatePayment`)
- Modify: `apps/backend/src/modules/bookings/bookings.routes.ts` (one route)
- Test: `apps/backend/tests/bookings/payment.test.ts` (new)

**Interfaces:**
- Consumes: `computeEstimate` (`./estimate.js`), `paymentGateway` (Task 2), `prisma.payment` (Task 1), existing `requireCustomer`, `ConflictError/NotFoundError`.
- Produces (Task 4 relies on): `chargeAmountFor(booking: {state, visitFeePaise, laborPaise}, parts: BookingPart[]): number` (charge.ts; 409 on other states); `initiatePayment(userId, id): Promise<{orderId: string; amountPaise: number; keyId: string | null}>`; route `POST /me/bookings/:id/pay` (200). Test fixture `confirmedBooking()` (drives both keystones — full E2E chain).

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/bookings/payment.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos, seedRepairPhotos } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a booking through BOTH keystones to CUSTOMER_CONFIRMED. labor 60000, visitFee 14900. */
export async function confirmedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/start-repair`, headers: auth(t.token) });
  await seedRepairPhotos(booking.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/complete-repair`, headers: auth(t.token) });
  const otp = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: otp } });
  return { c, t, bookingId: booking.id as string };
}

describe('POST /me/bookings/:id/pay', () => {
  it('creates the order for the approved total (empty cart: labor − visitFee) + Payment row + audit', async () => {
    const { c, bookingId } = await confirmedBooking();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.amountPaise).toBe(45100); // 60000 − 14900, the invariant-locked approved total
    expect(body.orderId).toMatch(/^order_dev_/);
    const rows = await prisma.payment.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.status).toBe('CREATED');
    expect(rows[0]!.amountPaise).toBe(45100);
    expect(await prisma.auditLog.count({ where: { action: 'PAYMENT_EVENT' } })).toBe(1);
  });

  it('is idempotent: a second pay returns the SAME order (no duplicate rows)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).toBe(first.orderId);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(1);
  });

  it('a DECLINED booking pays exactly the locked visit fee', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    await seedDiagnosisPhotos(booking.id);
    const issue = await seedIssue(f.cat.id);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/decline`, headers: auth(c.token) });
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().amountPaise).toBe(14900); // visitFeePaise only
  });

  it('guards: wrong state 409, foreign customer 404, technician 403', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).statusCode).toBe(409);
    const confirmed = await confirmedBooking();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(confirmed.t.token) })).statusCode).toBe(403);
  });
});
```

- [ ] **Step 2: Run to verify they fail** → 404 (route doesn't exist).

- [ ] **Step 3: `charge.ts`** (`apps/backend/src/modules/bookings/charge.ts`)

```ts
import type { BookingPart } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';
import { computeEstimate } from './estimate.js';

/** The ONE source of the charge amount (Golden Rule 4: snapshots only, never live catalog).
 *  - CUSTOMER_CONFIRMED: the invariant-locked approved total (labor + parts − visit-fee credit).
 *  - DECLINED_BY_CUSTOMER: the visit fee locked at ARRIVED — the visit happened, the repair didn't.
 *  Anything else is not chargeable. */
export function chargeAmountFor(
  booking: { state: string; laborPaise: number; visitFeePaise: number },
  parts: BookingPart[],
): number {
  if (booking.state === 'CUSTOMER_CONFIRMED') {
    return computeEstimate(booking as Parameters<typeof computeEstimate>[0], parts).totalPayablePaise;
  }
  if (booking.state === 'DECLINED_BY_CUSTOMER') {
    return booking.visitFeePaise;
  }
  throw new ConflictError('Booking is not awaiting payment');
}
```

> NOTE for the implementer: prefer typing `booking` as `{ state: BookingState; laborPaise: number; visitFeePaise: number }` (import the type) over the cast shown — adjust so `pnpm tsc --noEmit` passes with NO `as` if possible.

- [ ] **Step 4: `initiatePayment`** — append to `bookings.service.ts` (import `chargeAmountFor` from `./charge.js`, `paymentGateway` from `../../shared/third-party/razorpay.js`):

```ts
/** Customer initiates the UPI charge. Idempotent: an open (CREATED) attempt returns the SAME
 *  order — double-taps and app restarts never create duplicate gateway orders. */
export async function initiatePayment(userId: string, id: string): Promise<{ orderId: string; amountPaise: number; keyId: string | null }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { bookingParts: true },
  });
  if (!booking) throw new NotFoundError('Booking not found');
  const amountPaise = chargeAmountFor(booking, booking.bookingParts); // 409s on non-payable states

  const existing = await prisma.payment.findFirst({ where: { bookingId: id, method: 'UPI' }, orderBy: { createdAt: 'desc' } });
  if (existing?.status === 'CAPTURED') throw new ConflictError('This booking is already paid');
  if (existing?.status === 'CREATED') {
    return { orderId: existing.razorpayOrderId, amountPaise: existing.amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
  }

  // Gateway order BEFORE the tx: an orphaned order from a tx failure is harmless (unpaid orders
  // expire gateway-side); a DB row without an order would be a broken checkout.
  const { orderId } = await paymentGateway.createOrder(amountPaise, id);
  await prisma.$transaction(async (tx) => {
    await tx.payment.create({ data: { bookingId: id, method: 'UPI', amountPaise, razorpayOrderId: orderId } });
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { bookingId: id, event: 'order_created', amountPaise } },
    });
  });
  return { orderId, amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
}
```

- [ ] **Step 5: Route** in `bookings.routes.ts` (extend the service import):

```ts
  app.post('/me/bookings/:id/pay', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await initiatePayment(req.user!.id, (req.params as { id: string }).id));
  });
```

- [ ] **Step 6: Green + suites + commit**

Run: `pnpm vitest run tests/bookings/payment.test.ts` → PASS (4); then `pnpm vitest run tests/bookings` → no regressions; `pnpm tsc --noEmit` → clean.

```bash
git add src/modules/bookings tests/bookings/payment.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): chargeAmountFor + idempotent UPI pay endpoint"
```

---

### Task 4: Signature-verified webhook → PAYMENT_RECEIVED

**Files:**
- Create: `apps/backend/src/modules/payments/webhook.routes.ts` + `apps/backend/src/modules/payments/webhook.service.ts`
- Modify: `apps/backend/src/app.ts` (register the webhook routes)
- Test: extend `apps/backend/tests/bookings/payment.test.ts`

**Interfaces:**
- Consumes: `paymentGateway` + `DevPaymentGateway.signPayload` (Task 2), `prisma.payment` (Task 1), `transitionBooking` (bookings.state.js), `confirmedBooking` fixture (Task 3 — export it from the test file or inline the chain).
- Produces: `POST /webhooks/razorpay` — 401 bad/missing signature; 200 `{received: true}` for handled/ignored events; `handleWebhookEvent(rawBody: string, signature: string): Promise<void>` in webhook.service.ts.

- [ ] **Step 1: Write the failing tests** — append to `tests/bookings/payment.test.ts` (import `paymentGateway, DevPaymentGateway` from `../../src/shared/third-party/razorpay.js`; `const gw = paymentGateway as DevPaymentGateway;`):

```ts
/** Build a Razorpay-shaped payment.captured body for an order. */
function capturedEvent(orderId: string, amountPaise: number, paymentId = `pay_dev_${Math.random().toString(36).slice(2, 10)}`) {
  return JSON.stringify({
    event: 'payment.captured',
    payload: { payment: { entity: { id: paymentId, order_id: orderId, amount: amountPaise, status: 'captured' } } },
  });
}
function failedEvent(orderId: string) {
  return JSON.stringify({
    event: 'payment.failed',
    payload: { payment: { entity: { id: `pay_dev_${Math.random().toString(36).slice(2, 10)}`, order_id: orderId, amount: 0, error_description: 'UPI declined' } } },
  });
}
async function postWebhook(body: string, signature = gw.signPayload(body)) {
  return app.inject({ method: 'POST', url: '/webhooks/razorpay', headers: { 'content-type': 'application/json', 'x-razorpay-signature': signature }, payload: body });
}

describe('POST /webhooks/razorpay', () => {
  it('valid capture → Payment CAPTURED + PAYMENT_RECEIVED + evidence audit; duplicate delivery is a no-op', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId, amountPaise } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    const body = capturedEvent(orderId, amountPaise);
    expect((await postWebhook(body)).statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('PAYMENT_RECEIVED');
    const payment = await prisma.payment.findFirst({ where: { bookingId } });
    expect(payment!.status).toBe('CAPTURED');
    expect(payment!.razorpayPaymentId).not.toBeNull();
    expect(payment!.capturedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } });
    expect((audit!.metadata as { amountPaise: number }).amountPaise).toBe(amountPaise);
    // duplicate delivery: still 200, still exactly ONE transition
    expect((await postWebhook(body)).statusCode).toBe(200);
    expect(await prisma.auditLog.count({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } })).toBe(1);
  });

  it('bad signature → 401 and NOTHING changes', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId, amountPaise } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(capturedEvent(orderId, amountPaise), 'deadbeef')).statusCode).toBe(401);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
  });

  it('amount mismatch → flagged audit, NO transition, 200 (gateway stops retrying; ops investigates)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(capturedEvent(orderId, 1))).statusCode).toBe(200); // tampered/partial amount
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
    const flagged = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'amount_mismatch' } } });
    expect(flagged).not.toBeNull();
  });

  it('payment.failed → FAILED with reason; a re-pay issues a NEW order; unknown events → 200 ignored', async () => {
    const { c, bookingId } = await confirmedBooking();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(failedEvent(first.orderId))).statusCode).toBe(200);
    const failed = await prisma.payment.findFirst({ where: { razorpayOrderId: first.orderId } });
    expect(failed!.status).toBe('FAILED');
    expect(failed!.failureReason).toBe('UPI declined');
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).not.toBe(first.orderId);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(2);
    expect((await postWebhook(JSON.stringify({ event: 'refund.processed', payload: {} }))).statusCode).toBe(200);
  });
});
```

- [ ] **Step 2: Run to verify they fail** → 404 (webhook route missing).

- [ ] **Step 3: `webhook.service.ts`** (`apps/backend/src/modules/payments/webhook.service.ts`)

```ts
import { prisma } from '../../shared/database/prisma.js';
import { UnauthorizedError } from '../../shared/errors.js';
import { paymentGateway } from '../../shared/third-party/razorpay.js';
import { transitionBooking } from '../bookings/bookings.state.js';

interface RazorpayPaymentEntity {
  id: string;
  order_id: string;
  amount: number;
  error_description?: string;
}

/** Handle one gateway webhook delivery. The SIGNATURE is the authentication (Rule 1: the
 *  gateway's signed word is the evidence money moved) — invalid/missing → 401, no detail.
 *  Every handled outcome returns void (route replies 200) so the gateway stops retrying;
 *  anomalies are FLAGGED in audit for ops instead of erroring into a retry storm. */
export async function handleWebhookEvent(rawBody: string, signature: string | undefined): Promise<void> {
  if (!signature || !paymentGateway.verifyWebhookSignature(rawBody, signature)) {
    throw new UnauthorizedError('Invalid webhook signature');
  }
  const parsed = JSON.parse(rawBody) as { event?: string; payload?: { payment?: { entity?: RazorpayPaymentEntity } } };
  const event = parsed.event ?? 'unknown';
  const entity = parsed.payload?.payment?.entity;

  if (event === 'payment.captured' && entity) {
    const payment = await prisma.payment.findUnique({ where: { razorpayOrderId: entity.order_id } });
    if (!payment) {
      await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'unknown_order', orderId: entity.order_id } } });
      return;
    }
    if (payment.status === 'CAPTURED') return; // duplicate delivery — already handled
    if (entity.amount !== payment.amountPaise) {
      // Tampered/partial capture must NEVER close the booking. Flag loudly, ack quietly.
      await prisma.auditLog.create({
        data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'amount_mismatch', bookingId: payment.bookingId, expectedPaise: payment.amountPaise, gotPaise: entity.amount } },
      });
      return;
    }
    const booking = await prisma.booking.findUniqueOrThrow({ where: { id: payment.bookingId } });
    await prisma.$transaction(async (tx) => {
      await tx.payment.update({ where: { id: payment.id }, data: { status: 'CAPTURED', razorpayPaymentId: entity.id, capturedAt: new Date() } });
      // transitionBooking's optimistic lock makes a concurrent duplicate a 409 → rollback; the
      // status guard above catches the sequential duplicate. Either way: exactly one transition.
      await transitionBooking(tx, booking, 'PAYMENT_RECEIVED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'razorpay-webhook' }, { razorpayPaymentId: entity.id, amountPaise: payment.amountPaise, method: 'UPI' });
    });
    return;
  }

  if (event === 'payment.failed' && entity) {
    await prisma.$transaction(async (tx) => {
      // updateMany keyed on CREATED: a failed event for an already-captured/failed row is a no-op.
      await tx.payment.updateMany({
        where: { razorpayOrderId: entity.order_id, status: 'CREATED' },
        data: { status: 'FAILED', failureReason: entity.error_description ?? 'payment failed' },
      });
      await tx.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'payment_failed', orderId: entity.order_id } } });
    });
    return;
  }

  // Unknown / refund.* (B7 skeleton): acknowledge + audit, take no action.
  await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'ignored', type: event } } });
}
```

- [ ] **Step 4: `webhook.routes.ts`** — raw-body capture scoped to this route via a dedicated content-type parser context:

```ts
import type { FastifyInstance } from 'fastify';
import { handleWebhookEvent } from './webhook.service.js';

/** Gateway webhooks. NO requireAuth — the HMAC signature over the RAW body is the auth.
 *  The raw string must be preserved byte-for-byte for the HMAC, so this plugin scope
 *  re-registers the JSON parser to keep the raw body instead of parsing it. */
export async function registerWebhookRoutes(app: FastifyInstance) {
  await app.register(async (scope) => {
    scope.removeContentTypeParser('application/json');
    scope.addContentTypeParser('application/json', { parseAs: 'string' }, (_req, body, done) => {
      done(null, body); // hand the raw string through as req.body
    });
    scope.post('/webhooks/razorpay', async (req, reply) => {
      await handleWebhookEvent(req.body as string, req.headers['x-razorpay-signature'] as string | undefined);
      return reply.send({ received: true });
    });
  });
}
```

- [ ] **Step 5: Register in `app.ts`** — add `import { registerWebhookRoutes } from './modules/payments/webhook.routes.js';` and `await registerWebhookRoutes(app);` after `registerTechnicianJobRoutes`.

- [ ] **Step 6: Green + full suite + commit**

Run: `pnpm vitest run tests/bookings/payment.test.ts` → PASS (8); `pnpm vitest run` → ALL green (note the count); `pnpm tsc --noEmit` → clean.
> If the full-suite run trips the 100-req/min harness limiter (payment.test.ts's fixtures are inject-heavy), re-run the affected file alone to confirm green — harness artifact, not a product bug.

```bash
git add src/modules/payments src/app.ts tests/bookings/payment.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): Razorpay webhook — signature-authed, amount-verified, duplicate-safe → PAYMENT_RECEIVED"
```

---

### Task 5: Payment in the customer DTO + docs (STATUS/CHANGELOG/decision)

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.types.ts` (+`payment` block)
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (`getBooking`/`listBookings` include)
- Modify: `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md` (final entry: no charge OTP)
- Modify: `STATUS.md`, `CHANGELOG.md`
- Test: extend `apps/backend/tests/bookings/payment.test.ts`

**Interfaces:**
- Produces: `BookingDto.payment: { status: PaymentStatus; method: PaymentMethod; amountPaise: number } | null` (latest attempt by createdAt; no gateway ids).

- [ ] **Step 1: Write the failing test** — append to `payment.test.ts`:

```ts
describe('payment in the customer DTO', () => {
  it('GET /me/bookings/:id shows the latest attempt (no gateway ids leaked)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId, amountPaise } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    await postWebhook(capturedEvent(orderId, amountPaise));
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) })).json();
    expect(got.state).toBe('PAYMENT_RECEIVED');
    expect(got.payment).toEqual({ status: 'CAPTURED', method: 'UPI', amountPaise });
    expect(JSON.stringify(got.payment)).not.toContain('order_');
  });
});
```

- [ ] **Step 2: Verify it fails** (payment undefined), **Step 3: implement** — `bookings.types.ts`: `BookingDto` += `payment: PaymentSummary | null` with `export interface PaymentSummary { status: Payment['status']; method: Payment['method']; amountPaise: number }` (import `Payment` type); `toBookingDto` gains a 5th param `payment: PaymentSummary | null = null`. `getBooking` + `listBookings` include `payments: { orderBy: { createdAt: 'desc' }, take: 1 }` and map `b.payments[0] ? { status, method, amountPaise } : null`. Mutation endpoints keep the default (established partial-DTO convention).

- [ ] **Step 4: Docs.**
  - Decision doc, append: `**Final (2026-07-18, B6a):** no charge-time OTP. The completion OTP (B5) plus the customer's own UPI-app authorization are the two confirmations; a third adds friction without evidence value. Cash (B6b) has its own receipt OTP by design.`
  - `STATUS.md`: Phase + Active task → B6a done on branch (Payment model, gateway wrapper, pay endpoint, webhook, DECLINED visit-fee charge; test count); Next targets → B6b (cash path) then B6c (settlement ledger); note test-keys posture + Razorpay KYC/Route still pending in Blocked-on.
  - `CHANGELOG.md`: new dated entry — first money-moving slice, the full B6a summary (charge sources, idempotency, signature auth, amount verification, duplicate safety, declined-booking charge, B4a-token final resolution).

- [ ] **Step 5: Full suite + typecheck + commit**

Run: `pnpm vitest run` → ALL green (note count); `pnpm tsc --noEmit` → clean.

```bash
git add src/modules/bookings tests/bookings/payment.test.ts docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): payment in customer DTO + B6a docs (decision finalized)"
```

---

## Self-Review

**Spec coverage:** Payment model exact fields + append-only (T1) ✓; PaymentMethod/PaymentStatus enums (T1) ✓; DECLINED_BY_CUSTOMER→PAYMENT_RECEIVED + SYSTEM actor (T1, unit-tested incl. CLOSED default-deny swap) ✓; wrapper interface/lazy creds/timing-safe HMAC/dev signPayload (T2) ✓; optional config keys + env stubs (T2) ✓; chargeAmountFor both states + 409 (T3) ✓; pay idempotency + already-paid 409 + order-before-tx rationale (T3) ✓; declined visit-fee charge (T3 test) ✓; webhook signature-auth 401 / capture→CAPTURED+transition / amount mismatch flagged / duplicate no-op / failed+re-pay new order / unknown+refund ignored (T4) ✓; raw-body scoped parser (T4) ✓; DTO payment block without gateway ids (T5) ✓; decision-doc final entry + STATUS/CHANGELOG (T5) ✓; E2E keystones→pay→webhook (T4 test 1 via confirmedBooking) ✓. No gaps.

**Placeholder scan:** all code steps complete; one flagged degree of freedom (T3's `charge.ts` typing note — prefer the imported BookingState type over the cast) is explicit and bounded. ✓

**Type consistency:** `PaymentGateway`/`DevPaymentGateway`/`paymentGateway`/`signPayload` (T2) used identically in T3/T4 tests; `chargeAmountFor`/`initiatePayment` names match route usage; `handleWebhookEvent(rawBody, signature)` matches the route call; `confirmedBooking` defined T3, reused T4/T5 (same file); `PaymentSummary` defined and consumed in T5; audit metadata keys (`event`, `amountPaise`, `expectedPaise/gotPaise`) consistent between service and tests. ✓
