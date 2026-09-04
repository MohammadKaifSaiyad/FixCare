# apps/customer — FixCare Customer App

Flutter 3.x (Android + web for dev) + Riverpod + go_router + dio. Customer books →
tracks → pays → rates from mobile, with real-time job updates.

Mobile architecture & conventions: [`docs/03-tech-stack/mobile-stack.md`](../../docs/03-tech-stack/mobile-stack.md)
and the Flutter section of [`docs/05-development/coding-conventions.md`](../../docs/05-development/coding-conventions.md).

## Build timing
Built **Months 5-6** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md).
Built before the technician app to validate customer demand before investing in
supply-side tooling.

## Toolchain note
Uses its own `pubspec.yaml` (Dart/Flutter). **Not** part of the root pnpm
workspace — see [`docs/adrs/ADR-0001-monorepo.md`](../../docs/adrs/ADR-0001-monorepo.md).

## Run commands

Backend must be up first (from repo root):

```bash
docker compose up -d
pnpm --filter backend dev
```

Run the app against the local backend (Android emulator; `10.0.2.2` maps to the
host machine's `localhost`):

```bash
flutter run --dart-define=BASE_URL=http://10.0.2.2:3000
```

Chrome (web) variant, against host `localhost` directly:

```bash
flutter run -d chrome --dart-define=BASE_URL=http://localhost:3000
```

Generate code (freezed / json_serializable / riverpod_generator):

```bash
dart run build_runner build --delete-conflicting-outputs
```

Run tests:

```bash
flutter test
```

Analyze (must be clean before every commit):

```bash
flutter analyze
```

## Known toolchain gap — custom_lint / riverpod_lint

As of 2026-09-04, `custom_lint` (all published versions) caps `analyzer <9.0.0`,
while `riverpod_generator ^4.0.9` (pulled in for Riverpod 3.x codegen via
`flutter_riverpod ^3.4.3`) requires `analyzer >=13.0.0`. `custom_lint` and
`riverpod_lint` cannot currently be added to this project's `dev_dependencies`
without downgrading Riverpod, which we've chosen not to do. They are
intentionally omitted from `pubspec.yaml` and from the `analyzer.plugins` list
in `analysis_options.yaml`. Revisit once custom_lint ships an
analyzer-13+-compatible release.

## Status

Slice 1 scaffold: project structure, dependencies, theme, env config, and a
smoke test verifying the app boots and shows "FixCare". Routing (go_router),
auth flow, and feature modules land in subsequent tasks.
