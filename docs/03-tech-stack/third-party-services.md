# Third-Party Services

External services we depend on, with setup notes and fallback plans.

---

## Service Matrix

| Category | Primary | Fallback | Free Tier |
|---|---|---|---|
| Payments | Razorpay | Cashfree | Setup free, 2% per transaction |
| SMS/OTP | MSG91 | Twilio | ₹100 credits |
| WhatsApp | Gupshup | Wati | Free BSP |
| KYC (Aadhaar) | Setu | IDfy | Free trial |
| KYC (PAN) | Karza | Signzy | Free trial |
| Maps | Google Maps | Mapbox | $200/mo credit |
| Push | OneSignal | Direct FCM | 10K subscribers free |
| Email | Brevo | AWS SES | 300/day free |
| Crash | Sentry | — | 5K events/month |
| Analytics | PostHog | — | 1M events/month |
| Uptime | Uptime Kuma (self) | BetterStack | Free self-hosted |

---

## Payments: Razorpay

### Why Razorpay
- Best India coverage
- UPI Intent works perfectly
- Razorpay Route enables split payments (customer → merchant + technician + platform)
- Webhook reliability
- Test mode is excellent

### Setup
1. Apply at razorpay.com → KYC (takes 3-5 days)
2. Provide:
   - Business PAN
   - Bank account
   - GST registration
   - Business address proof
3. Generate API keys (test + live)
4. Configure webhooks: payment.captured, payment.failed, refund.processed

### Critical Integrations
- **UPI Intent** for customer payments
- **Razorpay Route** for splitting payments to merchant + platform
- **AutoPay** for visit fee authorization
- **Refunds API** for dispute resolutions
- **Webhooks** for payment status updates

### Razorpay Route Setup
- Create linked accounts for each merchant
- Configure split percentages per booking
- Settlement happens automatically (T+1 to merchant)
- Platform gets the remainder

### Test Mode
- Use test keys during all development
- Test cards: 4111 1111 1111 1111 (success), 5104 0600 0000 0008 (failure)
- Test UPI: success@razorpay
- Switch to live keys only post-Razorpay-approval

### Fallback: Cashfree
- Similar feature set
- Sometimes used as secondary processor for redundancy
- Don't integrate V1, just know it exists

---

## SMS/OTP: MSG91

### Why MSG91
- Cheapest for India
- Reliable delivery
- DLT compliance built-in
- Good Node.js library

### Setup
1. Sign up at msg91.com
2. Complete DLT registration (mandatory in India)
3. Get sender ID approved (e.g., "FIXCARE")
4. Create OTP template, get template ID approved
5. Buy SMS credits (₹0.20 per SMS typically)

### Critical: DLT Compliance
- Telecom Regulatory Authority requires registration
- Template-based SMS only
- Pre-approved sender IDs only
- Non-compliance = SMS gets blocked
- Setup takes 5-7 days, do it early

### Templates Needed
- OTP for customer login
- OTP for technician login
- OTP for customer arrival confirmation
- OTP for job completion
- Cash payment confirmation
- Job dispatched notification

### Backup: Twilio
- Globally reliable
- Higher cost in India (~₹0.50 per SMS)
- Use as failover only

---

## WhatsApp: Gupshup

### Why Gupshup
- Official WhatsApp BSP
- Indian company, India-focused pricing
- Good API
- Template message support

### Use Cases
- Merchant notifications (parts request, payout confirmation)
- Booking confirmations to customer (richer than SMS)
- Job updates with images (technician arrival selfie)

### Setup
1. Apply at gupshup.io
2. WhatsApp Business API approval (takes 2-3 weeks)
3. Get template messages pre-approved
4. Setup webhooks for incoming messages

### Important
- WhatsApp templates are pre-approved only
- Free-form replies allowed only within 24h of customer message
- Templates cost ₹0.50-1 per message typically

---

## KYC: Setu + Karza

### Setu (For Aadhaar via DigiLocker)

**Why Setu**
- Direct DigiLocker integration
- Aadhaar pulled from government source (not user upload)
- Fast onboarding
- Compliant with UIDAI guidelines

**Cost:** ₹3-10 per verification

**Flow:**
1. User taps "Verify with DigiLocker"
2. Redirected to DigiLocker → consent screen
3. Returns to app with verified Aadhaar data
4. Backend stores verified hash, never the actual number

### Karza (For PAN + Video KYC)

**Why Karza**
- Best Indian KYC API coverage
- PAN verification via NSDL
- Video KYC for high-trust technicians
- Bank account verification
- GST verification (merchants)

**Cost:** ₹10-30 per verification

**Use Cases:**
- PAN verification for technicians + merchants
- Bank account validation (penny drop)
- Video KYC for senior trust tier
- GST validation for merchants

### Verification Storage
- Never store raw Aadhaar in database
- Store: name, masked Aadhaar (XXXX-XXXX-1234), DOB, address
- Photos encrypted in R2
- Verification status + timestamp + vendor reference ID

### Privacy
- Comply with DPDP Act (India's data protection law)
- User consent before each KYC call
- Right to deletion (subject to legal retention requirements)
- Audit log of all KYC accesses

---

## Maps: Google Maps Platform

### APIs Used
- **Maps SDK for Android** (display maps)
- **Geocoding API** (address → coordinates)
- **Distance Matrix API** (time/distance between points)
- **Places API** (address autocomplete)

### Cost
- $200/month free credit (covers ~28K map loads)
- Per-request pricing after
- Set up billing alerts at $100, $150, $180

### Optimization
- Cache geocoding results aggressively
- Cluster markers when many shown
- Don't render map if not visible
- Use static maps for previews/history

### Fallback: Mapbox
- Similar feature set
- More generous free tier (50K loads/month)
- API slightly different (some refactoring needed)
- Keep credentials ready as backup

---

## Push Notifications: OneSignal

### Why OneSignal
- Easier than raw Firebase Cloud Messaging
- Free tier: 10K subscribers
- Segmentation built-in
- Cross-platform when iOS launches
- A/B testing

### Setup
1. Create OneSignal app
2. Configure Firebase project (OneSignal uses FCM under the hood)
3. Add OneSignal SDK to Flutter apps
4. Set up backend integration via OneSignal API

### Notification Types
- **Booking confirmation** (to customer)
- **Job assignment** (to technician, high priority)
- **Technician en route** (to customer)
- **Technician arrived** (to customer)
- **Diagnosis ready** (to customer)
- **Payment received** (to technician)
- **Settlement processed** (to merchant)
- **Dispute resolution** (to relevant party)

### Tagging Strategy
- Tag users with: role, city, language, last_active
- Enables targeted campaigns (e.g., "All Vadodara customers")

### Fallback: Direct FCM
- Cheaper at scale
- Less feature-rich
- More code to write
- Migrate at 50K+ users if cost matters

---

## Email: Brevo (Formerly Sendinblue)

### Use Cases
- Receipts to customers (booking + payment)
- Admin notifications (high-priority alerts)
- Technician onboarding emails
- Merchant settlement reports

### Why Brevo
- 300 emails/day free
- Indian-friendly
- Good deliverability
- API simple

### Email Templates
- Booking receipt
- Payment confirmation
- Technician onboarding welcome
- Merchant settlement summary
- Dispute resolution notice
- Account suspension notice

### Backup: AWS SES
- Pay-per-use (~₹0.10 per 1000 emails)
- Better deliverability
- Switch when >9K emails/month

---

## Crash Reporting: Sentry

### Setup
- Free tier: 5K errors/month
- One project for backend
- Separate projects for customer + technician apps
- Configure source maps for stack traces

### Best Practices
- Don't log PII (phone, Aadhaar) in error contexts
- Tag errors by feature module
- Set up alerts for new error types
- Triage errors weekly

---

## Analytics: PostHog

### Why PostHog
- 1M events/month free
- Self-hostable if needed
- Funnels, retention, A/B tests built-in
- GDPR/DPDP-friendly

### Events to Track
- App opened
- Service category viewed
- Booking initiated
- Booking completed
- Payment success/failure
- Photo uploaded
- Job status changed
- Customer rated technician
- Technician went online
- Cash debt incurred

### Privacy
- No PII in events
- User ID = hashed
- Configurable opt-out

---

## Cost Projections (Third-Party)

| Service | Stage 1 (Beta) | Stage 2 (1K users) | Stage 3 (10K users) |
|---|---|---|---|
| Razorpay | 2% per txn | 2% per txn | 2% (negotiate down) |
| MSG91 | ₹200/month | ₹2,000/month | ₹15,000/month |
| Gupshup | ₹500/month | ₹3,000/month | ₹20,000/month |
| Setu KYC | ₹500/month | ₹3,000/month | ₹15,000/month |
| Karza KYC | ₹500/month | ₹2,000/month | ₹10,000/month |
| Google Maps | Free | Free or ₹2K | ₹10,000/month |
| OneSignal | Free | Free or ₹800 | ₹3,000/month |
| Sentry | Free | Free or ₹2K | ₹4,000/month |
| PostHog | Free | Free | ₹4,000/month |
| **Total** | ~₹2,000/mo | ~₹15,000/mo | ~₹80,000/mo |

These scale with your business — they're variable costs, not fixed.

---

## Service Setup Checklist

Before launching V1, all of these must be configured:

- [ ] Razorpay account approved + live keys
- [ ] MSG91 DLT compliance complete
- [ ] MSG91 templates approved
- [ ] Gupshup WhatsApp Business approved
- [ ] Setu KYC integration tested
- [ ] Karza PAN verification tested
- [ ] Google Maps API key generated + billing alerts set
- [ ] OneSignal app configured with Firebase
- [ ] Brevo email templates created
- [ ] Sentry DSNs in all environments
- [ ] PostHog projects created
- [ ] Cloudflare DNS configured
- [ ] All API keys in secrets manager

---

## Vendor Lock-in Mitigation

### Principles
- All third-party calls go through a wrapper service in our backend
- Wrappers expose internal interfaces, not vendor-specific shapes
- Switching vendor = swap implementation behind interface
- Document every vendor's API in `vendor-integrations/` folder

### Example Wrapper Pattern
```
// services/sms-provider.ts
interface SmsProvider {
  sendOtp(phone: string, otp: string): Promise<void>;
}

class MSG91Provider implements SmsProvider { ... }
class TwilioProvider implements SmsProvider { ... }

// Inject the active one via DI / config
```

**Same pattern for:** KYC, Maps, Push, Payments, Storage, Email.

---

## Critical Reminders

### Before Going Live
- Test every webhook with real API calls (not just mocks)
- Verify all production secrets are different from dev
- Test refund flows in Razorpay live mode with small amounts
- Test SMS delivery to multiple operators (Jio, Airtel, Vi, BSNL)
- Confirm DLT-approved templates exactly match what backend sends
- Set up billing alerts on Google Maps (avoid $1000 surprise bill)

### Things People Forget
- Razorpay needs your account verified before refunds work
- Google Maps key restrictions (lock to your app's package name + SHA-1)
- MSG91 DLT mismatch = silent SMS failures
- WhatsApp template variables must match exactly or rejected
- KYC vendors charge for failed verifications too — monitor success rates
