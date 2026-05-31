# Auth Module — Sub-slice 0 (Bootstrap) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Fastify app skeleton — a configured, health-checkable server with typed config, Redis client, security plugins, and a global error handler — that sub-slices A/B/C will build auth onto.

**Architecture:** `buildApp()` (in `src/app.ts`) composes plugins + routes and returns a Fastify instance with no side effects, so tests use `app.inject()` (no real network). `server.ts` calls `buildApp()` + `.listen()`. Config is read once via a Zod-validated `config.ts` that throws at boot if anything is missing/malformed. Redis + Prisma singletons back a `/health` readiness check.

**Tech Stack:** Node 22 LTS, pnpm 9.15.2, Fastify 5, TypeScript strict (ESM/NodeNext), Zod, ioredis, @fastify/helmet, @fastify/cors, @fastify/rate-limit, dotenv, Vitest.

**Scope:** Bootstrap ONLY. NO OTP, JWT, refresh, or admin login (those are sub-slices A/B/C). On branch `feature/auth-module`.

---

## Shell prerequisite (EVERY command step)

Non-interactive shell defaults to Node 25; this project needs Node 22. Prefix commands with:
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
```
Load env for app/tests (from `apps/backend`): `set -a; . ./.env; set +a`.
Working dir for backend commands: `apps/backend`. ESM/NodeNext → local imports use `.js` extensions.
Docker Postgres+PostGIS + Redis must be running (`docker compose ps` from repo root; redis @ localhost:6379, PONG verified). All commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces).

## File Structure

```
apps/backend/
├── package.json                       # + deps, + dev/build/start scripts, + dotenv devDep
├── .env / .env.example                # + NODE_ENV, PORT, REDIS_URL, JWT_SECRET, etc.
├── src/
│   ├── server.ts                      # buildApp() + listen()  (NOT unit-tested)
│   ├── app.ts                         # buildApp(): compose plugins + routes → Fastify instance
│   ├── shared/
│   │   ├── config.ts                  # Zod-validated env → typed `config`; throws at boot
│   │   ├── database/prisma.ts         # (exists)
│   │   ├── redis/client.ts            # ioredis singleton
│   │   ├── errors.ts                  # AppError + typed subclasses
│   │   └── middleware/errorHandler.ts # maps errors → safe HTTP responses
│   └── plugins/
│       └── security.ts                # registers helmet + cors + rate-limit
└── tests/
    ├── config.test.ts                 # fail-fast on missing/invalid env
    ├── health.test.ts                 # GET /health via app.inject() → DB+Redis reachable
    └── error-handler.test.ts          # typed error → correct status + safe body
```

Note: `tests/schema/*` (from the merged slice) stay as-is. New bootstrap tests live directly under `tests/`. The existing `vitest.config.ts` `include: ['tests/**/*.test.ts']` already picks them up.

---

### Task 1: Install dependencies + scripts

**Files:** Modify `apps/backend/package.json`

- [ ] **Step 1: Install runtime + dev deps**

Run (in `apps/backend`, Node 22):
```bash
pnpm add zod ioredis @fastify/helmet @fastify/cors @fastify/rate-limit
pnpm add -D dotenv
```
Expected: added to `dependencies` (zod, ioredis, the three @fastify plugins) and `devDependencies` (dotenv); lockfile updated, no errors.

- [ ] **Step 2: Add dev/build/start scripts**

Edit `apps/backend/package.json` `scripts` to add (keep existing db/test scripts):
```json
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js",
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/package.json pnpm-lock.yaml && git commit -m "chore(backend): add fastify plugins, zod, ioredis, dotenv + run scripts"
```

---

### Task 2: Typed, validated config module (TDD)

**Files:** Create `apps/backend/src/shared/config.ts`, `apps/backend/tests/config.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/config.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { loadConfig } from '../src/shared/config.js';

const base = {
  NODE_ENV: 'test',
  PORT: '3000',
  DATABASE_URL: 'postgresql://fixcare:fixcare_dev@localhost:5432/fixcare_test?schema=public',
  REDIS_URL: 'redis://localhost:6379',
  JWT_SECRET: 'x'.repeat(32),
};

describe('config', () => {
  it('parses a valid environment', () => {
    const c = loadConfig(base);
    expect(c.PORT).toBe(3000); // coerced to number
    expect(c.JWT_SECRET).toHaveLength(32);
  });

  it('throws when JWT_SECRET is missing', () => {
    const { JWT_SECRET, ...without } = base;
    expect(() => loadConfig(without)).toThrow(/JWT_SECRET/);
  });

  it('throws when JWT_SECRET is too short', () => {
    expect(() => loadConfig({ ...base, JWT_SECRET: 'short' })).toThrow(/JWT_SECRET/);
  });
});
```

- [ ] **Step 2: Run the test, expect FAIL**

Run (in `apps/backend`):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/config.test.ts
```
Expected: FAIL — `loadConfig` not found.

- [ ] **Step 3: Implement config.ts**

Create `apps/backend/src/shared/config.ts`:
```ts
import { z } from 'zod';

const ConfigSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET must be at least 32 characters'),
  JWT_ACCESS_TTL: z.string().default('15m'),
  REFRESH_TTL_DAYS: z.coerce.number().int().positive().default(30),
  OTP_TTL_SECONDS: z.coerce.number().int().positive().default(300),
  OTP_MAX_SENDS_PER_WINDOW: z.coerce.number().int().positive().default(3),
  OTP_SEND_WINDOW_SECONDS: z.coerce.number().int().positive().default(900),
  OTP_MAX_VERIFY_ATTEMPTS: z.coerce.number().int().positive().default(5),
});

export type Config = z.infer<typeof ConfigSchema>;

/** Parse + validate an env-like object. Throws a readable error if invalid. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const result = ConfigSchema.safeParse(env);
  if (!result.success) {
    const issues = result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join('; ');
    throw new Error(`Invalid configuration: ${issues}`);
  }
  return result.data;
}

/** The validated, app-wide config. Reading this at import time fails fast at boot. */
export const config = loadConfig();
```
Note: `redis://localhost:6379` must pass `z.string().url()` — it does (valid URL scheme). MSG91_* and SEED_ADMIN_* keys are intentionally NOT in this schema yet (added in sub-slices A/C when used).

- [ ] **Step 4: Run the test, expect PASS**

Run:
```bash
set -a; . ./.env; set +a
pnpm test tests/config.test.ts
```
Expected: 3 passed.
NOTE: because `config.ts` calls `loadConfig()` at import time, the test env (`.env` loaded above) must contain `JWT_SECRET` and `REDIS_URL` — see Task 5 which adds them to `.env`. If this task is run before Task 5, temporarily ensure `JWT_SECRET` (≥32 chars) + `REDIS_URL` are exported. Do Task 5 first if needed; the env keys are independent of the code.

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/config.ts apps/backend/tests/config.test.ts && git commit -m "feat(backend): typed Zod-validated config with fail-fast"
```

---

### Task 3: Redis client singleton + typed errors

**Files:** Create `apps/backend/src/shared/redis/client.ts`, `apps/backend/src/shared/errors.ts`

- [ ] **Step 1: Create the typed error classes**

Create `apps/backend/src/shared/errors.ts`:
```ts
/** Base for all expected, mapped application errors. */
export class AppError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
    readonly code: string,
  ) {
    super(message);
    this.name = new.target.name;
  }
}

export class ValidationError extends AppError {
  constructor(message = 'Validation failed') { super(message, 400, 'VALIDATION_ERROR'); }
}
export class UnauthorizedError extends AppError {
  constructor(message = 'Unauthorized') { super(message, 401, 'UNAUTHORIZED'); }
}
export class ForbiddenError extends AppError {
  constructor(message = 'Forbidden') { super(message, 403, 'FORBIDDEN'); }
}
export class NotFoundError extends AppError {
  constructor(message = 'Not found') { super(message, 404, 'NOT_FOUND'); }
}
export class TooManyRequestsError extends AppError {
  constructor(message = 'Too many requests') { super(message, 429, 'TOO_MANY_REQUESTS'); }
}
```

- [ ] **Step 2: Create the Redis singleton**

Create `apps/backend/src/shared/redis/client.ts`:
```ts
import Redis from 'ioredis';
import { config } from '../config.js';

export const redis = new Redis(config.REDIS_URL, {
  maxRetriesPerRequest: 3,
  lazyConnect: false,
});
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/errors.ts apps/backend/src/shared/redis/client.ts && git commit -m "feat(backend): add typed error classes + Redis client singleton"
```

---

### Task 4: Global error handler + buildApp + security plugins + /health (TDD)

**Files:** Create `apps/backend/src/shared/middleware/errorHandler.ts`, `apps/backend/src/plugins/security.ts`, `apps/backend/src/app.ts`, `apps/backend/src/server.ts`, `apps/backend/tests/health.test.ts`, `apps/backend/tests/error-handler.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `apps/backend/tests/health.test.ts`:
```ts
import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

const app = await buildApp();
afterAll(() => app.close());

describe('GET /health', () => {
  it('returns 200 with db and redis reachable', async () => {
    const res = await app.inject({ method: 'GET', url: '/health' });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.status).toBe('ok');
    expect(body.db).toBe('up');
    expect(body.redis).toBe('up');
  });
});
```
Create `apps/backend/tests/error-handler.test.ts`:
```ts
import { afterAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { ForbiddenError } from '../src/shared/errors.js';

const app = await buildApp();
// register a throwaway route that throws a typed error
app.get('/__boom', async () => { throw new ForbiddenError('nope'); });
afterAll(() => app.close());

describe('global error handler', () => {
  it('maps a typed AppError to its status + safe body', async () => {
    const res = await app.inject({ method: 'GET', url: '/__boom' });
    expect(res.statusCode).toBe(403);
    const body = res.json();
    expect(body.code).toBe('FORBIDDEN');
    expect(body.message).toBe('nope');
    expect(body.stack).toBeUndefined(); // never leak internals
  });

  it('maps an unexpected error to a generic 500', async () => {
    app.get('/__crash', async () => { throw new Error('secret internal detail'); });
    const res = await app.inject({ method: 'GET', url: '/__crash' });
    expect(res.statusCode).toBe(500);
    const body = res.json();
    expect(body.message).not.toContain('secret internal detail'); // no leak
  });
});
```

- [ ] **Step 2: Run the tests, expect FAIL**

Run (in `apps/backend`):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/health.test.ts tests/error-handler.test.ts
```
Expected: FAIL — `buildApp` not found.

- [ ] **Step 3: Implement the error handler**

Create `apps/backend/src/shared/middleware/errorHandler.ts`:
```ts
import type { FastifyInstance, FastifyError, FastifyReply, FastifyRequest } from 'fastify';
import { AppError } from '../errors.js';

export function registerErrorHandler(app: FastifyInstance) {
  app.setErrorHandler((err: FastifyError, _req: FastifyRequest, reply: FastifyReply) => {
    if (err instanceof AppError) {
      return reply.code(err.statusCode).send({ code: err.code, message: err.message });
    }
    // Fastify validation / rate-limit errors carry a statusCode
    if (typeof err.statusCode === 'number' && err.statusCode < 500) {
      return reply.code(err.statusCode).send({ code: err.code ?? 'ERROR', message: err.message });
    }
    app.log.error(err); // log full detail server-side
    return reply.code(500).send({ code: 'INTERNAL_ERROR', message: 'Internal server error' });
  });
}
```

- [ ] **Step 4: Implement the security plugins**

Create `apps/backend/src/plugins/security.ts`:
```ts
import type { FastifyInstance } from 'fastify';
import helmet from '@fastify/helmet';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';

export async function registerSecurity(app: FastifyInstance) {
  await app.register(helmet);
  await app.register(cors, { origin: true });
  await app.register(rateLimit, { max: 100, timeWindow: '1 minute' }); // global per-IP baseline
}
```

- [ ] **Step 5: Implement buildApp + /health**

Create `apps/backend/src/app.ts`:
```ts
import Fastify, { type FastifyInstance } from 'fastify';
import { registerSecurity } from './plugins/security.js';
import { registerErrorHandler } from './shared/middleware/errorHandler.js';
import { prisma } from './shared/database/prisma.js';
import { redis } from './shared/redis/client.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({ logger: false });

  await registerSecurity(app);
  registerErrorHandler(app);

  app.get('/health', async () => {
    let db = 'down';
    let redisState = 'down';
    try { await prisma.$queryRaw`SELECT 1`; db = 'up'; } catch { /* stays down */ }
    try { const pong = await redis.ping(); redisState = pong === 'PONG' ? 'up' : 'down'; } catch { /* stays down */ }
    const status = db === 'up' && redisState === 'up' ? 'ok' : 'degraded';
    return { status, db, redis: redisState };
  });

  return app;
}
```
Create `apps/backend/src/server.ts`:
```ts
import { buildApp } from './app.js';
import { config } from './shared/config.js';

const app = await buildApp();
app
  .listen({ port: config.PORT, host: '0.0.0.0' })
  .then((addr) => console.log(`FixCare API listening on ${addr}`))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
```

- [ ] **Step 6: Run the tests, expect PASS**

Run (Docker Postgres+Redis must be up):
```bash
set -a; . ./.env; set +a
pnpm test tests/health.test.ts tests/error-handler.test.ts
```
Expected: health (1) + error-handler (2) pass. `/health` returns db:up + redis:up.

- [ ] **Step 7: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/ apps/backend/tests/health.test.ts apps/backend/tests/error-handler.test.ts && git commit -m "feat(backend): Fastify buildApp + security plugins + global error handler + /health"
```

---

### Task 5: Wire env keys + full-suite green + manual boot check

**Files:** Modify `apps/backend/.env`, `apps/backend/.env.example`

- [ ] **Step 1: Add the bootstrap env keys to .env**

Append to `apps/backend/.env` (the gitignored real file). Keep the existing DATABASE_URL/TEST_DATABASE_URL:
```
NODE_ENV="development"
PORT="3000"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="dev-only-change-me-min-32-characters-long-secret"
JWT_ACCESS_TTL="15m"
REFRESH_TTL_DAYS="30"
OTP_TTL_SECONDS="300"
OTP_MAX_SENDS_PER_WINDOW="3"
OTP_SEND_WINDOW_SECONDS="900"
OTP_MAX_VERIFY_ATTEMPTS="5"
```

- [ ] **Step 2: Mirror keys in .env.example (placeholders, committed)**

Append to `apps/backend/.env.example`:
```
NODE_ENV="development"
PORT="3000"
REDIS_URL="redis://localhost:6379"
JWT_SECRET="CHANGE_ME_min_32_chars"
JWT_ACCESS_TTL="15m"
REFRESH_TTL_DAYS="30"
OTP_TTL_SECONDS="300"
OTP_MAX_SENDS_PER_WINDOW="3"
OTP_SEND_WINDOW_SECONDS="900"
OTP_MAX_VERIFY_ATTEMPTS="5"
```

- [ ] **Step 3: Run the FULL suite (bootstrap + existing schema tests)**

Run (in `apps/backend`, Node 22, Docker up):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: ALL pass — the 11 schema tests + config (3) + health (1) + error-handler (2) = 17.

- [ ] **Step 4: Manual boot smoke check**

Run (in `apps/backend`):
```bash
set -a; . ./.env; set +a
( pnpm dev & sleep 4; curl -s localhost:3000/health; kill %1 ) 2>/dev/null
```
Expected: prints `{"status":"ok","db":"up","redis":"up"}`. (If `pnpm dev` via tsx watch is awkward to kill, run `pnpm exec tsx src/server.ts` in the background instead.)

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/.env.example && git commit -m "chore(backend): add bootstrap env keys (config, redis, jwt) to .env.example"
```
Note: `.env` is gitignored — do NOT commit it; only `.env.example` is committed.

---

### Task 6: Update docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Update STATUS.md**

Set Active task to "Auth sub-slice A (OTP + registration)" and add to Last shipped:
```
- Auth bootstrap (sub-slice 0): Fastify buildApp + typed config + Redis client +
  security plugins + global error handler + /health. On feature/auth-module.
```

- [ ] **Step 2: Update CHANGELOG.md**

Add under the current date:
```
- **Auth bootstrap (sub-slice 0).** Fastify app skeleton: buildApp()/server.ts,
  Zod-validated fail-fast config, ioredis singleton, typed errors + global error
  handler, helmet/cors/rate-limit, /health (DB+Redis readiness). Tests via app.inject().
```

- [ ] **Step 3: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record auth bootstrap sub-slice"
```

---

## Definition of Done

- `pnpm test` green: 17 tests (11 schema + 3 config + 1 health + 2 error-handler).
- `pnpm dev` boots; `GET /health` returns `{status:"ok",db:"up",redis:"up"}`.
- `config.ts` throws at boot if `JWT_SECRET` missing/short (proven by config test).
- Global error handler maps typed `AppError`→status+code, unexpected→generic 500 (no leak).
- `dotenv` is a devDep; `dev`/`build`/`start` scripts exist; bootstrap env keys in `.env.example`.
- No OTP/JWT/refresh/admin code (those are A/B/C). All commits authored by you, no Claude trailer.

## Out of scope (sub-slices A/B/C)
OTP send/verify, OtpSender, JWT signing/verify, requireAuth, refresh rotation, admin login, seed script, MSG91/SEED env keys. The config schema gains those keys when the consuming sub-slice needs them.

## Verification
- `pnpm test` → 17 passed.
- `curl localhost:3000/health` while `pnpm dev` runs → ok/up/up.
- `git log --oneline main..HEAD` shows the bootstrap commits, all authored by MohammadKaifSaiyad.
