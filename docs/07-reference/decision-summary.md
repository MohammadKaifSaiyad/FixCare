# Decision Summary (One Page)

Every locked decision in one place. For reasoning, follow the linked doc.

---

## Product

| Decision | Choice |
|---|---|
| Market | Vadodara + Padra, home appliance repair + electrical |
| Actors | Customer, Worker, Merchant |
| Pricing | Visit fee (₹149/₹99) + catalog labor + catalog parts |
| Visit fee | Credited toward labor if repair done; kept only on cancel |
| Worker pricing discretion | None (catalog only) |
| Parts (V1) | Preferred-merchant routing, NOT bidding |
| Payment default | UPI; cash is friction-added exception |
| Trust | Two scores: Service Trust (public) + Cash Compliance (internal) |
| Cash limit | Graduated ₹500 → ₹5000 by tenure/rating; ₹3000/24h velocity cap |
| Merchant settlement | T+1 |
| Worker payout | T+2 (after dispute window) |
| Warranty | 7-day same-issue rework free |
| Name | FixCare / FixCare Pro / FixCare Partner |

Detail: `02-product/`, `01-overview/`.

---

## Scope

| In V1 | Out of V1 (deferred) |
|---|---|
| Android customer + worker apps | iOS (V2) |
| Admin dashboard (web) | Dedicated merchant app (V2) |
| Merchant via WhatsApp + web | Merchant bidding auctions (V2) |
| Geofenced labor pricing | OCR bill scanning (V2) |
| 3-photo evidence + OTP handshakes | AMC plans (V1.5) |
| UPI + cash + trust meter | Scrap resale (V3) |
| Rules-based fraud engine | ML fraud detection (V2) |

---

## Tech Stack

| Layer | Choice | Why (short) |
|---|---|---|
| Mobile | Flutter (Android only) | One codebase, near-native, AI-friendly |
| Backend | Node 22 + Fastify 5 + TS | Mid-complexity sweet spot, real-time, AI examples |
| ORM/DB | Prisma 6 + Postgres 16 + PostGIS | Type-safe, portable, geospatial |
| Cache/Queue | Redis 7 + BullMQ | Standard, reliable |
| Validation | Zod | One source for types + runtime validation |
| Auth | OTP + JWT (argon2id admin) | Full control, secure |
| Realtime | Fastify WebSocket | Built-in, fast |
| Storage | Cloudflare R2 | No egress fees |
| Containers | Docker Compose | Dev = prod |
| Proxy | Caddy | Auto HTTPS |
| Hosting | Hetzner | 3-5x cheaper than AWS |
| Admin | Next.js + shadcn/ui | Standard, fast |
| Payments | Razorpay + Route | Only viable India option |
| KYC | Setu + Karza | Best India coverage |
| Push/SMS/WhatsApp | OneSignal / MSG91 / Gupshup | Easy / cheap / BSP |
| Maps | Google Maps | $200/mo free credit |
| IDE | Claude Code + Superpowers | Brainstorm+dev+debug+test in one |

Detail + rejected alternatives: `03-tech-stack/stack-decisions.md`.

---

## Architecture

| Decision | Choice |
|---|---|
| Pattern | Modular monolith (V1 + V2) |
| Hosting | Single Hetzner VPS → scale out later |
| DB | Single Postgres, no premature sharding |
| Realtime | WebSocket only for live data; REST for the rest |
| Background | BullMQ for all async/external work |
| Files | R2 with pre-signed direct uploads |

Detail: `04-architecture/system-architecture.md`.

---

## Claude Code Setup

| Item | Choice |
|---|---|
| Primary tool | Claude Code |
| Subscription | Start Pro, upgrade to Max if hitting limits |
| Day-1 plugins | superpowers, code-review, typescript-lsp, postgres MCP, github MCP |
| Methodology | Superpowers lifecycle (brainstorm→plan→TDD→review) |
| Keystone file | Root `CLAUDE.md` (auto-read) |

Detail: `05-development/vibe-coding-workflow.md`.

---

## Timeline & Budget

| Item | Estimate |
|---|---|
| Realistic V1 timeline | 12-18 months solo (10 is best-case) |
| V1 cash budget | ₹60k-1.5L (mostly designer + KYC + legal) |
| Infra at launch | ₹8k-15k/month |
| Daily work cap | 6 hours, Sundays off |

Detail: `05-development/build-sequence.md`, `assumptions-and-doubts.md`.

---

## Top 5 Risks (Memorize)

1. Android background location (OEM battery killing) — budget extra time
2. Razorpay Route approval delay — apply day 1
3. Cash-handling RBI/GST exposure — legal review before Month 6
4. Worker disintermediation — design stickiness, accept partial loss
5. Solo burnout — ship less but working

Detail: `05-development/assumptions-and-doubts.md`.
