# Infrastructure

Containerized, single-VPS to start, scale-ready.

---

## Hosting Strategy by Stage

### Stage 1: Building & Beta (0-100 users)
**Hetzner Cloud — CCX13** (~₹1,250/month)
- 2 dedicated vCPU
- 8 GB RAM
- 80 GB NVMe SSD
- 20 TB traffic
- Run everything via Docker Compose

### Stage 2: Early Growth (100-5,000 users)
**Hetzner CCX23** (~₹2,500/month) + **DigitalOcean Bangalore Managed Postgres**
- API on bigger Hetzner VPS
- Postgres moves to managed service (~₹1,500/month)
- Adds: automated backups, read replicas, point-in-time recovery
- Add Cloudflare CDN (free tier)

### Stage 3: Scale (5,000-50,000 users)
- Multiple Hetzner VPSes (API + workers separated)
- Managed Postgres with read replicas
- Redis Cloud or self-hosted cluster
- Load balancer (Hetzner LB or Cloudflare)
- Consider AWS Mumbai for latency if needed

### Stage 4: Heavy Scale (50,000+ users)
- Migrate to AWS/GCP Mumbai
- Kubernetes (only when truly necessary)
- Microservices split (notifications, payments separated)

**Don't over-build.** Stage 1 handles 10,000+ users with care.

---

## Why Hetzner over AWS/DigitalOcean

| Provider | Cost (2vCPU/8GB) | Performance |
|---|---|---|
| Hetzner CCX13 | ~₹1,250/mo | Dedicated vCPUs, NVMe |
| DO Bangalore Premium | ~₹4,000/mo | Shared vCPUs |
| AWS EC2 t3.large Mumbai | ~₹5,500/mo | Burstable CPUs |

**Hetzner gives 3-5x more compute for the price.**

### Hetzner Downsides
- Data centers in Germany/Finland/US (latency ~150ms to India)
- **Mitigated by:** Cloudflare CDN for static assets, fact that 150ms is fine for app calls

### When to Move Off Hetzner
- Real-time latency becomes critical (live multiplayer-style needs)
- Compliance forces data residency in India
- You have >₹50,000/month infra budget

---

## Docker Compose Architecture

### Services
```yaml
services:
  postgres:        # PostgreSQL 16 + PostGIS
  redis:           # Cache + queues
  api:             # Fastify API server
  websocket:       # Fastify WebSocket server (same image, diff command)
  workers:         # BullMQ workers (same image, diff command)
  caddy:           # Reverse proxy, HTTPS
```

### Single-VPS Layout
```
┌─────────────────────────────────────┐
│        Hetzner VPS (CCX13)          │
│  ┌─────────────────────────────┐    │
│  │       Caddy (80, 443)       │    │
│  └─────────────────────────────┘    │
│         │              │             │
│  ┌──────▼─────┐  ┌────▼────────┐    │
│  │  API:3000  │  │ WS:3001     │    │
│  └──────┬─────┘  └────┬────────┘    │
│         │              │             │
│  ┌──────▼──────────────▼────────┐   │
│  │     Postgres + Redis         │   │
│  └──────────────────────────────┘   │
│  ┌──────────────────────────────┐   │
│  │  Workers (BullMQ consumers)  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
```

### Volume Mounts
- `postgres-data` → persistent Postgres files
- `redis-data` → AOF persistence
- `caddy-data` → SSL certs auto-renewed
- `app-logs` → mounted host directory for log files

---

## Reverse Proxy: Caddy

### Why Caddy over Nginx
- Automatic HTTPS via Let's Encrypt
- Simpler config (Caddyfile vs nginx.conf)
- Built-in HTTP/3 support
- Sensible defaults
- Better error messages

### Caddyfile (Conceptual)
```
api.fixcare.in {
  reverse_proxy api:3000
  encode gzip zstd
  log {
    output file /var/log/caddy/api.log
  }
}

ws.fixcare.in {
  reverse_proxy websocket:3001
}

admin.fixcare.in {
  reverse_proxy admin:3001  # Next.js admin
  basicauth {
    admin <bcrypt-hash>  # Extra layer
  }
}
```

---

## Database: PostgreSQL 16

### Version Choice
- Use 16 (stable, performant, modern features)
- Avoid 17 (too new, plugin compatibility risk) until 2026

### PostGIS Extension
- Required for geospatial queries
- Use `postgis/postgis:16-3.4` Docker image

### Configuration Tweaks
- `shared_buffers` = 25% of RAM (2GB on 8GB VPS)
- `effective_cache_size` = 50% of RAM
- `work_mem` = 16 MB (per connection)
- `maintenance_work_mem` = 512 MB
- `max_connections` = 100 (more than enough for solo + Fastify connection pool)

### Backups
- Daily `pg_dump` via cron
- Upload to Cloudflare R2
- Retain: 30 days daily, 12 months monthly
- Test restore quarterly (or it doesn't count)

### Migration to Managed Postgres (Stage 2)
When traffic warrants:
1. Provision DO Managed Postgres Bangalore
2. Set up logical replication from Hetzner Postgres
3. Cut over during low-traffic window
4. Decommission Hetzner Postgres
5. Total downtime: <5 minutes if done right

---

## Cache: Redis 7

### Use Cases
- OTP storage (5-min TTL)
- Session/refresh token storage
- BullMQ queues
- Rate limiting counters
- Frequently-accessed data caching (technician availability)

### Configuration
- AOF persistence enabled
- Max memory: 1GB (Stage 1)
- Eviction policy: `allkeys-lru`
- Backed up via RDB snapshots

---

## File Storage: Cloudflare R2

### Buckets
- `fixcare-kyc` — Private, signed URL access only
- `fixcare-jobs` — Private, signed URL access
- `fixcare-profile` — Public read, authenticated write
- `fixcare-backups` — Private, server-only access

### CORS Configuration
- KYC bucket: no CORS (server-only)
- Jobs bucket: allow from app domain only
- Profile bucket: allow from any (public read)

### Costs (At Various Scales)
- 10 GB stored: ~₹15/month
- 100 GB stored: ~₹150/month
- 1 TB stored: ~₹1,500/month
- **Bandwidth/egress: FREE** (R2's killer feature)

---

## DNS & Domain

### Setup
- Domain: `fixcare.in` (or chosen)
- DNS: Cloudflare (free)
- Subdomains:
  - `fixcare.in` — landing page (Vercel/Netlify free)
  - `api.fixcare.in` — API
  - `ws.fixcare.in` — WebSocket
  - `admin.fixcare.in` — Admin dashboard
  - `status.fixcare.in` — Status page (Uptime Kuma)

### Cloudflare Features Used (All Free)
- DNS
- Proxy/CDN
- DDoS protection
- WAF rules
- Free SSL (in addition to Caddy's)
- Analytics

---

## CI/CD: GitHub Actions

### Pipeline (Per Push to Main)
1. Lint + type check
2. Run tests
3. Build Docker image
4. Push to GitHub Container Registry
5. SSH to Hetzner → pull new image → docker-compose up

### Deployment Strategy
- Rolling updates via Docker Compose
- Brief downtime acceptable (<10 sec) for V1
- Add zero-downtime later (blue-green or load balancer)

### Secrets Management
- Stage 1: GitHub Actions secrets + Hetzner `.env` files
- Stage 2: Doppler.com (free tier for solo)
- Stage 3: AWS Secrets Manager or HashiCorp Vault

---

## Monitoring

### Uptime: Uptime Kuma (Self-hosted)
- Runs in same Docker Compose stack
- Monitors: API, WebSocket, Admin, DB connection
- Alerts to email, WhatsApp via Gupshup, Telegram

### Errors: Sentry
- Free tier: 5K errors/month (plenty for V1)
- Captures backend + frontend errors
- Stack traces, breadcrumbs, user context

### Logs
- Stage 1: File-based logs, weekly rotation
- Stage 2: Add Better Stack or Grafana Loki
- Stage 3: Datadog or CloudWatch

### Metrics
- Stage 1: Skip (focus on shipping)
- Stage 2: Add Grafana + Prometheus
- Stage 3: Full observability stack

---

## Security Layer

### Firewall
- Hetzner Cloud Firewall enabled
- Allow only: 22 (SSH), 80, 443 (HTTPS), 8080 (admin if needed)
- Block all other inbound
- SSH only via key (passwords disabled)

### SSH Hardening
- Disable root login
- Change default SSH port (security through obscurity, minor benefit)
- Use Fail2ban
- Use Tailscale or WireGuard for admin access (V2)

### Database Security
- Postgres listens only on Docker network (not exposed to host)
- Strong passwords (32-char random)
- Role-based access (app user has limited grants)
- SSL connections within Docker network

### Secrets
- Never in code
- Never in Git
- `.env` files chmod 600
- Production secrets only on production server

---

## Backup Strategy

### What to Back Up
- Postgres database (daily)
- Redis AOF file (daily — for queue continuity)
- R2 buckets (cross-region replication when available)
- Code (Git is the backup)
- Environment configs (encrypted, stored separately)

### Backup Destinations
- Primary: Cloudflare R2 (different bucket)
- Secondary: Backblaze B2 (cross-cloud for safety)
- Tertiary: Local download once weekly (you, manually)

### Restore Drills
- Quarterly: Full restore to a fresh VPS
- Verify: All services start, data intact
- Document: How long it takes (your real RTO)
- **An untested backup is not a backup.**

---

## Disaster Recovery

### Scenarios & Plans

**Scenario: VPS dies**
- RTO: 4 hours
- Spin up new Hetzner VPS, restore Postgres, redeploy Docker
- Update Cloudflare DNS to new IP
- Practiced quarterly

**Scenario: Database corruption**
- RTO: 1 hour
- Restore from latest daily backup
- Data loss: max 24 hours (acceptable for V1)
- For better RPO: hourly backups (Stage 2)

**Scenario: Cloudflare R2 outage**
- Photos can't be uploaded temporarily
- App falls back to "retry later" mode
- Read existing photos via signed URLs (cached)

**Scenario: Razorpay outage**
- Bookings continue, payments queue up
- Show banner: "Payment processing delayed"
- Cash payments unaffected

**Scenario: You get hospitalized**
- Document everything in this docs folder
- Give read access to one trusted person
- Auto-renewal on domains/hosting
- Customer support paused, refund-friendly during outage

---

## Cost Projections (Updated)

| Stage | Monthly Cost |
|---|---|
| 0-3 months (building) | ₹500 – ₹1,500 |
| 4-6 months (more dev) | ₹1,500 – ₹3,500 |
| 7-9 months (beta) | ₹3,500 – ₹6,000 |
| 10-12 months (launch) | ₹8,000 – ₹15,000 |
| Year 2 (1,000 active users) | ₹25,000 – ₹50,000 |
| Year 3 (10,000 active users) | ₹1,00,000 – ₹2,00,000 |

These are infrastructure-only. Add: payment processing (2% Razorpay), KYC (₹10-30 per verification), SMS (₹0.20 per SMS).

---

## Local Development

### Should Mirror Production
- Same Docker Compose stack
- Same Postgres + Redis versions
- Same Caddy reverse proxy (optional locally)
- Different env vars (test API keys)

### Workflow
```bash
# Clone repo
git clone fixcare-api
cd fixcare-api

# Start everything
docker-compose up -d

# Watch logs
docker-compose logs -f api

# Run migrations
docker-compose exec api pnpm prisma migrate dev

# Open Prisma Studio
docker-compose exec api pnpm prisma studio
```

### Dev Helpers
- `Makefile` with common commands
- Seed scripts for test data
- Reset scripts for clean state
