# Auth Module — Sub-slice A (OTP + Registration) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phone-OTP login + registration for Customer/Technician: `POST /auth/otp/send` and `POST /auth/otp/verify`, where verify creates (or finds) the user atomically with its role profile and returns real access + refresh tokens.

**Architecture:** OTP state lives in Redis (5-min TTL, hashed, single-use, attempt-capped, per-phone send rate-limit). On verify, `createUserWithProfile` creates `User` + exactly the matching role profile in one Prisma transaction (the role↔profile invariant guard), writes an `AuditLog`, and issues a short access JWT (HS256) + a hashed `RefreshToken` row. SMS sending is abstracted behind an `OtpSender` interface (dev stub logs + exposes the OTP in non-prod; MSG91 impl is an inert stub until DLT approval).

**Tech Stack:** Node 22, pnpm, Fastify 5, Prisma 6, ioredis, Zod v4, jsonwebtoken, Node `crypto`, Vitest.

**Scope:** Sub-slice A only. The minimal token *issue* is built here (so verify returns tokens), but the **refresh-rotation/reuse-detection endpoint and `requireAuth` middleware are sub-slice B** — clearly seamed below. On branch `feature/auth-otp-registration`.

---

## Shell prerequisite (EVERY command step)

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null   # shell defaults to Node 25
```
Load env (from `apps/backend`): `set -a; . ./.env; set +a`. Work dir: `apps/backend`. ESM/NodeNext → local imports use `.js`. Docker Postgres+Redis must be running. Commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces; never write that literal phrase in a message).

## Existing foundation (sub-slice 0, do NOT recreate)
`src/app.ts` (`buildApp()`), `src/shared/config.ts` (`config`, Zod v4), `src/shared/redis/client.ts` (`redis`), `src/shared/database/prisma.ts` (`prisma`), `src/shared/errors.ts` (`AppError`, `ValidationError`, `UnauthorizedError`, `ForbiddenError`, `NotFoundError`, `TooManyRequestsError`), global error handler, security plugins, `/health`. `tests/schema/helpers.ts` already truncates all 7 tables; `tests/teardown.ts` quits prisma+redis.

## File Structure

```
apps/backend/src/
├── shared/
│   ├── auth/
│   │   ├── tokens.ts              # signAccessToken() (HS256) + issueRefreshToken() (hashed RefreshToken row)
│   │   └── otp.ts                 # generateOtp() + hashOtp() (crypto)
│   └── third-party/
│       └── otp-sender.ts          # OtpSender interface + DevOtpSender + Msg91OtpSender (inert stub) + factory
└── modules/auth/
    ├── auth.schemas.ts            # Zod: sendOtpBody, verifyOtpBody
    ├── auth.service.ts            # sendOtp(), verifyOtp(), createUserWithProfile()
    ├── auth.routes.ts             # registerAuthRoutes(app): POST /auth/otp/send, /auth/otp/verify
    └── auth.types.ts              # UserDto + token result types
tests/
├── helpers/redis.ts               # flushTestRedis() for between-test isolation
└── auth/
    ├── otp-send.test.ts
    └── otp-verify.test.ts
```

`app.ts` is modified once to register the auth routes. Tests live under `tests/auth/`.

---

### Task 1: Install jsonwebtoken + OTP/token crypto helpers

**Files:** Modify `apps/backend/package.json`; Create `apps/backend/src/shared/auth/otp.ts`, `apps/backend/src/shared/auth/tokens.ts`

- [ ] **Step 1: Install jsonwebtoken**

Run (in `apps/backend`, Node 22):
```bash
pnpm add jsonwebtoken
pnpm add -D @types/jsonwebtoken
```
Expected: added to deps/devDeps, no errors.

- [ ] **Step 2: Create the OTP crypto helper**

Create `apps/backend/src/shared/auth/otp.ts`:
```ts
import { createHash, randomInt } from 'node:crypto';

/** A cryptographically-random 6-digit OTP as a string (zero-padded). */
export function generateOtp(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

/** SHA-256 hash of an OTP — we store/compare hashes, never the raw OTP. */
export function hashOtp(otp: string): string {
  return createHash('sha256').update(otp).digest('hex');
}
```

- [ ] **Step 3: Create the token helper**

Create `apps/backend/src/shared/auth/tokens.ts`:
```ts
import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import type { Prisma, UserRole } from '@prisma/client';
import { config } from '../config.js';

export interface AccessClaims {
  sub: string;   // userId
  role: UserRole;
}

/** Sign a short-lived access JWT (HS256). */
export function signAccessToken(userId: string, role: UserRole): string {
  return jwt.sign({ sub: userId, role } satisfies AccessClaims, config.JWT_SECRET, {
    algorithm: 'HS256',
    expiresIn: config.JWT_ACCESS_TTL,
  } as jwt.SignOptions);
}

/** SHA-256 of a refresh token (only the hash is stored). */
export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Issue a new refresh token: returns the raw opaque token (sent to client) and
 * creates the hashed RefreshToken row. `tx` is a Prisma transaction client.
 * NOTE: rotation / reuse-detection / the /auth/refresh endpoint are sub-slice B.
 */
export async function issueRefreshToken(
  tx: Prisma.TransactionClient,
  userId: string,
  meta: { userAgent?: string; ipHash?: string } = {},
): Promise<string> {
  const raw = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + config.REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);
  await tx.refreshToken.create({
    data: { userId, tokenHash: hashRefreshToken(raw), expiresAt, userAgent: meta.userAgent, ipHash: meta.ipHash },
  });
  return raw;
}
```

- [ ] **Step 4: Typecheck**

Run (in `apps/backend`):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
pnpm exec tsc --noEmit
```
Expected: clean. If `jwt.sign`'s `expiresIn` typing complains about `string`, the `as jwt.SignOptions` cast above handles it; report if any other error appears.

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/package.json pnpm-lock.yaml apps/backend/src/shared/auth/ && git commit -m "feat(backend): add OTP + token crypto helpers (jsonwebtoken, HS256 access, hashed refresh)"
```

---

### Task 2: OtpSender interface + dev stub + inert MSG91 stub

**Files:** Create `apps/backend/src/shared/third-party/otp-sender.ts`

- [ ] **Step 1: Create the OtpSender module**

Create `apps/backend/src/shared/third-party/otp-sender.ts`:
```ts
import { config } from '../config.js';

/** Abstraction over OTP delivery. The rest of the code depends on this, not a vendor SDK. */
export interface OtpSender {
  send(phone: string, otp: string): Promise<void>;
}

/** Dev/test sender: logs the OTP. The verify flow is testable because the OTP is
 *  also surfaced in non-prod responses by the service. Never used in production. */
export class DevOtpSender implements OtpSender {
  async send(phone: string, otp: string): Promise<void> {
    // No PII beyond the masked phone tail; OTP printed for local/dev use only.
    console.log(`[DevOtpSender] OTP for ...${phone.slice(-4)} = ${otp}`);
  }
}

/** Real MSG91 sender — INERT until DLT/template approval. Throws if used. */
export class Msg91OtpSender implements OtpSender {
  async send(_phone: string, _otp: string): Promise<void> {
    throw new Error('Msg91OtpSender is not enabled yet (pending DLT/template approval)');
  }
}

/** Factory: dev stub everywhere except production. Swap to MSG91 by config later. */
export function makeOtpSender(): OtpSender {
  return config.NODE_ENV === 'production' ? new Msg91OtpSender() : new DevOtpSender();
}
```
Note: no MSG91_* config keys are added yet — the stub needs none (it throws before using any). They'll be added when MSG91 is actually wired.

- [ ] **Step 2: Typecheck**

```bash
pnpm exec tsc --noEmit
```
Expected: clean.

- [ ] **Step 3: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/third-party/otp-sender.ts && git commit -m "feat(backend): add OtpSender interface + dev stub + inert MSG91 stub"
```

---

### Task 3: Zod schemas + auth types

**Files:** Create `apps/backend/src/modules/auth/auth.schemas.ts`, `apps/backend/src/modules/auth/auth.types.ts`

- [ ] **Step 1: Create the Zod schemas**

Create `apps/backend/src/modules/auth/auth.schemas.ts`:
```ts
import { z } from 'zod';

/** Roles that may self-register via OTP (Merchant/Admin use other paths). */
export const otpRole = z.enum(['CUSTOMER', 'TECHNICIAN']);

const phone = z.string().regex(/^[6-9]\d{9}$/, 'Invalid Indian phone number');

export const sendOtpBody = z.object({ phone, role: otpRole });
export type SendOtpBody = z.infer<typeof sendOtpBody>;

export const verifyOtpBody = z.object({
  phone,
  role: otpRole,
  otp: z.string().regex(/^\d{6}$/, 'OTP must be 6 digits'),
});
export type VerifyOtpBody = z.infer<typeof verifyOtpBody>;
```

- [ ] **Step 2: Create the response types/DTO**

Create `apps/backend/src/modules/auth/auth.types.ts`:
```ts
import type { User } from '@prisma/client';

export interface UserDto {
  id: string;
  role: User['role'];
  status: User['status'];
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  user: UserDto;
}

export function toUserDto(user: User): UserDto {
  return { id: user.id, role: user.role, status: user.status };
}
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/auth.schemas.ts apps/backend/src/modules/auth/auth.types.ts && git commit -m "feat(backend): add auth Zod schemas + UserDto types"
```

---

### Task 4: Redis test helper + the send flow (TDD)

**Files:** Create `apps/backend/tests/helpers/redis.ts`, `apps/backend/src/modules/auth/auth.service.ts` (sendOtp portion), `apps/backend/src/modules/auth/auth.routes.ts`; Modify `apps/backend/src/app.ts`; Create `apps/backend/tests/auth/otp-send.test.ts`

- [ ] **Step 1: Create the Redis test helper**

Create `apps/backend/tests/helpers/redis.ts`:
```ts
import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + rate-limit keys between tests so each test is isolated. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const rl = await redis.keys('otp-rl:*');
  const all = [...keys, ...rl];
  if (all.length) await redis.del(...all);
}
```

- [ ] **Step 2: Write the FAILING send test**

Create `apps/backend/tests/auth/otp-send.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

describe('POST /auth/otp/send', () => {
  it('sends an OTP and returns devOtp in non-prod', async () => {
    const res = await app.inject({
      method: 'POST', url: '/auth/otp/send',
      payload: { phone: '9800000001', role: 'CUSTOMER' },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.ok).toBe(true);
    expect(body.devOtp).toMatch(/^\d{6}$/); // non-prod convenience
  });

  it('rejects an invalid phone with 400', async () => {
    const res = await app.inject({
      method: 'POST', url: '/auth/otp/send',
      payload: { phone: '12345', role: 'CUSTOMER' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rate-limits after 3 sends in the window (429)', async () => {
    const send = () => app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone: '9811111111', role: 'CUSTOMER' } });
    await send(); await send(); await send();
    const fourth = await send();
    expect(fourth.statusCode).toBe(429);
  });
});
```

- [ ] **Step 3: Run, expect FAIL**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/auth/otp-send.test.ts
```
Expected: FAIL — route 404 (not registered yet).

- [ ] **Step 4: Implement the send service (create auth.service.ts with sendOtp)**

Create `apps/backend/src/modules/auth/auth.service.ts`:
```ts
import { redis } from '../../shared/redis/client.js';
import { config } from '../../shared/config.js';
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';
import { TooManyRequestsError } from '../../shared/errors.js';
import { makeOtpSender } from '../../shared/third-party/otp-sender.js';
import type { SendOtpBody } from './auth.schemas.js';

const otpSender = makeOtpSender();

const otpKey = (phone: string) => `otp:${phone}`;
const rlKey = (phone: string) => `otp-rl:${phone}`;

export interface SendOtpResult {
  ok: true;
  devOtp?: string; // present only in non-production
}

export async function sendOtp({ phone, role }: SendOtpBody): Promise<SendOtpResult> {
  // Per-phone send rate-limit: max N per window.
  const count = await redis.incr(rlKey(phone));
  if (count === 1) await redis.expire(rlKey(phone), config.OTP_SEND_WINDOW_SECONDS);
  if (count > config.OTP_MAX_SENDS_PER_WINDOW) {
    throw new TooManyRequestsError('Too many OTP requests. Try again later.');
  }

  const otp = generateOtp();
  await redis.set(
    otpKey(phone),
    JSON.stringify({ hash: hashOtp(otp), attempts: 0, role }),
    'EX', config.OTP_TTL_SECONDS,
  );
  await otpSender.send(phone, otp);

  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: otp };
}
```

- [ ] **Step 5: Create the routes + register them**

Create `apps/backend/src/modules/auth/auth.routes.ts`:
```ts
import type { FastifyInstance } from 'fastify';
import { ValidationError } from '../../shared/errors.js';
import { sendOtpBody } from './auth.schemas.js';
import { sendOtp } from './auth.service.js';

export async function registerAuthRoutes(app: FastifyInstance) {
  app.post('/auth/otp/send', async (request, reply) => {
    const parsed = sendOtpBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await sendOtp(parsed.data);
    return reply.code(200).send(result);
  });
}
```
Modify `apps/backend/src/app.ts` — add the import and registration (after `registerErrorHandler(app);`, before the `/health` route):
```ts
import { registerAuthRoutes } from './modules/auth/auth.routes.js';
```
```ts
  await registerAuthRoutes(app);
```

- [ ] **Step 6: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/otp-send.test.ts
```
Expected: 3 passed (send happy, invalid-phone 400, rate-limit 429).

- [ ] **Step 7: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/auth.service.ts apps/backend/src/modules/auth/auth.routes.ts apps/backend/src/app.ts apps/backend/tests/ && git commit -m "feat(backend): OTP send endpoint (rate-limited, dev OTP in non-prod)"
```

---

### Task 5: Verify flow + find-or-create + invariant guard + token issue (TDD)

**Files:** Modify `apps/backend/src/modules/auth/auth.service.ts` (add verifyOtp + createUserWithProfile), `apps/backend/src/modules/auth/auth.routes.ts` (add verify route); Create `apps/backend/tests/auth/otp-verify.test.ts`

- [ ] **Step 1: Write the FAILING verify tests**

Create `apps/backend/tests/auth/otp-verify.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function sendAndGetOtp(phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const res = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  return res.json().devOtp as string;
}

describe('POST /auth/otp/verify', () => {
  it('new TECHNICIAN: creates User + exactly one Technician profile + returns tokens', async () => {
    const phone = '9800000010';
    const otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.user.role).toBe('TECHNICIAN');

    const user = await prisma.user.findUnique({ where: { phone }, include: { technician: true, customer: true } });
    expect(user?.technician).toBeTruthy();
    expect(user?.customer).toBeNull();           // invariant: no other profile
    const tokens = await prisma.refreshToken.count({ where: { userId: user!.id } });
    expect(tokens).toBe(1);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'USER_REGISTERED', actorId: user!.id } });
    expect(audit).toBeTruthy();
  });

  it('existing user logs in as STORED role (ignores role hint) + audits USER_LOGGED_IN', async () => {
    const phone = '9800000011';
    // register as CUSTOMER
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    // log in again but claim TECHNICIAN — stored role (CUSTOMER) must win
    otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.role).toBe('CUSTOMER');
    const user = await prisma.user.findUnique({ where: { phone }, include: { customer: true, technician: true } });
    expect(user?.customer).toBeTruthy();
    expect(user?.technician).toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'USER_LOGGED_IN', actorId: user!.id } });
    expect(audit).toBeTruthy();
  });

  it('wrong OTP → 401', async () => {
    const phone = '9800000012';
    await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    expect(res.statusCode).toBe(401);
  });

  it('too many wrong attempts (>5) invalidates the OTP → 401', async () => {
    const phone = '9800000013';
    await sendAndGetOtp(phone, 'CUSTOMER');
    for (let i = 0; i < 5; i++) {
      await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    }
    // 6th attempt — even the correct OTP is now gone
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp: '000000' } });
    expect(res.statusCode).toBe(401);
  });

  it('no OTP sent → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone: '9800000014', role: 'CUSTOMER', otp: '123456' } });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/otp-verify.test.ts
```
Expected: FAIL — verify route 404.

- [ ] **Step 3: Add verifyOtp + createUserWithProfile to auth.service.ts**

Append to `apps/backend/src/modules/auth/auth.service.ts`:
```ts
import { prisma } from '../../shared/database/prisma.js';
import type { Prisma, UserRole } from '@prisma/client';
import { UnauthorizedError, ForbiddenError } from '../../shared/errors.js';
import { signAccessToken, issueRefreshToken } from '../../shared/auth/tokens.js';
import { toUserDto, type AuthTokens } from './auth.types.js';
import type { VerifyOtpBody } from './auth.schemas.js';

/** Create a User + exactly the matching role profile, atomically. The ONLY user-creation path. */
export async function createUserWithProfile(tx: Prisma.TransactionClient, phone: string, role: UserRole) {
  const user = await tx.user.create({ data: { phone, role } });
  if (role === 'CUSTOMER') await tx.customer.create({ data: { userId: user.id, name: '' } });
  else if (role === 'TECHNICIAN') await tx.technician.create({ data: { userId: user.id, name: '', skills: [] } });
  else throw new ForbiddenError('Role cannot self-register via OTP');
  return user;
}

export async function verifyOtp({ phone, otp }: VerifyOtpBody): Promise<AuthTokens> {
  const raw = await redis.get(otpKey(phone));
  if (!raw) throw new UnauthorizedError('Invalid or expired OTP');

  const state = JSON.parse(raw) as { hash: string; attempts: number; role: UserRole };

  // attempt cap
  if (state.attempts >= config.OTP_MAX_VERIFY_ATTEMPTS) {
    await redis.del(otpKey(phone));
    throw new UnauthorizedError('Invalid or expired OTP');
  }
  if (hashOtp(otp) !== state.hash) {
    await redis.set(otpKey(phone), JSON.stringify({ ...state, attempts: state.attempts + 1 }), 'KEEPTTL');
    throw new UnauthorizedError('Invalid or expired OTP');
  }

  await redis.del(otpKey(phone)); // single-use

  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.user.findUnique({ where: { phone } });
    let user = existing;
    let isNew = false;
    if (!existing) {
      user = await createUserWithProfile(tx, phone, state.role); // role from the SEND request
      isNew = true;
    } else if (existing.status !== 'ACTIVE' || existing.deletedAt) {
      throw new ForbiddenError('Account is not active');
    }
    await tx.auditLog.create({
      data: {
        action: isNew ? 'USER_REGISTERED' : 'USER_LOGGED_IN',
        actorType: 'USER',
        actorId: user!.id,
      },
    });
    const accessToken = signAccessToken(user!.id, user!.role);
    const refreshToken = await issueRefreshToken(tx, user!.id);
    return { accessToken, refreshToken, user: toUserDto(user!) };
  });

  return result;
}
```
Note: `'KEEPTTL'` preserves the OTP's remaining TTL when bumping the attempt counter (ioredis supports it). The stored `role` (from the original send) is used for new-user creation; the verify request's role hint is NOT trusted for an existing user — its stored role wins.

- [ ] **Step 4: Add the verify route**

Modify `apps/backend/src/modules/auth/auth.routes.ts` — add the import + route inside `registerAuthRoutes`:
```ts
import { sendOtpBody, verifyOtpBody } from './auth.schemas.js';
import { sendOtp, verifyOtp } from './auth.service.js';
```
```ts
  app.post('/auth/otp/verify', async (request, reply) => {
    const parsed = verifyOtpBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await verifyOtp(parsed.data);
    return reply.code(200).send(result);
  });
```

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/otp-verify.test.ts
```
Expected: 5 passed (new technician + invariant, existing logs in as stored role, wrong OTP 401, >5 attempts 401, no-OTP 401).

- [ ] **Step 6: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/ apps/backend/tests/auth/otp-verify.test.ts && git commit -m "feat(backend): OTP verify + find-or-create with role-profile invariant guard + token issue"
```

---

### Task 6: Full suite + boot smoke + docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Run the FULL suite**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: ALL pass — 17 (sub-slice 0) + 3 send + 5 verify = 25.

- [ ] **Step 2: Manual smoke (real server, real Redis/DB)**

```bash
set -a; . ./.env; set +a
pnpm exec tsx src/server.ts > /tmp/fc.log 2>&1 &
SRV=$!; sleep 4
OTP=$(curl -s -XPOST localhost:3000/auth/otp/send -H 'content-type: application/json' -d '{"phone":"9800000099","role":"CUSTOMER"}' | node -e "process.stdin.on('data',d=>console.log(JSON.parse(d).devOtp))")
echo "got OTP: $OTP"
curl -s -XPOST localhost:3000/auth/otp/verify -H 'content-type: application/json' -d "{\"phone\":\"9800000099\",\"role\":\"CUSTOMER\",\"otp\":\"$OTP\"}"; echo
kill $SRV 2>/dev/null
```
Expected: verify returns JSON with `accessToken`, `refreshToken`, `user.role: "CUSTOMER"`.
Cleanup the smoke user afterward (optional): it lives in `fixcare_dev`; harmless.

- [ ] **Step 3: Update STATUS.md**

Set Active task to "Auth sub-slice B (JWT + refresh rotation + requireAuth)" and add to Last shipped:
```
- Auth sub-slice A (OTP + registration): /auth/otp/send + /auth/otp/verify; OtpSender
  dev stub; rate-limit + attempt-cap + single-use OTP; createUserWithProfile invariant
  guard; access JWT + hashed RefreshToken issued on verify. 25 tests green.
```

- [ ] **Step 4: Update CHANGELOG.md** (add under the current date):
```
- **Auth sub-slice A (OTP + registration).** POST /auth/otp/send (per-phone rate-limit,
  dev OTP in non-prod) + POST /auth/otp/verify (single-use, 5-attempt cap, find-or-create
  with the role↔profile invariant guard, AuditLog USER_REGISTERED/USER_LOGGED_IN, issues
  access JWT + hashed refresh token). OtpSender interface (dev stub + inert MSG91). 25 tests.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record auth sub-slice A (OTP + registration)"
```

---

## Definition of Done

- `pnpm test` green: 25 tests (17 prior + 3 send + 5 verify).
- Manual smoke: send→verify returns real tokens for a new customer.
- A new TECHNICIAN gets exactly one Technician profile (no other) — invariant proven by test.
- Existing user logs in as their stored role regardless of the role hint.
- OTP is single-use, 5-attempt-capped, 5-min TTL; sends are rate-limited (429).
- `tsc --noEmit` clean. All commits authored by you, no Claude trailer.

## Seam to sub-slice B (NOT built here)
- `tokens.ts` issues tokens but there is **no `/auth/refresh`, no rotation, no reuse-detection, no `requireAuth`** yet — that is sub-slice B. `issueRefreshToken` deliberately doesn't set `replacedById`/rotation.
- The composite `RefreshToken(userId, expiresAt)` index migration is a sub-slice B item.
- `/auth/logout` + `/auth/logout-all` are sub-slice B.

## Out of scope
Admin login (sub-slice C), MSG91 real sending (inert stub only), profile-detail updates (name/skills), `requireAuth`-protected resources.

## Verification
- `pnpm test` → 25 passed.
- Smoke curl send→verify → tokens returned.
- `git log --oneline main..HEAD` → the sub-slice A commits, all authored by MohammadKaifSaiyad.
