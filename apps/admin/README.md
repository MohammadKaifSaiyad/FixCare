# apps/admin — FixCare Admin Dashboard

Next.js 14 + shadcn/ui + Tailwind. Web dashboard to run the platform manually
before mobile apps exist (manual job creation, technician KYC verification,
dispute resolution, catalog management, financial reports).

## Build timing
Built **Month 4** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md).
Deploys to `admin.fixcare.in`. Built before the customer/technician apps so ops
can run manually from day one.

## Workspace
Part of the root **pnpm workspace** (see `/pnpm-workspace.yaml`). Consumes API
contract types from `packages/shared-types`.

> Empty scaffold. Actual code lands in the Month 4 build phase.
