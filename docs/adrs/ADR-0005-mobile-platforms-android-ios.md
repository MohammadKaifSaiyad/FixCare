# ADR-0005 — Mobile platforms: Android + iOS for V1, drop web

**Status:** Accepted · **Date:** 2026-09-05 · **Amends:** the "Android only V1" stance in
`CLAUDE.md`, `docs/03-tech-stack/mobile-stack.md`, and the customer-app slice designs.

## Context

The original stance was **Android-only for V1** (CLAUDE.md tech stack: "Android only V1";
the customer-app Slice 1 design listed "iOS (Android-only V1)" as out of scope). The
reasoning was reach — the Vadodara/Padra market skews heavily Android — traded against the
cost of a second mobile platform (Apple Developer account, App Store review, iOS platform
config, extra testing). A **web** target existed only incidentally: the Flutter scaffold
created `web/` and it was used as a fast, emulator-free dev loop (`flutter run -d chrome`).

The founder has decided both mobile platforms are first-priority for V1, and that the web
target adds no user value and should go.

## Decision

**V1 mobile platforms are Android AND iOS — both first-priority. Web is dropped.**

This applies to **both Flutter apps**: the customer app (`apps/customer`) and the technician
app (`apps/technician`, not yet built). When the technician app is scaffolded, it targets
Android + iOS from the start.

Concretely:

- **Add iOS:** each app scaffolds an `ios/` project and carries iOS platform config
  (a **Debug-only** `NSAppTransportSecurity` `localhost` exception for the dev backend's
  cleartext HTTP — wired via a separate `Info-Debug.plist` on the Debug build config only,
  so Release/Profile stay HTTPS-only). **App IDs differ by platform, by convention, and
  that is expected:** Android `applicationId = in.fixcare.fixcare_customer` (underscores
  allowed); iOS `PRODUCT_BUNDLE_IDENTIFIER = in.fixcare.fixcareCustomer` (iOS bundle ids
  conventionally omit underscores, so `flutter create` camelCases the suffix). They are
  independent identifiers — do NOT force them equal. Whatever cross-platform identity
  matching needs (OneSignal, deep links, analytics) must be configured per-platform with
  each app's real id. App **Dart is already platform-neutral** — Riverpod / go_router /
  dio / secure-storage all run on iOS unchanged — so this is scaffolding + platform config
  + testing, not a rewrite.
- **Drop web:** remove the `web/` scaffold and the Chrome run commands from the apps'
  READMEs. Dev is done on the Android emulator / iOS simulator / real devices.

Build order (ADR-0004) is unchanged: backend → customer app → technician app → admin →
merchant. This ADR only changes *which platforms* each app targets, not their order.

## Consequences (accepted trade-offs)

- **Doubled mobile surface** — every app slice must build and be smoke-tested on both an
  Android emulator and an iOS simulator before merge. iOS-specific platform work
  (background location for the technician app especially — already a known hard risk on
  Android) now has an iOS variant to budget for.
- **Apple dependencies become critical-path:** an Apple Developer account ($99/yr) and a
  Mac with Xcode are required to build/ship iOS. iOS builds cannot be produced in the
  CI/agent environment used for the Android APK check — they need the founder's Mac +
  Xcode. Review of an iOS-touching PR verifies config by construction; the founder runs the
  simulator smoke-test.
- **Losing the web dev loop:** `flutter run -d chrome` was the fastest no-emulator way to
  poke the UI. Dropping it means spinning an emulator/simulator for quick checks. Judged
  worth it — a web build we don't ship is a maintenance surface with no user, and it masked
  a real bug once (a Chrome run against the emulator-only `10.0.2.2` base URL surfaced only
  as a generic "network error").
- **The dev-backend cleartext allowance is now per-platform:** Android uses a debug-only
  `network_security_config.xml` (already in place); iOS needs the debug-only ATS exception.
  Both must stay debug-scoped — release traffic is HTTPS-only on both platforms.

## Follow-through

- Customer app: the next PR after Slice 1 adds `ios/`, the iOS ATS/Info.plist config, and
  removes `web/` + the Chrome commands. Slice 1 itself merges Android-only (web scaffold
  still present); this ADR is the record that the change is deliberate and scheduled.
- Technician app: scaffolded with Android + iOS, no web, when it starts.
- Docs updated in the same pass: CLAUDE.md ("Android only V1" → "Android + iOS V1, no web"),
  `mobile-stack.md`, and the customer-app slice designs' out-of-scope lists.
