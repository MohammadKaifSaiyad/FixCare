---
name: flutter-feature
description: Use when adding a new feature to apps/customer or apps/technician (Flutter) — e.g. "add the booking screen", "build technician onboarding". Scaffolds the feature-first data/domain/presentation structure with Riverpod and a typed go_router route. The app-side equivalent of scaffold-module.
---

# Flutter Feature (FixCare apps)

Scaffold a feature in a Flutter app following the **feature-first** convention from
`coding-conventions.md`. Applies to both `apps/customer` and `apps/technician`.

## Structure

```
features/<feature>/
├── data/            # repositories + DTO/models (freezed + json_serializable)
│   ├── <feature>_repository.dart
│   └── models/
├── domain/          # entities + value objects (pure Dart, no Flutter/dio)
│   └── <feature>.dart
└── presentation/    # screens + widgets + Riverpod providers
    ├── <feature>_screen.dart
    └── <feature>_providers.dart
```

## Rules baked in (coding-conventions.md Flutter/Mobile)
- **Feature-first**, not layer-first. Each feature owns its data/domain/presentation.
- **Riverpod everywhere** for state — never mix in Bloc/Provider/GetX.
- **go_router** with **typed routes** + deep-link support (push notification → screen).
- **UI never calls dio directly** — it goes through a repository (see `api-repository`).
- Repositories return **domain entities or a typed `Failure`**, never raw JSON.
- Models use **`freezed` + `json_serializable`**.
- Secrets/tokens via **`flutter_secure_storage`** (never localStorage-style patterns).
- Build **loading / error / empty** states for every screen.
- Performance: test on low-end (Redmi 9A class); dispose controllers; lazy-load maps;
  keep release APK <25 MB.

## Process
1. Create the three folders; define the domain entity first (pure Dart).
2. Add the repository (`api-repository` skill) and freezed models in `data/`.
3. Build providers + screen in `presentation/`; wire a typed go_router route.
4. Add loading/error/empty states.
5. Run `flutter-widget-reviewer` before merge.

> Reference: `docs/05-development/coding-conventions.md` (Flutter/Mobile), `docs/03-tech-stack/mobile-stack.md`.
