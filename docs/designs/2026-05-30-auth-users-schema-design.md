# Design — Auth + Users Schema Slice

_Date: 2026-05-30 · Status: approved (pending spec review) · Scope: first vertical slice of `prisma/schema.prisma`_

## Context

First real backend feature. This is the **auth + users vertical slice** of the Prisma
schema — the entities the first endpoints (OTP login, registration, refresh) need:
a base `User`, persisted refresh tokens, the four role profiles, and a minimal
append-only audit log. Heavier concerns (KYC, bank/deposit, trust scores, the service
catalog) are deliberately **deferred to their own future slices** and appear here only
as commented seams.

Grounded in: `CLAUDE.md` (Golden Rules), `docs/05-development/coding-conventions.md`,
`docs/03-tech-stack/backend-stack.md` (auth flow), `docs/04-architecture/module-structure.md`,
`docs/02-product/trust-system.md`. Naming follows ADR-0003 (Technician, not Worker).

## Decisions locked (during brainstorming)

1. **Base `User` + separate 1:1 role-profile tables** (Approach A: unique `userId` FK on each profile).
2. **One role per phone**, fixed at registration (`User.role` single enum).
3. **`RefreshToken` persisted in Postgres** (rotation-aware, hashed); **OTPs live in Redis** (5-min TTL, not in the schema).
4. **Role profiles = identity + status only**; KYC / bank / deposit / trust deferred.
5. **Admin** authenticates by **email + argon2id password** (not phone-OTP); `passwordHash` on the Admin profile.
6. **Soft-delete (`deletedAt`)** on `User` + all profiles; `RefreshToken` is **hard-expired**.
7. **Admin sub-roles** via an extensible **`adminLevel` enum** (SUPER_ADMIN/MANAGER/SUPPORT); the `rbac.ts` level→action mapping is deferred to the admin build (#4).
8. **Refresh expiry is sliding 30-day** — renewed on each rotation; active users rarely re-OTP (near-zero SMS cost).
9. **Minimal append-only `AuditLog`** included now so auth/user events are audited from day one (foundation for Golden Rule 5 in financial slices).

## Auth-cost note (why OTP, not passwords)

OTP is sent only at first login / after 30 days dormant — with the sliding 30-day refresh
token, a typical user triggers ~1 SMS/month, so cost at V1 scale (~130 users) is ~₹20/month.
Phone is the identity in this marketplace (dispatch, handshakes, notifications all need a
verified number); passwords for C/T/M would not even save SMS (resets need it) and weaken
fraud defenses. Admins use passwords because they're few and web-based. Decision: keep
OTP + sliding refresh; do not switch C/T/M to passwords.

## Models

### Base User + enums

```prisma
model User {
  id            String     @id @default(uuid())
  phone         String     @unique          // E.164; sole login identity for C/T/M
  role          UserRole                     // fixed at registration; one role per phone
  status        UserStatus @default(ACTIVE)  // platform-level (distinct from per-role status)
  createdAt     DateTime   @default(now())
  updatedAt     DateTime   @updatedAt
  deletedAt     DateTime?                     // soft-delete; queries filter deletedAt: null

  customer      Customer?
  technician    Technician?
  merchant      Merchant?
  admin         Admin?
  refreshTokens RefreshToken[]
}

enum UserRole   { CUSTOMER  TECHNICIAN  MERCHANT  ADMIN }
enum UserStatus { ACTIVE  SUSPENDED }
```

### RefreshToken (hashed, sliding, rotation-aware)

```prisma
model RefreshToken {
  id           String        @id @default(uuid())
  userId       String
  user         User          @relation(fields: [userId], references: [id])
  tokenHash    String        @unique          // SHA-256 of the opaque token; raw token never stored
  expiresAt    DateTime                         // sliding: pushed +30d on each rotation
  createdAt    DateTime      @default(now())
  revokedAt    DateTime?                        // set on rotation-out or logout
  replacedById String?       @unique            // rotation chain → enables reuse detection
  replacedBy   RefreshToken? @relation("TokenRotation", fields: [replacedById], references: [id])
  previous     RefreshToken? @relation("TokenRotation")
  userAgent    String?                          // coarse client descriptor
  ipHash       String?                          // hashed IP, never raw (PII rule)

  @@index([userId])
  @@index([expiresAt])
}
```

Notes: store only the **hash**; rotation revokes the old token and links `replacedById`;
presenting a **revoked** token = theft signal → revoke the whole chain + write
`REFRESH_TOKEN_REUSE_DETECTED` audit. Enables "log out all devices" (reason for DB
persistence over Redis-only). Hard-expired by a cleanup job; no `deletedAt`.

### Role profiles (Approach A — identity + status only)

```prisma
model Customer {
  id        String         @id @default(uuid())
  userId    String         @unique
  user      User           @relation(fields: [userId], references: [id])
  name      String
  status    CustomerStatus @default(ACTIVE)
  createdAt DateTime       @default(now())
  updatedAt DateTime       @updatedAt
  deletedAt DateTime?
  // addresses, bookings → future slices
}

model Technician {
  id        String           @id @default(uuid())
  userId    String           @unique
  user      User             @relation(fields: [userId], references: [id])
  name      String
  skills    ServiceSkill[]                       // coarse enum; real catalog = services/ slice
  status    TechnicianStatus @default(PENDING)
  createdAt DateTime         @default(now())
  updatedAt DateTime         @updatedAt
  deletedAt DateTime?
  // KYC (aadhaarLast4, PAN, DigiLocker ref) → kyc/ slice
  // bank / UPI / ₹500 deposit → wallet/ slice
  // serviceTrust / cashCompliance → trust-scores/ slice
}

model Merchant {
  id        String         @id @default(uuid())
  userId    String         @unique
  user      User           @relation(fields: [userId], references: [id])
  shopName  String
  status    MerchantStatus @default(PENDING)
  createdAt DateTime       @default(now())
  updatedAt DateTime       @updatedAt
  deletedAt DateTime?
  // GST / license / PAN → kyc/ or merchant-catalog/ slice
}

model Admin {
  id           String      @id @default(uuid())
  userId       String      @unique
  user         User        @relation(fields: [userId], references: [id])
  name         String
  email        String      @unique            // admins log in by email + password
  passwordHash String                          // argon2id — admins ONLY
  adminLevel   AdminLevel  @default(SUPPORT)
  status       AdminStatus @default(ACTIVE)
  createdAt    DateTime    @default(now())
  updatedAt    DateTime    @updatedAt
  deletedAt    DateTime?
}

enum CustomerStatus   { ACTIVE  SUSPENDED }
enum TechnicianStatus { PENDING  KYC_SUBMITTED  VERIFIED  SUSPENDED  DEACTIVATED }
enum MerchantStatus   { PENDING  VERIFIED  SUSPENDED }
enum AdminLevel       { SUPER_ADMIN  MANAGER  SUPPORT }   // extensible; rbac.ts maps level→actions later
enum AdminStatus      { ACTIVE  SUSPENDED }
enum ServiceSkill     { AC  FAN  ELECTRICAL  WIRING  APPLIANCE }  // coarse placeholder
```

### Minimal append-only AuditLog

```prisma
model AuditLog {
  id        String      @id @default(uuid())
  action    AuditAction
  actorType ActorType
  actorId   String?                       // null for SYSTEM
  subjectId String?                       // entity the action targets
  metadata  Json?                         // small, PII-FREE context only
  createdAt DateTime    @default(now())

  @@index([actorId])
  @@index([subjectId])
  @@index([action])
  @@index([createdAt])
}

enum ActorType   { USER  ADMIN  SYSTEM }
enum AuditAction {
  USER_REGISTERED
  USER_LOGGED_IN
  USER_SUSPENDED
  USER_REACTIVATED
  ADMIN_LEVEL_CHANGED
  REFRESH_TOKEN_REUSE_DETECTED
  // financial actions (PAYMENT_CAPTURED, PAYOUT_ISSUED, …) added in their slices
}
```

Append-only by convention: the app only ever `create`s rows — no update/delete path, no
`deletedAt`. Shape is ready for financial slices to extend (per the `audit-logged-mutation` skill).

## Cross-cutting rules

- **Soft-delete:** `deletedAt` on `User` + all profiles; never hard-delete; queries filter
  `deletedAt: null` (app-layer + tests). `RefreshToken` hard-expired (cleanup job).
- **PII (Golden Rules 6-7):** this slice holds minimal PII — `phone`, `name`, admin `email`.
  No Aadhaar/PAN/bank here. `RefreshToken` uses `ipHash` (hashed) + coarse `userAgent`. No PII
  in logs/analytics (the `golden-rules-auditor` agent checks diffs).
- **Indexes/uniques:** `User.phone`, `Admin.email`, each profile `userId`, `RefreshToken.tokenHash`,
  `RefreshToken.replacedById` unique; `@@index` on `RefreshToken.userId`/`expiresAt` + `AuditLog` lookups.
- **Role↔profile invariant** (`role = TECHNICIAN` ⇒ exactly one matching profile) is
  **application-enforced** (service guard + test) — not expressible declaratively here.
- **Naming/migration:** Technician/TECHNICIAN (ADR-0003); logical `// ===` section headers
  (AUTH / USERS & ROLES / AUDIT); created via `prisma migrate dev`; migration reviewed by the
  `prisma-migration-reviewer` agent; root `package.json` pins `"packageManager": "pnpm@9.15.2"`.

## PII & traceability (carry-forward to the kyc/ slice)

**Store the proof and the pointer, not the document.** No raw Aadhaar is ever stored. The
kyc/ slice will store `aadhaarLast4`, the **Setu/DigiLocker verification reference**
(`kycReferenceId`), verified name, and verification date. Full-identity resolution (for
legal/fraud cases) goes back to the licensed KYC provider via that reference — keeping
Aadhaar liability off-platform while preserving traceability. Admin PII visibility is
**scoped by `adminLevel`** and **masked by default** (full value only on a specific screen,
sufficient privilege); phone is visible to support/managers, masked for low-privilege staff.
KYC alone doesn't prove honesty (borrowed/stolen IDs) — behavioral defenses (₹500 deposit,
trust scores, two-sided handshakes, photo evidence) layer on top. **Open item for the admin
slice:** whether viewing full PII is itself audit-logged.

## Testing posture (TDD, written first at implementation)

Tests for: (a) one-role-per-phone uniqueness, (b) role↔profile guard, (c) soft-delete
filtering, (d) refresh-token rotation + reuse-detection, (e) sliding-expiry renewal,
(f) audit rows written for register/login/suspend/admin-level-change.

## Out of scope (explicit)

OTP storage (Redis, not schema); KYC fields; bank/UPI/deposit; trust scores; service
catalog/pricing; addresses; bookings; the `rbac.ts` permission mapping; actual route/service
code. Those are later slices/phases.

## Next step

writing-plans → break this into TDD-sized tasks (scaffold `apps/backend` + Prisma, then the
models + invariant tests). `apps/backend` is currently an empty folder; scaffolding it
(package.json, Fastify, Prisma init) is the first implementation task.
