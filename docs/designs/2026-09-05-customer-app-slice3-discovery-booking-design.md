# Customer App — Slice 3: Discovery + Create Booking (design)

**Date:** 2026-09-05 · **Branch:** `feature/customer-app-slice3-discovery-booking` · **Status:** approved
**App:** `apps/customer` (Flutter, Android + iOS). Third app slice; builds on Slices 1-2 (Riverpod
`@riverpod` codegen, go_router, dio + single-flight interceptor, `Result<T>`, freezed, theme tokens +
Outfit, profile + address modules). Backend contract read from `apps/backend/src/modules/{catalog,bookings}`.
Screen designs: `Claude Design/fixcare-customer-app-design`.

## Goal

A logged-in customer browses the real service catalog, books a service at their address for a chosen slot,
and lands on a booking screen — turning the stub home into the app's core value path. Tracking detail and
state actions are Slice 4.

## Scope (settled)

| In | Out (Slice 4+) |
|---|---|
| Home = real catalog (categories + per-zone services) | Full state-driven tracking (17 states, polling) |
| Booking wizard: service → address → slot → confirm | confirm-arrival / approve-decline / completion-OTP |
| `POST /me/bookings` → land on a **tracking stub** | Payment UI, disputes UI, bookings-list screen |
| Cancel from the stub | Home's active-booking (dark) card; real slot availability |

## Key backend facts (read from source — authoritative)

- **Services are priced PER ZONE.** `GET /catalog/services?zoneId=&categoryId=` → `ServiceDto[]` where each =
  `{id, name, tier, categoryId, laborPaise: int|null (null=unpriced in that zone), visitFeePaise: int (the
  zone's visit fee)}`. **`zoneId` is required.** `GET /catalog/categories` → `CategoryDto[] {id, name, status}`.
- **A customer's zone comes from their address.** The Slice-2 `AddressDto` already carries
  `zone:{id, name, visitFeePaise}`. Home resolves prices via the **default address's** `zone.id`.
- **`POST /me/bookings {addressId, serviceId, scheduledSlot}`** → `BookingDto` (state `DISPATCHED`).
  `scheduledSlot` = ISO 8601, **must be in the future** (backend `.refine`). The backend derives the
  customer from the **JWT** and **snapshots zone + price server-side from `addressId`** — the app sends only
  those three fields (never a customer id, never a client-computed price).
- **Create 422s** (the two real ones): `"We don't serve this area yet"` (address unserviceable) and
  `"This service is unavailable in your area"` (service unpriced in that zone). Error envelope `{code, message}`.
- **`BookingDto`** (create response + Slice-4 tracking contract): `id, bookingNumber ("FC-…"), state,
  scheduledSlot, visitFeePaise, laborPaise, service{id,name}, zone{id,name}, address{id}, estimate,
  technician?{name,maskedPhone}, diagnosis?, parts[], photos[], payment?, dispute?`. Slice 3 models the full
  DTO (so Slice 4 need not re-model) but only renders the stub subset.
- **Cancel:** `POST /me/bookings/:id/cancel` (exists from B1).

## Carry-forwards honored (from the Slice-2 whole-branch review)

- The app **never sends a customer id** — the backend derives it from the token.
- The app **never snapshots price client-side** — it sends `{addressId, serviceId, scheduledSlot}`; the
  backend snapshots zone + price. See [[booking-zone-price-snapshot]].

## Module layout (feature-first)

```
lib/features/
  catalog/
    data/catalog_dtos.dart        // freezed CategoryDto, ServiceDto (== backend ServicePriceDto)
    data/catalog_repository.dart  // categories() / services(zoneId, categoryId?) → Result; provider
    presentation/                 // (Home consumes these; catalog has no standalone screen this slice)
  booking/
    data/booking_dtos.dart        // freezed BookingDto (full) + nested types
    data/booking_repository.dart  // create() / get(id) / cancel(id) → Result; provider
    presentation/booking_wizard_screen.dart   // /book/:serviceId (3-step)
    presentation/booking_wizard_controller.dart // @riverpod transient wizard state
    presentation/booking_tracking_screen.dart  // /booking/:id (stub)
  home/presentation/home_screen.dart          // REPLACE the stub → real catalog
```
Reuses (no new primitives): `core/result.dart`, `dioProvider` + interceptor, `core/theme.dart`, the
**address module** (default address → zone; address picking), freezed, `@riverpod`.

## Data layer

**CatalogRepository(Dio):** `categories() → Result<List<CategoryDto>>`; `services({required String zoneId,
String? categoryId}) → Result<List<ServiceDto>>`. `catalogRepositoryProvider`.

**BookingRepository(Dio):** `create({required String addressId, required String serviceId, required String
scheduledSlot}) → Result<BookingDto>`; `get(String id) → Result<BookingDto>`; `cancel(String id) →
Result<void>` (POST /me/bookings/:id/cancel, 200/void). `bookingRepositoryProvider`.

**DTOs:** `CategoryDto {id, name, status}`; `ServiceDto {id, name, tier, categoryId, laborPaise:int?,
visitFeePaise:int}`; full `BookingDto` per the contract above (freezed, `abstract class X with _$X`,
nullable where the backend is nullable). Generated `.g/.freezed` committed.

## Data flow

1. **Home:** load `categories()` + the customer's addresses (address controller). Default address →
   `zone.id` → `services(zoneId, categoryId)` per selected category. Render prices from `visitFeePaise`
   (+ `laborPaise` when non-null). **No default address (no zone) → Home shows the category grid but CANNOT
   fetch services** (`GET /catalog/services` requires `zoneId`). So instead of a service list it shows an
   "Add an address to see services & book" CTA (→ the Slice-2 add-address flow); once an address exists,
   services load. This is deliberate — service *prices* and *availability* are zone-specific, so there is no
   meaningful zone-less service list to show.
2. **Tap service** → `/book/:serviceId`. `BookingWizardController` holds `{serviceId, addressId?,
   scheduledSlot?}`.
   - **Address step:** radio list of `/me/addresses` (default preselected), each with its serviceability
     chip; "Add address" → add-address flow → back to the wizard.
   - **Slot step:** date chips (today…+7) + window chips (Morning 9-12 / Afternoon 12-3 / Evening 3-6) →
     resolve to a concrete **future ISO** datetime (guard: must be > now; if today's window has passed,
     disable/skip it).
   - **Confirm step:** service name, chosen address (+ serviceability), slot, **visit fee** (that address's
     zone) → "Confirm booking" → `create(...)`.
3. **Create result:** `Ok(booking)` → `context.go('/booking/:id')` (replace). `Failure` → surface the
   backend `message` inline on the confirm step (the two 422s especially), stay on confirm; `network`/`server`
   → retry affordance. **Never swallow the Result** (Slice-2 lesson).
4. **Tracking stub** (`/booking/:id`): render the `BookingDto` — bookingNumber, state badge ("Finding you a
   technician…" for DISPATCHED), service, slot, address, visit fee — + a **Cancel** button (`cancel(id)` →
   back to Home) + a "Live tracking coming soon" banner. May re-fetch via `get(id)`.

## Screens & routing

- **Home** (`/home`): address-switcher header (default address; avatar → `/account`), category grid, per-category
  service list (price teasers), bottom tab bar. No-address path handled per §data-flow.
- **Booking wizard** (`/book/:serviceId`): 3-step stepper; keys `wizardAddress`, `wizardSlot`, `wizardConfirm`,
  `confirmBookingBtn`.
- **Tracking stub** (`/booking/:id`): the created BookingDto + Cancel.
- Routing: add `/book/:serviceId`, `/booking/:id`. Service tap → `context.push`; confirm → `context.go`
  (replace, so Back doesn't re-enter the wizard).

## Error / loading / edge

Typed `Result` → `FailureKind` messages. Home: spinner → content / retry; empty catalog → "No services yet".
No default address → the add-address CTA (not a crash). Slot step: never allow a past ISO. Confirm 422 →
inline backend message (unserviceable / unpriced), save-in-place. 401 → interceptor refresh.

## Testing (mocked transport; contract-guarded per the Slice-1/2 lesson)

- **catalog_repository_test:** categories/services → Ok/Failure; assert `services` sends `zoneId`+`categoryId`
  query params; `{code,message}` envelope; laborPaise-null parsed.
- **booking_repository_test:** `create` sends **exactly** `{addressId, serviceId, scheduledSlot}`
  (`FullHttpRequestMatcher(needsExactBody:true)`); Ok(BookingDto) parsed (full DTO incl. nested); 422 →
  Failure(validation) with the backend message; network→network. `get` parses; `cancel` → Ok(void).
- **home_widget_test:** categories render; a priced service shows its price; **no-default-address → add-address
  CTA renders (no crash)**.
- **wizard_widget_test:** service → address (default preselected) → slot (window→future ISO) → confirm →
  `create` called with the 3 fields; a **422 create surfaces the message and stays on confirm** (silent-swallow
  regression guard).
- **tracking_stub_test:** renders bookingNumber + state badge.
- `flutter analyze` clean; build_runner idempotent (generated files committed).

## Out of scope (recorded)

Full state-driven tracking (17 states, polling, confirm-arrival, approve/decline, completion-OTP) — Slice 4;
payment UI, disputes UI, bookings-list screen, Home's active-booking dark card, real slot-availability API,
camera evidence. Maps live tiles still need billing (parked; unrelated to this slice).
