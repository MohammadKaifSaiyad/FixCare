# 06-operations

Operational documentation — runbooks, monitoring, security, backups, incident
response. These grow as the platform becomes real (Month 2+ once deployed).

## What belongs here
- `security-checklist.md` — OWASP top-10 review, pre-launch security gate (Month 11)
- `monitoring.md` — Sentry, PostHog, uptime, alerting setup
- `backups-and-recovery.md` — backup schedule + restore-drill runbook
- `runbooks/` — "what to do when X breaks" (DB down, Razorpay webhook failing, etc.)

> Currently a stub. Until these files exist, operational detail lives inside
> `docs/03-tech-stack/infrastructure.md` (security, monitoring, backups, costs).
