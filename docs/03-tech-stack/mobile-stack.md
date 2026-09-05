# Mobile Stack

Flutter for both customer and technician apps. Single shared codebase, **Android + iOS
for V1** (Android-first in emphasis, but iOS ships alongside — see
[ADR-0005](../adrs/ADR-0005-mobile-platforms-android-ios.md)). No web app.

---

## Core Setup

```
Framework:       Flutter 3.x (latest stable)
Language:        Dart 3.x
Target:          Android API 23+ (Android 6.0+) — covers 95%+ of Indian devices
iOS:             iOS 15+ (Flutter scaffold default; ships in V1 alongside Android — ADR-0005)
```

### Why Flutter Wins
- Single codebase = 2 apps × 2 platforms = 4 apps from 1 codebase
- Near-native performance (critical for maps + real-time)
- Excellent AI code generation
- Hot reload speeds vibe coding iteration
- Google's long-term backing
- Beautiful UI out of the box

---

## State Management

**Pick:** Riverpod 2.x

### Why
- Best AI code generation support
- Compile-time safety
- Testable
- Familiar to junior devs
- Active community

### Avoid
- **Provider:** Older, being replaced
- **Bloc:** More boilerplate, AI generates messy bloc code
- **GetX:** Anti-pattern community; harder to maintain

---

## Routing

**Pick:** go_router

### Why
- Official Flutter recommendation
- Deep linking support (push notifications → specific screen)
- Type-safe routes
- Works well with Riverpod

---

## Backend Communication

```
HTTP:            dio
Type-safe API:   retrofit
Real-time:       web_socket_channel
JSON:            json_serializable + freezed
```

### Why dio over http
- Interceptors (auth token refresh, logging)
- Better error handling
- Cancel tokens
- File upload progress

### Pattern
- All API calls go through a `Repository` layer
- Repositories return domain models, not raw JSON
- Errors mapped to typed `Failure` classes
- Riverpod providers expose repositories to UI

---

## Local Storage

```
Secure:          flutter_secure_storage (tokens, sensitive data)
Preferences:     shared_preferences (UI state, flags)
Database:        drift (sqlite) — only if needed for offline mode
```

**V1 default:** No local DB. Server is single source of truth.
**Add drift only when:** Technician app needs offline job queue.

---

## Maps & Location

```
Maps:            google_maps_flutter
GPS:             geolocator
Background loc:  flutter_background_geolocation (technician app only)
Place picker:    google_places_flutter
```

### Permissions Needed
- Location (foreground + background for technician)
- Foreground service notification (Android requirement)

### Battery Strategy (Technician App)
- Online but no active job: GPS every 60 seconds
- Active job: GPS every 10 seconds
- Stop background updates when offline

---

## Push Notifications

```
Provider:        OneSignal
Plugin:          onesignal_flutter
Deep linking:    via go_router + notification payload
```

### Why OneSignal over raw FCM
- Easier setup
- Built-in segmentation (technician vs customer)
- Free tier covers 10K subscribers
- Cross-platform (Android + iOS) out of the box
- A/B testing built-in

---

## Camera & Photos

```
Camera:          camera (full control)
Picker:          image_picker (gallery + camera)
Compression:     flutter_image_compress
Geotag:          via geolocator at capture time
```

### Critical Photo Rules
- Technician app photos: **camera only**, gallery disabled
- Photos must be geotagged + timestamped at capture
- Compress before upload (max 1MB per photo)
- Upload to backend, get S3-style URL back
- Store URL only, never the file

---

## QR Code

```
Scanner:         mobile_scanner
Generator:       qr_flutter
```

### Use Cases
- Technician badge QR (generated, shown in technician app, scanned by customer)
- Merchant return QR (generated on merchant side, scanned by technician)
- Customer verification (customer scans technician QR on arrival)

---

## Payments

```
Plugin:          razorpay_flutter
UPI Intent:      via razorpay_flutter
AutoPay:         via Razorpay subscriptions API
```

### Customer App Flow
1. Booking confirmation → call backend → backend creates Razorpay order
2. App opens Razorpay checkout
3. Customer pays via UPI/card
4. Razorpay webhook hits backend → updates job status
5. App polls for status update OR receives WebSocket push

---

## Authentication UI

```
Phone input:     intl_phone_field
OTP input:       pin_code_fields
Biometric:       local_auth (for app unlock, V2)
```

### Phone OTP Flow
1. User enters phone
2. App calls backend → MSG91 sends OTP
3. User enters 6-digit OTP
4. App sends to backend → backend validates → returns JWT
5. JWT stored in secure storage
6. Refresh token auto-handled by dio interceptor

---

## Localization

```
Package:         flutter_localizations + intl
Languages V1:    English + Hindi + Gujarati
```

### Approach
- All strings in ARB files
- AI can help generate translations
- Get human review for Hindi/Gujarati before launch
- User selects language at first launch (defaults to system)

---

## Crash & Analytics

```
Crash:           Sentry (free tier 5K events/month)
Analytics:       PostHog (free tier 1M events/month)
Logs:            local file + remote upload on crash
```

### What to Log
- All API calls (anonymized)
- All screen views
- Booking funnel events
- Payment success/failure
- Photo upload success/failure
- WebSocket connection state

### What NOT to Log
- Phone numbers (PII)
- UPI IDs (PII)
- Aadhaar numbers (sensitive)
- Customer addresses (PII)
- Photos themselves

---

## App Structure (Per App)

```
lib/
├── main.dart                 # App entry, providers setup
├── app.dart                  # MaterialApp + routing
├── core/                     # Shared infrastructure
│   ├── api/                  # dio config, interceptors
│   ├── storage/              # Secure storage wrappers
│   ├── theme/                # Colors, typography
│   ├── routing/              # go_router config
│   ├── errors/               # Failure classes
│   └── utils/                # Helpers
├── features/                 # By feature, not by layer
│   ├── auth/
│   │   ├── data/             # Repositories, models
│   │   ├── domain/           # Entities, use cases
│   │   └── presentation/     # Screens, widgets, providers
│   ├── booking/
│   ├── jobs/
│   ├── payments/
│   └── profile/
└── shared/                   # Cross-feature widgets
    └── widgets/
```

### Why "Features" Folder
- One feature change touches one folder
- AI can work within feature boundary cleanly
- Easy to extract features into packages later

---

## Code Quality

```
Linter:          flutter_lints (Google's official)
Custom rules:    dart_code_metrics
Formatter:       dart format (built-in)
```

### Enforce in CI
- Lint passes
- All tests pass
- Code coverage >50% (V1 target; raise later)

---

## Testing Strategy (V1)

**Minimum:**
- Unit tests for utility functions
- Unit tests for repositories (with mocked API)
- Widget tests for critical screens (booking flow)

**Skip in V1:**
- Integration tests (slow, brittle)
- E2E tests (use manual QA + beta users)

**Add in V2:**
- Integration tests for payment flow
- E2E tests for critical paths

---

## Build & Release

```
CI/CD:           GitHub Actions
Distribution:    Firebase App Distribution (testers)
                 Google Play Store (production)
```

### Build Variants
- `debug` — Development, points to local backend
- `staging` — Testing, points to staging backend
- `production` — Live, points to prod backend

Use Flutter flavors for clean separation.

---

## Dependencies to Add Early

Listed in priority order, install as needed:

```yaml
# Critical
flutter_riverpod: ^2.x
go_router: ^14.x
dio: ^5.x
freezed_annotation: ^2.x
json_annotation: ^4.x
flutter_secure_storage: ^9.x
intl_phone_field: ^3.x
pin_code_fields: ^8.x

# Maps & Location
google_maps_flutter: ^2.x
geolocator: ^11.x
flutter_background_geolocation: ^4.x  # technician app only

# Camera & Files
camera: ^0.10.x
image_picker: ^1.x
flutter_image_compress: ^2.x
mobile_scanner: ^5.x
qr_flutter: ^4.x

# Push & Comms
onesignal_flutter: ^5.x

# Payments
razorpay_flutter: ^1.x

# Monitoring
sentry_flutter: ^8.x
posthog_flutter: ^4.x
```

---

## Performance Targets

| Metric | Target |
|---|---|
| App size (release APK) | <30 MB |
| Cold start time | <2 seconds |
| Booking flow completion | <90 seconds |
| Map render time | <1 second |
| Photo upload (1 photo) | <5 seconds on 3G |
| WebSocket reconnect | <3 seconds |

---

## Common Pitfalls (For Solo Vibe Coding)

### Watch For
- AI generating different state management patterns in different files (enforce Riverpod everywhere)
- AI using deprecated Flutter widgets (always check Flutter 3.x docs)
- AI hardcoding API URLs (always use env config)
- AI forgetting null safety (Dart is strict; AI sometimes isn't)
- AI generating tests that don't actually test anything

### Best Practices
- Generate one screen at a time
- Test each screen on a real low-end Android (₹10k phone)
- Profile builds regularly (`flutter build apk --analyze-size`)
- Update dependencies cautiously (one at a time, test thoroughly)
