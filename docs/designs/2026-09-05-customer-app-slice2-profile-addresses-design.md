# Customer App — Slice 2: Boot Hydration + Profile + Addresses (design)

**Date:** 2026-09-05 · **Branch:** `feature/customer-app-slice2-profile-addresses` · **Status:** approved
**App:** `apps/customer` (Flutter, Android + iOS — ADR-0005). Second app slice; builds on Slice 1's
backbone (Riverpod `@riverpod` codegen, go_router, dio + single-flight interceptor, `Result<T>`, freezed,
theme tokens + Outfit). Screen designs: `Claude Design/fixcare-customer-app-design`. Backend contract read
from `apps/backend/src/modules/{profiles,addresses}`.

## Goal

A logged-in customer has a real identity (name fetched on boot, captured on first run) and can manage
their service addresses with live pincode serviceability and a map-picked location — the prerequisites for
booking. Replaces the Slice-1 placeholder user.

## Scope (settled)

| In | Out (later slice) |
|---|---|
| Boot hydration: fetch real `/me/profile` on cold boot | Home real content / catalog grid (Slice 3) |
| First-run **name capture** (gated after login when name empty) | Booking creation / tracking |
| **Account** screen (view name + phone, edit name, sign out) | Actual arrival-geofence *use* of lat/lng (captured now) |
| **Address** list / add / edit / delete / set-default | Address search / autocomplete |
| Live pincode **serviceability** while typing | Multiple map providers |
| **Google Maps** pin-drop for lat/lng (graceful w/o key) | |

## New tech

**`google_maps_flutter`** — Maps is in the locked stack (`CLAUDE.md`: "Maps | Google Maps Platform"), so
this is first-use, **no ADR needed**. Needs a Maps API key (Android `AndroidManifest.xml` meta-data + iOS
`AppDelegate.swift`). The key is **never committed**; the app **degrades gracefully without it** (map area
shows a "add MAPS_API_KEY" placeholder; all other address fields + save still work), so the slice is
testable/mergeable before the key is provisioned. The PR carries an exact key-setup runbook.

## Backend contract (read from source — the authority)

- **Profile:** `GET /me/profile` → `CustomerProfileDto { id, role:'CUSTOMER', name, status }` (name may be
  empty for a new user — no phone in this DTO). `PATCH /me/profile { name }` → updated DTO. 401 unauth.
- **Addresses:** `GET /me/addresses` → `AddressDto[]`; `POST /me/addresses` (201) → `AddressDto`;
  `GET/PATCH/DELETE /me/addresses/:id`. `AddressDto = { id, label, line1, line2?, landmark?, pincode,
  lat?, lng?, isDefault, status, serviceable, zone:{id,name,visitFeePaise}|null, message? }`.
  - Create body: `{ label, line1, line2?, landmark?, pincode(6-digit), lat?, lng?, isDefault? }` —
    **lat & lng both-or-neither**. Out-of-area still saves (201, `serviceable:false` + `message`).
  - Update body: same fields, all partial, ≥1 required, lat/lng both-or-neither.
- **Serviceability:** `GET /serviceability?pincode=` → `{ serviceable, zone, message? }`.
- **Error envelope (all endpoints):** `{ code, message }` (see `errorHandler.ts`) — repositories read
  `message`, never `error`.

## Module layout (feature-first, mirrors Slice 1's `auth/`)

```
lib/features/
  profile/
    data/profile_dtos.dart        // freezed CustomerProfileDto
    data/profile_repository.dart  // getProfile / updateName → Result; profileRepositoryProvider
    presentation/name_capture_screen.dart   // /name
    presentation/account_screen.dart        // /account
    // No profile_controller: name lives in the session, so name capture + Account
    // name-edit drive AuthController (updateName → session refresh). Decided, not optional.
  address/
    data/address_dtos.dart        // freezed AddressDto, ServiceabilityDto
    data/address_repository.dart  // list/create/update/delete/checkServiceability → Result; provider
    presentation/address_list_screen.dart   // /addresses
    presentation/address_form_screen.dart   // /address/new + /address/:id/edit
    presentation/address_controller.dart     // @riverpod list state (load/refresh/mutations)
    presentation/widgets/serviceability_chip.dart, address_map_picker.dart
```

Reuses (no new primitives): `core/result.dart`, `core/network/dio_client.dart` + interceptor,
`core/storage/token_store.dart`, `core/theme.dart`, `core/widgets/`.

## Data layer

**ProfileRepository(Dio):** `getProfile() → Result<CustomerProfileDto>` (GET); `updateName(String) →
Result<CustomerProfileDto>` (PATCH `{name}`). `profileRepositoryProvider`.

**AddressRepository(Dio):** `list() → Result<List<AddressDto>>`; `create(CreateAddress) → Result<AddressDto>`;
`update(id, UpdateAddress) → Result<AddressDto>`; `delete(id) → Result<void>`; `checkServiceability(pincode)
→ Result<ServiceabilityDto>`. `addressRepositoryProvider`. Request bodies match the backend exactly
(lat/lng both-or-neither enforced client-side before the call).

## Boot hydration (the core change to Slice 1's AuthController)

Slice 1 returned a placeholder `SessionAuthenticated(UserDto(id:'',…))` when a token existed. New `build()`:

```
build():
  access token absent            → SessionUnauthenticated
  access token present            → GET /me/profile:
     Ok(profile)                  → SessionAuthenticated(profile)          // real id + name
     Failure(unauthorized)        → TokenStore.clear() → SessionUnauthenticated   // stale token
     Failure(network/server/…)    → SessionAuthenticated(unhydrated marker) // option (a): stay logged in
```

- **Session type** carries the real profile when hydrated. Add a `hydrated` flag (or nullable name) so the
  name-gate only fires on a *successful* fetch returning an empty name — a network blip must NOT eject a
  logged-in user or force name capture. On network failure the user lands on Home (stub) and can retry.
- **`submitOtp` (login):** verify returns `user{id,role,status}` **without name**. After saving tokens,
  fetch `/me/profile`; set `SessionAuthenticated(profile)`. If `profile.name` is empty → the router's
  name-gate sends them to `/name`.
- **`AuthController.updateName(String)`** (new method): calls `ProfileRepository.updateName`, and on Ok
  re-emits `SessionAuthenticated` with the new name. Both name capture and Account name-edit call this — the
  session is the single source of truth for the current name, so no separate profile controller is needed.

## Routing (additions to app_router.dart)

New routes: `/name`, `/account`, `/addresses`, `/address/new`, `/address/:id/edit`.
Redirect rules (added to the existing session-keyed redirect):
- `AsyncLoading` → `/splash`; `hasError` → `/phone` (unchanged).
- `SessionUnauthenticated` → `/phone` (allow `/phone`,`/otp`).
- `SessionAuthenticated` **but name empty (and hydrated)** → force `/name` (allow only `/name`).
- `SessionAuthenticated` named → normal; `/splash`/auth screens/`/name` → `/home`.
- Account/addresses reached from Home (avatar → `/account`).

## Screens

1. **Name capture** (`/name`) — heading "What should we call you?", one name field (`Key('nameField')`),
   "Continue" 56px CTA (`Key('nameContinueBtn')`). Submit → `updateName` → session refresh → `/home`.
   Uses the Slice-1 field/heading styling (theme tokens, Outfit).
2. **Account** (`/account`) — name (editable), phone (read-only from session), rows: "My addresses"
   (→ `/addresses`), "Sign out" (`Key('signOutBtn')` → `AuthController.logout`). Logout moves here from the
   Home stub avatar; the avatar now → `/account`.
3. **Address list** (`/addresses`) — per-address card: label, line1/line2, pincode, serviceability chip
   (green "We serve this area ✓" / muted "Out of service area"), default badge, edit/delete/set-default
   actions. Empty state → "Add your first address". "Add address" → `/address/new`. Pull-to-refresh.
4. **Add/Edit address** (`/address/new`, `/address/:id/edit`) — fields: label, line1, line2, landmark,
   pincode. At 6-digit pincode → **debounced (~400ms) `checkServiceability`** → inline ✓/warning
   (out-of-area warns, save stays enabled). **Google Maps pin-drop** for lat/lng (degrades to a placeholder
   without a key). `isDefault` toggle. Save (`Key('saveAddressBtn')`) → create/update → back to list.

## Error / loading / edge

Typed `Result` → `FailureKind` messages (network/unauthorized/rateLimited/validation/server). Lists: spinner
→ content or retry. Serviceability check debounced; a failed check shows "couldn't check — you can still
save". Out-of-area: `serviceable:false` shows the warning, save allowed (backend 201). 401 anywhere →
interceptor refresh, else the boot path clears + re-login.

## Testing (mocked transport; contract-guarded per the Slice-1 /code-review lesson)

- **profile_repository_test:** getProfile/updateName → Ok(DTO)/401/400/network; **assert PATCH body is
  exactly `{name}`**.
- **address_repository_test:** list/create/update/delete/serviceability → Ok/failure mapping; **assert
  request bodies** (create `{label,line1,…,pincode}`, lat/lng both-or-neither) + `{code,message}` envelope.
- **auth_controller_boot_test:** token+named → Authenticated(named); token+empty-name → name-gate;
  token+401 → cleared/Unauthenticated; token+network → stays Authenticated (option a).
- **name_gate_router_test:** authenticated-nameless → `/name`; named → not.
- **address_form_widget_test:** serviceable pincode shows ✓; out-of-area shows warning + save enabled.
- Map picker: not unit-tested (platform view) — covered by manual device test with the key.
- `flutter analyze` clean; build_runner generates freezed/riverpod cleanly; 16 prior tests stay green.

## Maps API key runbook (goes in the PR + apps/customer/README.md)

1. Google Cloud Console → enable **Maps SDK for Android** + **Maps SDK for iOS** → create an API key.
2. **Restrict** the key: Android → package name `in.fixcare.fixcare_customer` + SHA-1; iOS → bundle id
   `in.fixcare.fixcareCustomer`.
3. Android: add `<meta-data android:name="com.google.android.geo.API_KEY" android:value="…"/>` in
   `android/app/src/main/AndroidManifest.xml` (or via a local, git-ignored `secrets.properties`).
4. iOS: `GMSServices.provideAPIKey("…")` in `ios/Runner/AppDelegate.swift`.
5. Verify: run on emulator/simulator, open Add Address, confirm the map tile renders and a dropped pin sets
   lat/lng. Without the key the placeholder shows and the rest of the form still works.

## Out of scope (recorded)

Home real content/catalog (Slice 3), booking creation/tracking, the arrival-geofence *use* of lat/lng
(captured now), address search/autocomplete, saved-place labels beyond free text, multiple map providers,
reverse-geocoding pincode from a dropped pin (pin sets lat/lng only; pincode stays typed this slice).
