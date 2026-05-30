---
name: zod-validated-route
description: Use when adding or modifying a Fastify route handler in apps/backend. Templates a route with Zod input validation at the boundary, auth-first + ownership checks, typed-error handling, and DTO mapping (never raw Prisma out). Enforces the non-negotiable route conventions.
---

# Zod-Validated Fastify Route

Every route in `apps/backend` follows this shape. The boundary is where you trust
nothing from the client — validate there, then hand clean data to the service.

## The required shape

```ts
// <feature>.schemas.ts
import { z } from 'zod';

export const createThingBody = z.object({
  // ... fields; trust NOTHING from the client
});
export type CreateThingBody = z.infer<typeof createThingBody>;   // infer, don't duplicate
```

```ts
// <feature>.routes.ts
export async function thingRoutes(app: FastifyInstance) {
  app.post('/v1/things', async (request, reply) => {
    // 1. AUTH — first line of every protected route
    const user = await requireAuth(request);

    // 2. VALIDATE input at the boundary
    const body = createThingBody.parse(request.body);

    // 3. OWNERSHIP — a user may only act on their own resources
    //    (verify ownership inside the service or here; never skip it)

    // 4. Delegate ALL logic to the service (no business logic here)
    const thing = await thingService.create(user.id, body);

    // 5. Map to a DTO — never return the raw Prisma object
    return reply.code(201).send(toThingDto(thing));
  });
}
```

## Non-negotiables (from coding-conventions.md)
- **Validate every input with Zod.** No unvalidated `request.body` / `request.query`.
- **Auth check is the first line** of a protected handler; **ownership check** after.
- **No business logic and no Prisma in the handler** — call the service.
- **Throw typed errors** (`ValidationError`, `NotFoundError`, `BusinessRuleError`);
  the global error handler maps them to safe HTTP responses. Never leak stack/SQL.
- **Never return raw Prisma models** — map to an explicit DTO.
- **No `any`** — `unknown` + narrowing.
- **Rate-limit auth endpoints harder** than the rest.
- **Webhook handlers verify the signature** (e.g. Razorpay) before trusting payload.

## Process
1. Define/extend the Zod schema in `<feature>.schemas.ts`; export the inferred type.
2. Write the failing route test first (`test-driven-development`).
3. Implement the handler in the 5-step shape above.
4. Confirm: auth-first ✓ ownership ✓ Zod-validated ✓ typed errors ✓ DTO out ✓.

> Reference: `docs/05-development/coding-conventions.md` (Validation, Layering, Security).
