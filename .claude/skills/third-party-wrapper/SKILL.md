---
name: third-party-wrapper
description: Use when integrating a vendor SDK/API in apps/backend — Razorpay, MSG91, Setu, Karza, OneSignal, Gupshup. Templates a wrapper behind shared/third-party/ with a typed interface, typed errors, webhook signature verification, and no secrets in code. Keeps vendor lock-in and fallbacks contained.
---

# Third-Party Wrapper (FixCare backend)

Every external vendor is wrapped behind an interface in `shared/third-party/` so the
rest of the codebase depends on **our** abstraction, not the vendor SDK. Makes
fallbacks, testing, and vendor swaps tractable.

## Pattern

```ts
// shared/third-party/razorpay.ts
export interface PaymentGateway {
  createOrder(input: CreateOrderInput): Promise<OrderResult>;   // domain types, not SDK types
  verifyWebhookSignature(rawBody: string, signature: string): boolean;
}

class RazorpayGateway implements PaymentGateway {
  // secrets ONLY from env (process.env) — never hardcoded, never in git
  async createOrder(input) {
    try { /* call SDK */ }
    catch (e) { throw new ThirdPartyError('razorpay', e); }   // typed error, no raw leak
  }
  verifyWebhookSignature(rawBody, signature) { /* HMAC compare */ }
}

export const paymentGateway: PaymentGateway = new RazorpayGateway();
```

## Non-negotiables (coding-conventions.md Security + Inter-Module)
- **One wrapper per vendor** in `shared/third-party/`; the rest of the code imports the
  **interface**, never the SDK directly.
- **No secrets in code or git** — env only, with `.env.example` as the template.
- **Webhook handlers verify the signature** before trusting any payload (Razorpay etc.).
- **Typed errors** (`ThirdPartyError`) — never leak vendor stack traces/response bodies
  to clients or logs; **no PII** in logs (phone/VPA/Aadhaar).
- **Map vendor responses to domain types** — don't let SDK shapes leak outward.
- **Fallback awareness:** `third-party-services.md` documents fallbacks (e.g. SMS
  provider) — the interface should make swapping a provider a config change.
- Slow calls go through a BullMQ worker, not inline in a request (see `bullmq-worker`).

## Process
1. Define the domain interface first (inputs/outputs in OUR types).
2. Implement the vendor class; secrets from env; wrap errors as `ThirdPartyError`.
3. For webhooks: signature-verify in the route before the handler trusts the body.
4. Unit-test against the interface with the SDK mocked.

> Reference: `docs/05-development/coding-conventions.md` (Inter-Module, Security), `docs/03-tech-stack/third-party-services.md`.
