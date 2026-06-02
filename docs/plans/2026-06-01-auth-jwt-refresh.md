# Auth Module — Sub-slice B (JWT verify + refresh rotation + requireAuth) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the session lifecycle: a `requireAuth` middleware that gates protected routes, a `/auth/refresh` endpoint that rotates refresh tokens with reuse-detection, and logout / logout-all.

**Architecture:** `verifyAccessToken` validates the HS256 JWT; `requireAuth` then loads the user from DB per request (rejecting suspended/deleted) and attaches a typed `request.user`. `/auth/refresh` runs in one Prisma transaction: a presented **revoked** token triggers reuse-detection (revoke all the user's tokens + audit), otherwise the token rotates (old revoked + linked to new, new issued with a fresh sliding expiry). Tokens are stored only as hashes.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, ioredis, jsonwebtoken (HS256), Zod v4, Vitest.

**Scope:** Sub-slice B only. Admin login is sub-slice C. On branch `feature/auth-jwt-refresh`.

---

## Shell prerequisite (EVERY command step)
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null   # shell defaults to Node 25
```
Load env (from `apps/backend`): `set -a; . ./.env; set +a`. Work dir: `apps/backend`. ESM/NodeNext → local imports use `.js`. Docker Postgres+Redis running. Commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces; never write that literal phrase in a message).

## Existing foundation (sub-slices 0 + A on main — do NOT recreate)
- `src/shared/auth/tokens.ts`: `signAccessToken(userId, role)`, `hashRefreshToken(token)`, `issueRefreshToken(tx, userId, meta?)` → returns `string` (raw token). **Task 1 refactors `issueRefreshToken` to also return the row id.**
- `src/modules/auth/auth.service.ts`: `sendOtp`, `verifyOtp`, `createUserWithProfile` (verifyOtp calls `issueRefreshToken(tx, user.id)` and uses its return as `refreshToken`).
- `src/modules/auth/auth.routes.ts`: `registerAuthRoutes(app)` with `/auth/otp/send` + `/auth/otp/verify`.
- `src/shared/errors.ts`: `UnauthorizedError`, `ForbiddenError`, `ValidationError`. `src/shared/database/prisma.ts`: `prisma`.
- Prisma `RefreshToken`: `tokenHash @unique`, `expiresAt`, `revokedAt?`, `replacedById? @unique` + self-relation, `userAgent?`, `ipHash?`, `@@index([userId])`, `@@index([expiresAt])`.
- Tests: `tests/schema/helpers.ts` (`prisma`, `resetDb`), `tests/helpers/redis.ts` (`flushTestRedis`).

## File Structure

```
apps/backend/src/
├── shared/
│   ├── auth/tokens.ts            # + verifyAccessToken(); refactor issueRefreshToken → {raw,id}; + rotateRefreshToken()
│   └── middleware/auth.ts        # NEW: requireAuth preHandler + assertOwnership + Fastify type augmentation
└── modules/auth/
    ├── auth.service.ts           # + refreshTokens(), logout(), logoutAll(); update verifyOtp caller
    ├── auth.schemas.ts           # + refreshBody, logoutBody
    └── auth.routes.ts            # + POST /auth/refresh, /auth/logout, /auth/logout-all
prisma/
└── migrations/<ts>_refresh_token_composite_index/   # @@index([userId, expiresAt])
tests/auth/
├── require-auth.test.ts          # NEW
├── refresh.test.ts               # NEW
└── logout.test.ts                # NEW
```

---

### Task 1: verifyAccessToken + refactor issueRefreshToken to return the row id

**Files:** Modify `apps/backend/src/shared/auth/tokens.ts`, `apps/backend/src/modules/auth/auth.service.ts`

- [ ] **Step 1: Add verifyAccessToken + refactor issueRefreshToken in tokens.ts**

Modify `apps/backend/src/shared/auth/tokens.ts`:
- Add `UnauthorizedError` import: change the top imports to include it:
```ts
import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';
import type { Prisma, UserRole } from '@prisma/client';
import { config } from '../config.js';
import { UnauthorizedError } from '../errors.js';
```
- Add `verifyAccessToken` (after `signAccessToken`):
```ts
/** Verify an access JWT (HS256). Throws UnauthorizedError on any invalid/expired token. */
export function verifyAccessToken(token: string): AccessClaims {
  try {
    const decoded = jwt.verify(token, config.JWT_SECRET, { algorithms: ['HS256'] });
    if (typeof decoded === 'string' || !decoded.sub || !('role' in decoded)) {
      throw new UnauthorizedError('Invalid token');
    }
    return { sub: String(decoded.sub), role: (decoded as { role: UserRole }).role };
  } catch (err) {
    if (err instanceof UnauthorizedError) throw err;
    throw new UnauthorizedError('Invalid or expired token');
  }
}
```
- Refactor `issueRefreshToken` to return both the raw token and the new row id (rotation needs the id):
```ts
export interface IssuedRefreshToken {
  raw: string;   // sent to the client
  id: string;    // RefreshToken row id (for rotation linking)
}

/** Create a new refresh-token row (hashed) with a sliding 30d expiry. Returns the raw token + row id. */
export async function issueRefreshToken(
  tx: Prisma.TransactionClient,
  userId: string,
  meta: { userAgent?: string; ipHash?: string } = {},
): Promise<IssuedRefreshToken> {
  const raw = randomBytes(32).toString('base64url');
  const expiresAt = new Date(Date.now() + config.REFRESH_TTL_DAYS * 24 * 60 * 60 * 1000);
  const row = await tx.refreshToken.create({
    data: { userId, tokenHash: hashRefreshToken(raw), expiresAt, userAgent: meta.userAgent, ipHash: meta.ipHash },
  });
  return { raw, id: row.id };
}
```

- [ ] **Step 2: Update the existing caller in auth.service.ts (verifyOtp)**

In `apps/backend/src/modules/auth/auth.service.ts`, find the line in `verifyOtp` that does:
```ts
    const refreshToken = await issueRefreshToken(tx, user!.id);
```
Change it to use the new shape:
```ts
    const { raw: refreshToken } = await issueRefreshToken(tx, user!.id);
```

- [ ] **Step 3: Typecheck + confirm the existing suite still passes**

Run (in `apps/backend`):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
pnpm exec tsc --noEmit
set -a; . ./.env; set +a
pnpm test
```
Expected: tsc clean; 25 tests still pass (the verifyOtp refactor is behavior-preserving).

- [ ] **Step 4: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/auth/tokens.ts apps/backend/src/modules/auth/auth.service.ts && git commit -m "refactor(backend): verifyAccessToken + issueRefreshToken returns row id (for rotation)"
```

---

### Task 2: requireAuth middleware + ownership helper (TDD)

**Files:** Create `apps/backend/src/shared/middleware/auth.ts`, `apps/backend/tests/auth/require-auth.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/auth/require-auth.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';

const app = await buildApp();
// test-only protected route
app.get('/__me', { preHandler: [requireAuth] }, async (req) => ({ id: req.user!.id, role: req.user!.role }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function registerAndGetAccess(phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role, otp } });
  return verify.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('requireAuth', () => {
  it('allows a valid access token and attaches request.user', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000040', 'CUSTOMER');
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(200);
    expect(res.json().id).toBe(user.id);
    expect(res.json().role).toBe('CUSTOMER');
  });

  it('rejects a missing token with 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/__me' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects a garbage token with 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: 'Bearer not-a-jwt' } });
    expect(res.statusCode).toBe(401);
  });

  it('rejects a suspended user with 403', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000041', 'CUSTOMER');
    await prisma.user.update({ where: { id: user.id }, data: { status: 'SUSPENDED' } });
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(403);
  });

  it('rejects a soft-deleted user with 401', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000042', 'CUSTOMER');
    await prisma.user.update({ where: { id: user.id }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/auth/require-auth.test.ts
```
Expected: FAIL — `requireAuth` not found.

- [ ] **Step 3: Implement the middleware**

Create `apps/backend/src/shared/middleware/auth.ts`:
```ts
import type { FastifyReply, FastifyRequest } from 'fastify';
import type { UserRole } from '@prisma/client';
import { verifyAccessToken } from '../auth/tokens.js';
import { prisma } from '../database/prisma.js';
import { UnauthorizedError, ForbiddenError } from '../errors.js';

// Make request.user typed across the app.
declare module 'fastify' {
  interface FastifyRequest {
    user?: { id: string; role: UserRole };
  }
}

/** Fastify preHandler: verify Bearer JWT, load the user, reject suspended/deleted. */
export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new UnauthorizedError('Missing bearer token');
  const claims = verifyAccessToken(header.slice('Bearer '.length));

  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user || user.deletedAt) throw new UnauthorizedError('Invalid token');
  if (user.status !== 'ACTIVE') throw new ForbiddenError('Account is not active');

  request.user = { id: user.id, role: user.role };
}

/** Throw if the authenticated user does not own the target resource. */
export function assertOwnership(user: { id: string }, resourceUserId: string): void {
  if (user.id !== resourceUserId) throw new ForbiddenError('You do not have access to this resource');
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/require-auth.test.ts
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/middleware/auth.ts apps/backend/tests/auth/require-auth.test.ts && git commit -m "feat(backend): requireAuth middleware + assertOwnership (per-request user load)"
```

---

### Task 3: rotateRefreshToken helper + /auth/refresh with reuse-detection (TDD)

**Files:** Modify `apps/backend/src/shared/auth/tokens.ts`, `apps/backend/src/modules/auth/auth.service.ts`, `apps/backend/src/modules/auth/auth.schemas.ts`, `apps/backend/src/modules/auth/auth.routes.ts`; Create `apps/backend/tests/auth/refresh.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/auth/refresh.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function register(phone: string) {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role: 'CUSTOMER' } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
  return verify.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('POST /auth/refresh', () => {
  it('rotates a valid refresh token (new tokens; old revoked + linked)', async () => {
    const { refreshToken, user } = await register('9800000050');
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.refreshToken).not.toBe(refreshToken);

    const rows = await prisma.refreshToken.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'asc' } });
    expect(rows.length).toBe(2);
    expect(rows[0]!.revokedAt).not.toBeNull();        // old revoked
    expect(rows[0]!.replacedById).toBe(rows[1]!.id);   // linked to new
    expect(rows[1]!.revokedAt).toBeNull();             // new active
  });

  it('reused (revoked) token → 401 + ALL user tokens revoked + audit', async () => {
    const { refreshToken, user } = await register('9800000051');
    await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } }); // rotates; original now revoked
    const replay = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } }); // reuse original
    expect(replay.statusCode).toBe(401);

    const active = await prisma.refreshToken.count({ where: { userId: user.id, revokedAt: null } });
    expect(active).toBe(0); // whole chain nuked
    const audit = await prisma.auditLog.findFirst({ where: { action: 'REFRESH_TOKEN_REUSE_DETECTED', subjectId: user.id } });
    expect(audit).toBeTruthy();
    expect(audit!.actorType).toBe('SYSTEM');
  });

  it('unknown token → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: 'nope' } });
    expect(res.statusCode).toBe(401);
  });

  it('expired token → 401', async () => {
    const { refreshToken, user } = await register('9800000052');
    await prisma.refreshToken.updateMany({ where: { userId: user.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/refresh.test.ts
```
Expected: FAIL — `/auth/refresh` route 404.

- [ ] **Step 3: Add the refresh schema**

In `apps/backend/src/modules/auth/auth.schemas.ts`, append:
```ts
export const refreshBody = z.object({ refreshToken: z.string().min(1) });
export type RefreshBody = z.infer<typeof refreshBody>;

export const logoutBody = z.object({ refreshToken: z.string().min(1) });
export type LogoutBody = z.infer<typeof logoutBody>;
```

- [ ] **Step 4: Add refreshTokens() to auth.service.ts**

Append to `apps/backend/src/modules/auth/auth.service.ts` (the `prisma`, `issueRefreshToken`, `hashRefreshToken`, `signAccessToken`, `UnauthorizedError` are already imported from Task 1/sub-slice A — add `hashRefreshToken` to the tokens import and `RefreshBody` to the schemas import if not present):
```ts
import { hashRefreshToken } from '../../shared/auth/tokens.js';
import type { RefreshBody } from './auth.schemas.js';

export async function refreshTokens({ refreshToken }: RefreshBody): Promise<{ accessToken: string; refreshToken: string }> {
  const tokenHash = hashRefreshToken(refreshToken);

  return prisma.$transaction(async (tx) => {
    const existing = await tx.refreshToken.findUnique({ where: { tokenHash } });
    if (!existing) throw new UnauthorizedError('Invalid refresh token');

    // Reuse-detection: a revoked token presented again = theft signal.
    if (existing.revokedAt) {
      await tx.refreshToken.updateMany({
        where: { userId: existing.userId, revokedAt: null },
        data: { revokedAt: new Date() },
      });
      await tx.auditLog.create({
        data: { action: 'REFRESH_TOKEN_REUSE_DETECTED', actorType: 'SYSTEM', subjectId: existing.userId },
      });
      throw new UnauthorizedError('Invalid refresh token');
    }

    if (existing.expiresAt < new Date()) throw new UnauthorizedError('Invalid refresh token');

    // Rotate: issue a new token, revoke + link the old one.
    // NOTE: a legitimate near-simultaneous double-fire could present the same token
    // twice; we accept the rare re-login rather than add a grace window in V1.
    const user = await tx.user.findUniqueOrThrow({ where: { id: existing.userId } });
    const { raw, id: newId } = await issueRefreshToken(tx, existing.userId);
    await tx.refreshToken.update({ where: { id: existing.id }, data: { revokedAt: new Date(), replacedById: newId } });
    const accessToken = signAccessToken(user.id, user.role);
    return { accessToken, refreshToken: raw };
  });
}
```
(Ensure `signAccessToken` and `issueRefreshToken` are imported in this file — they are, from sub-slice A's token-issue in verifyOtp.)

- [ ] **Step 5: Add the route**

In `apps/backend/src/modules/auth/auth.routes.ts` — update imports + add the route inside `registerAuthRoutes`:
```ts
import { sendOtpBody, verifyOtpBody, refreshBody } from './auth.schemas.js';
import { sendOtp, verifyOtp, refreshTokens } from './auth.service.js';
```
```ts
  app.post('/auth/refresh', async (request, reply) => {
    const parsed = refreshBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await refreshTokens(parsed.data);
    return reply.code(200).send(result);
  });
```

- [ ] **Step 6: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/refresh.test.ts
```
Expected: 4 passed (rotate, reuse→401+revoke-all+audit, unknown→401, expired→401).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/ apps/backend/tests/auth/refresh.test.ts && git commit -m "feat(backend): /auth/refresh rotation with reuse-detection"
```

---

### Task 4: logout + logout-all (TDD)

**Files:** Modify `apps/backend/src/modules/auth/auth.service.ts`, `apps/backend/src/modules/auth/auth.routes.ts`; Create `apps/backend/tests/auth/logout.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/auth/logout.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function register(phone: string) {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role: 'CUSTOMER' } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
  return verify.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('logout', () => {
  it('POST /auth/logout revokes the presented refresh token', async () => {
    const { refreshToken, user } = await register('9800000060');
    const res = await app.inject({ method: 'POST', url: '/auth/logout', payload: { refreshToken } });
    expect(res.statusCode).toBe(200);
    const row = await prisma.refreshToken.findFirst({ where: { userId: user.id } });
    expect(row!.revokedAt).not.toBeNull();
    // the revoked token can no longer refresh
    const refresh = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(refresh.statusCode).toBe(401);
  });

  it('POST /auth/logout-all revokes ALL the authed user\\'s tokens', async () => {
    const { accessToken, refreshToken, user } = await register('9800000061');
    // create a 2nd active token via a refresh
    await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    const res = await app.inject({ method: 'POST', url: '/auth/logout-all', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(200);
    const active = await prisma.refreshToken.count({ where: { userId: user.id, revokedAt: null } });
    expect(active).toBe(0);
  });

  it('POST /auth/logout-all without a token → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/logout-all' });
    expect(res.statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/logout.test.ts
```
Expected: FAIL — routes 404.

- [ ] **Step 3: Add logout + logoutAll to auth.service.ts**

Append to `apps/backend/src/modules/auth/auth.service.ts` (add `LogoutBody` to the schemas import):
```ts
import type { LogoutBody } from './auth.schemas.js';

/** Revoke a single refresh token (idempotent — no error if already gone/revoked). */
export async function logout({ refreshToken }: LogoutBody): Promise<void> {
  const tokenHash = hashRefreshToken(refreshToken);
  await prisma.refreshToken.updateMany({ where: { tokenHash, revokedAt: null }, data: { revokedAt: new Date() } });
}

/** Revoke all of a user's active refresh tokens ("log out all devices"). */
export async function logoutAll(userId: string): Promise<void> {
  await prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
}
```

- [ ] **Step 4: Add the routes**

In `apps/backend/src/modules/auth/auth.routes.ts` — update imports + add routes. Add the `requireAuth` import and the logout schema/service:
```ts
import { sendOtpBody, verifyOtpBody, refreshBody, logoutBody } from './auth.schemas.js';
import { sendOtp, verifyOtp, refreshTokens, logout, logoutAll } from './auth.service.js';
import { requireAuth } from '../../shared/middleware/auth.js';
```
```ts
  app.post('/auth/logout', async (request, reply) => {
    const parsed = logoutBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    await logout(parsed.data);
    return reply.code(200).send({ ok: true });
  });

  app.post('/auth/logout-all', { preHandler: [requireAuth] }, async (request, reply) => {
    await logoutAll(request.user!.id);
    return reply.code(200).send({ ok: true });
  });
```

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/logout.test.ts
```
Expected: 3 passed.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/ apps/backend/tests/auth/logout.test.ts && git commit -m "feat(backend): /auth/logout + /auth/logout-all"
```

---

### Task 5: Composite RefreshToken index migration

**Files:** Modify `apps/backend/prisma/schema.prisma`; Create `apps/backend/prisma/migrations/<ts>_refresh_token_composite_index/`

- [ ] **Step 1: Add the composite index to the schema**

In `apps/backend/prisma/schema.prisma`, in the `RefreshToken` model, alongside the existing `@@index([userId])` and `@@index([expiresAt])`, add:
```prisma
  @@index([userId, expiresAt])
```
(Keep the existing two indexes — the composite serves the `WHERE userId = ? AND expiresAt > now()` lookup + the per-user purge.)

- [ ] **Step 2: Create + apply the migration to the dev DB**

Run (in `apps/backend`, Node 22, env loaded — targets `DATABASE_URL` = fixcare_dev):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm exec prisma migrate dev --name refresh_token_composite_index
```
Expected: a new migration folder with a single `CREATE INDEX "RefreshToken_userId_expiresAt_idx" ...`, applied cleanly. **Adding an index is non-destructive — NO reset should be prompted.** If `prisma migrate dev` prompts to RESET the database, STOP and report it (do NOT pass the dangerous-action consent or reset) — that would indicate unexpected drift to investigate.

- [ ] **Step 3: Verify the index exists**

Run (from repo root):
```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "\di RefreshToken_userId_expiresAt_idx"
```
Expected: lists the index.

- [ ] **Step 4: Regenerate client + run full suite**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare/apps/backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
pnpm exec prisma generate
set -a; . ./.env; set +a
pnpm test
```
Expected: all pass — 25 (prior) + 5 require-auth + 4 refresh + 3 logout = 37.

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/prisma/ && git commit -m "feat(backend): composite RefreshToken(userId, expiresAt) index"
```

---

### Task 6: Full suite + smoke + docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full suite (confirm 37)**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare/apps/backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: 37 passed.

- [ ] **Step 2: Smoke — register → refresh → reuse → 401**

```bash
set -a; . ./.env; set +a
pnpm exec tsx src/server.ts > /tmp/fc-b.log 2>&1 &
SRV=$!; sleep 4
J=$(curl -s -XPOST localhost:3000/auth/otp/send -H 'content-type: application/json' -d '{"phone":"9800000088","role":"CUSTOMER"}')
OTP=$(node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).devOtp))" <<<"$J")
RT=$(curl -s -XPOST localhost:3000/auth/otp/verify -H 'content-type: application/json' -d "{\"phone\":\"9800000088\",\"role\":\"CUSTOMER\",\"otp\":\"$OTP\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).refreshToken))")
echo "first refresh:" && curl -s -o /dev/null -w "%{http_code}\n" -XPOST localhost:3000/auth/refresh -H 'content-type: application/json' -d "{\"refreshToken\":\"$RT\"}"
echo "replay (reuse) should be 401:" && curl -s -o /dev/null -w "%{http_code}\n" -XPOST localhost:3000/auth/refresh -H 'content-type: application/json' -d "{\"refreshToken\":\"$RT\"}"
kill $SRV 2>/dev/null
```
Expected: first refresh `200`, replay `401`. Then clean up the smoke user from fixcare_dev:
```bash
docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "DELETE FROM \"AuditLog\" WHERE \"subjectId\" IN (SELECT id FROM \"User\" WHERE phone='9800000088'); DELETE FROM \"RefreshToken\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE phone='9800000088'); DELETE FROM \"Customer\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE phone='9800000088'); DELETE FROM \"User\" WHERE phone='9800000088';"
```

- [ ] **Step 3: Update STATUS.md** — Active task → "Auth sub-slice C (admin login)"; add to Last shipped:
```
- Auth sub-slice B (JWT + refresh + requireAuth): requireAuth middleware + ownership;
  /auth/refresh rotation with reuse-detection (revoke-all + audit); /auth/logout +
  /auth/logout-all; composite RefreshToken(userId,expiresAt) index. 37 tests green.
```

- [ ] **Step 4: Update CHANGELOG.md** (under the current date):
```
- **Auth sub-slice B (JWT + refresh rotation + requireAuth).** `requireAuth` preHandler
  (verify HS256 JWT → load user → reject suspended/deleted → typed request.user) +
  `assertOwnership`. `POST /auth/refresh` rotates the refresh token (old revoked + linked
  to new, sliding 30d) with reuse-detection (a revoked token replayed → revoke all the
  user's tokens + AuditLog REFRESH_TOKEN_REUSE_DETECTED → 401). `/auth/logout` +
  `/auth/logout-all`. Composite RefreshToken(userId,expiresAt) index. 37 tests.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record auth sub-slice B (JWT + refresh + requireAuth)"
```

---

## Definition of Done

- `pnpm test` green: 37 tests (25 prior + 5 require-auth + 4 refresh + 3 logout).
- Smoke: register → refresh `200` → replay `401`.
- `requireAuth` rejects missing/garbage/expired tokens (401) and suspended (403) / deleted (401) users; attaches typed `request.user`.
- `/auth/refresh` rotates (old revoked + `replacedById` linked, new active, sliding expiry); reuse → 401 + all user tokens revoked + `REFRESH_TOKEN_REUSE_DETECTED` audit.
- `/auth/logout` revokes one; `/auth/logout-all` (auth-gated) revokes all.
- Composite index present in `fixcare_dev`; `tsc --noEmit` clean. All commits authored by you, no Claude trailer.

## Seam to sub-slice C (NOT built here)
Admin email/password login (`/admin/auth/login`, argon2id), admin seed script. `requireAuth` is built here and admins will reuse it (their JWT carries `role: ADMIN`); the admin-level permission mapping (`rbac.ts`) stays deferred.

## Out of scope
Admin login (C); MSG91 real sending; profile-detail updates; protecting real resource routes (only a test-only `/__me` exercises requireAuth here); concurrency grace-window for refresh (noted, intentionally not built).

## Verification
- `pnpm test` → 37 passed.
- `\di RefreshToken_userId_expiresAt_idx` lists the index.
- `git log --oneline main..HEAD` → the sub-slice B commits, all authored by MohammadKaifSaiyad.
