# Coding Conventions

Patterns to enforce in every Claude Code session. `CLAUDE.md` references this file.
Keep these strict — consistency is what keeps a solo, AI-assisted codebase maintainable.

---

## TypeScript / Backend

### Types
- **Strict mode on.** `noUncheckedIndexedAccess` on.
- **Never `any`.** Use `unknown` and narrow with type guards.
- Derive types from Prisma where possible; don't hand-write DB shapes.
- Public API responses use explicit DTO types, not Prisma models.

### Validation
- Every route validates input with a Zod schema in `<feature>.schemas.ts`.
- Infer TS types from Zod (`z.infer`), don't duplicate.
- Validate at the boundary; trust nothing from the client.

### Layering
```
route handler  →  service  →  repository/Prisma
```
- Route handlers: parse/validate input, call service, shape response. No business logic.
- Services: all business logic, orchestration, transactions.
- Repository (optional, for complex queries): Prisma access.
- **Never** call Prisma directly from a route handler.

### Errors
- Throw typed errors (`ValidationError`, `NotFoundError`, `BusinessRuleError`, etc.).
- Global error handler maps them to safe HTTP responses.
- Never leak internal details (stack traces, SQL) to clients.
- Never `catch` and silently ignore. Log every caught error.

### Money
- **Always integer paise.** Never floating point for currency.
- All money math via `shared/utils/currency.ts`.
- Round only at display time, in the client.

### Database
- All schema changes via Prisma migrations (`prisma migrate`), never manual SQL on prod.
- Soft-delete users/financial records (never hard-delete; audit trail).
- PostGIS queries via typed helpers in `shared/geo/`, never inline raw SQL in services.
- Every financial mutation writes an `AuditLog` entry in the same transaction.

### Async
- All async functions have explicit error handling.
- Long/slow/external work goes to a BullMQ queue, never inline in a request.
- Use transactions for any multi-step financial operation.

---

## Security (Audit Every Time)

- Auth check is the **first line** of every protected handler.
- Ownership check after auth: a user accesses only their own resources.
- No secrets in code or git. `.env` only, `.env.example` as template.
- No PII in logs or analytics: phone, UPI VPA, address, Aadhaar, photos.
- Aadhaar masked everywhere except the verified-hash store.
- Rate-limit auth endpoints harder than the rest.
- Webhook handlers verify signatures (Razorpay) before trusting payload.

---

## Inter-Module Rules

- Modules talk via **service calls** or **events**, never cross-module DB queries.
- No importing another module's routes.
- Shared utilities live in `shared/`, not duplicated per module.
- Third-party SDKs wrapped in `shared/third-party/` behind an interface.

---

## Flutter / Mobile

### Architecture
- Feature-first folders (`features/booking/`), not layer-first.
- Each feature: `data/` (repos, models), `domain/` (entities), `presentation/` (screens, providers).
- State management is **Riverpod everywhere** — never mix in Bloc/Provider/GetX.
- Routing is **go_router** with typed routes + deep-link support.

### API & Data
- All network calls go through a Repository; UI never calls dio directly.
- Repositories return domain entities or typed `Failure`, never raw JSON.
- Models use `freezed` + `json_serializable`.

### Photos
- Worker app: **camera only**, gallery disabled.
- Geotag + timestamp at capture.
- Compress to <500 KB before upload.
- Upload via queue with retry; don't block UI on upload.

### Performance
- Test on low-end devices (Redmi 9A class) from Month 3, not just at launch.
- App size budget: <25 MB release APK.
- Lazy-load maps; dispose controllers; profile memory regularly.

### Storage
- Secrets/tokens: `flutter_secure_storage`.
- **Never** browser localStorage patterns; this is native.

---

## Git & Commits

- Commit small and often: working code, refactor, feature, fix, tests — each a commit.
- Conventional commit format:
  ```
  feat(auth): add OTP refresh endpoint
  fix(bookings): handle missing visit-fee zone
  refactor(payments): extract Razorpay client
  test(dispatch): add nearest-worker tests
  docs(api): update auth flow
  chore(deps): bump prisma to 6.1
  ```
- Work on feature branches / worktrees, never directly on main.
- Run `/code-review` before merging.

---

## Testing

- TDD via Superpowers: failing test first, then minimal code.
- **Must have coverage:** payments, ledger math, auth, booking state machine, dispatch.
- **Nice to have:** everything else.
- **Skip in V1:** UI E2E (manual QA), load tests (until scale).
- A test must assert something specific — not just "runs without error."

---

## Documentation Discipline

- New endpoint → update `docs/API.md` (or regenerate from Zod via swagger).
- Decision changed → update the relevant `docs/03-tech-stack/*` file + add `Last updated:` line.
- Major architectural choice → add an ADR in `docs/adrs/`.
- Every session → update `CHANGELOG.md` + the "Current Phase" block in `CLAUDE.md`.

---

## What Claude Code Should Push Back On

If asked to do any of these, raise it rather than comply silently:

- Storing raw Aadhaar or any PII in logs.
- Skipping the audit log on a financial mutation.
- Giving the worker any pricing discretion.
- Letting a job complete without photos or the customer OTP.
- Adding a new framework/library without an ADR.
- Floating-point money math.
- Bypassing the service layer for "just a quick query."
