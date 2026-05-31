# Design — Auth Module

_Date: 2026-05-31 · Status: approved (pending spec review) · Scope: the service + routes layer for authentication in `apps/backend`_

## Context

The auth + users **schema** slice is merged to `main` (`User`, `RefreshToken`,
`AuditLog`, and the four role profiles). This slice builds the **service + routes**
that make those tables work: phone-OTP login for Customer/Technician, JWT + refresh
rotation, `requireAuth`, and admin email/password login. There is **no Fastify
server yet** (only the Prisma client singleton), so this slice also bootstraps the
app skeleton.

Grounded in: `docs/03-tech-stack/backend-stack.md` (auth flow), `docs/05-development/coding-conventions.md`
(route/service/validation/security rules), `docs/03-tech-stack/third-party-services.md`
(MSG91), the merged schema, and the project skills `zod-validated-route` / `scaffold-module`
/ `third-party-wrapper`. Naming per ADR-0003. Build-order per ADR-0004 (auth is
foundational backend, before apps).

## Decisions locked (during brainstorming)

1. **Scope as one design, built in 4 sub-slices:** 0 bootstrap → A OTP+registration (C/T) →
   B JWT+refresh+middleware → C admin login. Each is its own plan + PR off `main`.
2. **Merchant auth deferred**; merchant stays **WhatsApp + web, no app** (existing decision upheld — no ADR change).
3. **Role at signup:** client declares role (CUSTOMER|TECHNICIAN) at OTP-send. New phone →
   create User + that profile; existing phone → stored role wins (role hint ignored).
4. **OTP delivery via an `OtpSender` interface** (`third-party-wrapper`): dev stub logs + returns
   the OTP in non-prod responses; real `Msg91OtpSender` implemented but inert until DLT approval.
5. **Access JWT:** minimal claims `{ sub, role, iat }`, HS256, 15-min. `requireAuth` verifies then
   **loads the user from DB per request** (rejects suspended/deleted immediately).
6. **Refresh:** opaque token, **only its SHA-256 hash stored** in the Postgres `RefreshToken` table;
   `POST /auth/refresh` rotates (revoke old, issue new, slide expiry +30d); **reuse-detection** on a
   revoked token → revoke all the user's tokens + `AuditLog REFRESH_TOKEN_REUSE_DETECTED` → 401.
7. **OTP security:** per-phone send rate-limit (3/15min + cooldown), max 5 verify attempts, single-use +
   5-min TTL, global per-IP rate-limit on `/auth/*` and a stricter one on `/admin/auth/login`.
8. **Config:** typed Zod-validated `config.ts`, **fail-fast at boot**; declare `dotenv` devDep; add the
   deferred env keys. JWT signing = **HS256 single secret**.
9. **Admin:** email + **argon2id** password, separate `/admin/auth/login`; reuses the same token machinery;
   first admin created by a **seed script** from env. `adminLevel` surfaced but `rbac.ts` mapping deferred.

## Module structure (incl. the bootstrap this slice adds)

```
apps/backend/src/
├── server.ts                      # builds app + listen()
├── app.ts                         # buildApp() — composes plugins+routes (testable, no listen)
├── shared/
│   ├── config.ts                  # Zod-validated env → typed config (throws at boot if invalid)
│   ├── database/prisma.ts         # (exists)
│   ├── redis/client.ts            # Redis singleton (OTP + rate-limit)
│   ├── auth/{jwt.ts, argon2.ts}   # access-JWT sign/verify; admin password hash/verify
│   ├── third-party/otp-sender.ts  # OtpSender interface + DevOtpSender + Msg91OtpSender (inert)
│   ├── errors.ts                  # typed error classes
│   └── middleware/{auth.ts, errorHandler.ts}   # requireAuth + ownership; global error handler
├── plugins/{helmet.ts, cors.ts, rateLimit.ts, sensible.ts}
└── modules/auth/
    ├── auth.routes.ts  auth.service.ts  auth.schemas.ts  auth.types.ts
    └── __tests__/auth.test.ts
```

`buildApp()` is pure composition so tests use `app.inject()` (no network). `server.ts` calls it + `.listen()`.

## Endpoints

| Method | Path | Body → Result |
|---|---|---|
| POST | `/auth/otp/send` | `{ phone, role }` → `{ ok }` (+`devOtp` in non-prod) |
| POST | `/auth/otp/verify` | `{ phone, otp, role }` → `{ accessToken, refreshToken, user }` |
| POST | `/auth/refresh` | `{ refreshToken }` → `{ accessToken, refreshToken }` (rotated) |
| POST | `/auth/logout` | `{ refreshToken }` → revokes it |
| POST | `/auth/logout-all` | (auth) → revokes all the user's refresh tokens |
| POST | `/admin/auth/login` | `{ email, password }` → `{ accessToken, refreshToken, admin }` |
| GET | `/health` | → `{ status, db, redis }` |

## Flows

**OTP send:** validate phone (`/^[6-9]\d{9}$/`) + role → rate-limit (Redis, 3/15min, 429 if exceeded) →
generate random 6-digit OTP → store `otp:{phone}` = `{ hash(otp), attempts:0, role }` TTL 5min →
`otpSender.send` (dev: log + return in non-prod). No phone/OTP in logs.

**OTP verify:** load `otp:{phone}` (absent → 401) → increment attempts (>5 → delete key, 401) →
compare `hash(submitted)` (mismatch → 401) → **delete key (single-use)** → find-or-create user in a
transaction: existing → stored role wins, reject if not ACTIVE; new → `createUserWithProfile(phone, role, tx)`
(**the role↔profile invariant guard** — User + exactly the matching profile, atomic) → `AuditLog`
USER_REGISTERED|USER_LOGGED_IN → issue tokens → return DTO (never raw Prisma).

**Refresh (one transaction):** `hash(submitted)` → find RefreshToken (none → 401) → if `revokedAt!=null`
(**reuse**) revoke all user tokens + AuditLog REFRESH_TOKEN_REUSE_DETECTED → 401; if expired → 401; else
rotate: new RefreshToken (`expiresAt=now+30d`), old `revokedAt=now`,`replacedById=new.id`, new access JWT,
return both. Known impl edge: a brief grace window so a legitimate double-fire isn't treated as reuse.

**requireAuth:** Bearer JWT verify (401) → load User by `sub`, assert ACTIVE + not deleted (401/403) →
`request.user={id,role}`. `assertOwnership(user, resourceUserId)` helper (403) for protected resources.

**Admin login:** validate → find Admin by email (generic 401 for unknown email OR wrong password — no
enumeration) → argon2id verify → assert ACTIVE → issue tokens (same machinery, `role:ADMIN`) →
AuditLog USER_LOGGED_IN (actorType ADMIN) → DTO without `passwordHash`. First admin via `prisma/seed.ts`
from `SEED_ADMIN_EMAIL`/`SEED_ADMIN_PASSWORD`.

## Error contract (global handler → safe responses, no stack/SQL leak)

`ValidationError`→400 · `UnauthorizedError`→401 (bad/expired OTP, bad/expired/reused token, bad admin creds — generic) ·
`ForbiddenError`→403 (suspended/deleted, ownership) · `TooManyRequestsError`→429 · fallback→500 (logged, generic out).

## Config keys (validated at boot)

`NODE_ENV, PORT, DATABASE_URL, TEST_DATABASE_URL, REDIS_URL, JWT_SECRET, JWT_ACCESS_TTL=15m,
REFRESH_TTL_DAYS=30, OTP_TTL_SECONDS=300, OTP_MAX_SENDS_PER_WINDOW=3, OTP_SEND_WINDOW_SECONDS=900,
OTP_MAX_VERIFY_ATTEMPTS=5, MSG91_API_KEY/TEMPLATE_ID/SENDER_ID (inert), SEED_ADMIN_EMAIL/PASSWORD`.
Add `dotenv` devDep; add `dev`/`build`/`start` scripts.

## Schema follow-ups folded in (from the schema-slice review)

- Add composite `@@index([userId, expiresAt])` to `RefreshToken` (small migration, sub-slice B).
- Reuse-detection **behavioral** test (sub-slice B).
- Role↔profile invariant guard implemented in `createUserWithProfile` (sub-slice A).
- `dotenv` devDep + deferred `.env` keys + `dev/build/start` scripts (sub-slice 0).
- `Merchant` smoke test + dynamic-TRUNCATE helper: still deferred (not auth concerns) — carry forward.

## Testing (TDD; needs Postgres `fixcare_test` + a test Redis; `resetDb()` also flushes Redis)

OTP: send→verify happy (new creates User+profile; existing logs in); expired/wrong/too-many→401; rate-limit→429;
invariant (TECHNICIAN→one Technician row, no other profile; no User without profile).
JWT/refresh: verify; requireAuth rejects expired/suspended/deleted; rotate+slide; **reuse replay→401+chain revoked+AuditLog**; logout/logout-all.
Admin: valid login; unknown-email==wrong-password 401; suspended→403; DTO hides passwordHash.
Bootstrap: `/health` OK + DB/Redis reachable; config fails fast on missing JWT_SECRET.
Tests via `app.inject()`; dev OtpSender exposes the OTP to tests.

## Build sequence (4 sub-slices, each own plan + PR off main)

0. **Bootstrap** — app.ts/server.ts, config.ts, Redis client, errors + handler, security plugins, /health, scripts, dotenv. (depends: nothing)
1. **A — OTP + registration** — OtpSender + dev stub, send/verify, createUserWithProfile guard, first token issue. (depends: 0)
2. **B — JWT + refresh + middleware** — token service, requireAuth + ownership, refresh rotation + reuse-detection, logout/logout-all, composite-index migration. (depends: A)
3. **C — Admin login** — argon2id, /admin/auth/login, seed script. (depends: 0 + B)

## Out of scope (explicit)

Merchant auth; admin/merchant account-creation endpoints (seed only for admin); `rbac.ts` permission
mapping; profile-detail updates (name/skills/KYC/bank); real MSG91 sending (inert until DLT); WebSocket auth;
the apps. Each is a later slice/phase.

## Next step

writing-plans for **sub-slice 0 (bootstrap)** first — the others follow as their own plans.
