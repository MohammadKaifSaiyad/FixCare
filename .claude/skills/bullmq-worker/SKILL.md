---
name: bullmq-worker
description: Use when adding or modifying a background job in apps/backend — notifications, payment webhooks, KYC calls, settlements, trust-score recalc, async dispatch. Templates a BullMQ queue + worker with idempotency, retry/backoff, and no-PII payloads. Backend only — Flutter apps use in-app retry queues, NOT BullMQ.
---

# BullMQ Worker (FixCare backend)

Move slow, external, or scheduled work off the request path. The stack locks
**Redis 7 + BullMQ** (`docs/03-tech-stack/backend-stack.md`). This is a Node library
and runs **inside `apps/backend` only**.

> **Scope note:** Flutter apps (`customer`, `technician`) do NOT use BullMQ. When an
> app needs deferred work (e.g. retry a photo upload), that is an **in-app retry
> queue** — see the `camera-evidence-capture` and `api-repository` skills. Do not
> reference BullMQ in app code.

## Pattern

```ts
// shared/queue/queues.ts — define the queue
export const notificationsQueue = new Queue('notifications', { connection: redis });

// modules/<feature>/<feature>.events.ts — typed job names
export const NOTIFY_JOB = 'notify' as const;

// workers/notifications.worker.ts — the worker
new Worker('notifications', async (job) => {
  // 1. IDEMPOTENT: jobs can run more than once — guard on a dedupe key / DB state
  if (await alreadyProcessed(job.data.dedupeKey)) return;
  // 2. do the work; NO PII in job.data (no phone/VPA/address/Aadhaar/photos)
  await sendPush(job.data.userId, job.data.templateId);
}, {
  connection: redis,
  // 3. retry with backoff for transient failures
});
// enqueue with: removeOnComplete, attempts, backoff: { type: 'exponential', delay }
```

## Non-negotiables
- **Idempotent.** A job may be delivered/retried more than once — guard against double
  effects (especially money: never double-pay/charge).
- **No PII in job payloads** — pass IDs, not phone/VPA/address/Aadhaar/photo bytes
  (Golden Rule 7). Resolve PII inside the worker from the DB if needed.
- **Retry/backoff** for transient failures; **dead-letter / alert** on permanent ones.
- **Don't do money mutations in a non-idempotent worker** — combine with
  `audit-logged-mutation`; verify the evidence gate still holds at run time.
- Webhook-triggered workers (Razorpay) only after **signature verification** at the route.
- One worker file per concern under `workers/` (see `module-structure.md`).

## Process
1. Define the queue in `shared/queue/`, job-name constant in `<feature>.events.ts`.
2. Write the worker with the idempotency guard first; test the double-delivery case.
3. Enqueue from the service (never block the request on the work).
4. Wire into `workers/index.ts`.

> Reference: `docs/03-tech-stack/backend-stack.md`, `docs/04-architecture/module-structure.md` (Workers), `docs/05-development/coding-conventions.md` (Async), Golden Rule 7.
