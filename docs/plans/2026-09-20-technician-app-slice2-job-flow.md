# Technician App Slice 2 — Drive a Job Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a verified technician drive an accepted job through its full lifecycle (en-route → arrive → diagnose+photos → parts → repair+photos → confirm-completion → confirm-cash) from a state-driven job-detail screen with camera-evidence capture.

**Architecture:** Extends the technician app's Slice-1 jobs feature. A pure `jobActionFor(state)` maps each booking state to the technician's next action; an `@riverpod` family controller loads the job from `GET /technician/jobs/mine` and adaptively polls (reusing the customer Slice-4 shape) to observe customer-side transitions; a state-driven `JobDetailScreen` renders the phase-action card. The camera-evidence pipeline (camera-only, geotag+timestamp, <500KB, presigned PUT + confirm, in-app retry queue) sits behind injectable `CameraService`/`PhotoUploadQueue` seams. Parts the technician adds are tracked app-side (the `mine` DTO carries no cart).

**Tech Stack:** Flutter 3.47, Riverpod 3.x `@riverpod`, freezed 4, dio 5, a camera plugin + image-compression + location package (per ADR-0007), `http_mock_adapter` + `flutter_test` (hermetic). Codegen: `dart run build_runner build --delete-conflicting-outputs`.

**Spec:** `docs/designs/2026-09-20-technician-app-slice2-job-flow-design.md` (+ `docs/adrs/ADR-0007-technician-camera-capture.md`)

## Global Constraints

- **`flutter analyze` 0 issues** before every commit (an `info` counts). Run from `apps/technician/`.
- **TDD:** failing test first, watch it fail, then minimal implementation. All tests hermetic — mock transport (`http_mock_adapter`) or inject fakes (`CameraService`/`PhotoUploadQueue`); never a real camera/network.
- **Repository requests use `FullHttpRequestMatcher(needsExactBody: true)`** in tests. Bodyless POSTs send NO body; bodied ones send exactly the documented body.
- **Never swallow a `Failure`** — every action maps `Result` → visible UX, surfacing the backend `{code,message}` verbatim.
- **Camera-only (Golden Rule / fraud defense):** the capture path uses `ImageSource.camera` ONLY — NO gallery/file-picker entry point anywhere in the app. A test asserts no gallery path exists.
- **Photo evidence rules (camera-evidence-capture skill):** geotag + timestamp at capture; compress <500KB before upload; queued retry upload (in-app, NOT BullMQ) with per-slot state (pending/uploading/done/failed-retry); gate buttons ("Submit diagnosis" / "Complete repair") disabled until all required slots are `done`; no PII (image bytes / precise coords) in logs.
- **Two-sided handshakes:** technician `arrive` MINTS the arrival code (no state change — the customer confirms); `confirm-completion`/`confirm-cash` the technician ENTERS the customer's code. Never both sides of one handshake.
- **`confirm-completion`/`confirm-cash` code is `z.string().length(6)`** (any 6 chars), NOT the digit-regex the customer's confirm-arrival uses — the app should send the code as entered (6 chars).
- Money is integer paise; render with the app's `rupees(int)` (from Slice-1 `core/format.dart`).
- App sends only each endpoint's allowed body; parts are catalog-priced (no client price).
- After adding freezed/@riverpod classes or a dep, re-run build_runner / `flutter pub get` and commit generated + lock files.
- Do NOT modify `apps/customer` (read as reference only). Commit as `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, no Claude trailer.

---

## File Structure

**Data (`apps/technician/lib/features/jobs/data/`):**
- `technician_job_repository.dart` — **extend** (the ~13 methods).
- `technician_job_dto.dart` — **add** `ArriveResultDto`, `PhotoSignDto`, `PhotoConfirmDto`.
- `catalog_repository.dart` + `catalog_dtos.dart` — **new** (issues/parts).

**Presentation (`apps/technician/lib/features/jobs/presentation/`):**
- `job_action.dart` — **new, pure** (`JobAction`, `jobActionFor`, `requiredPhotoKinds`).
- `job_detail_controller.dart` — **new `@riverpod`** (adaptive poll).
- `photo_capture.dart` — **new** (`CameraService`, `PhotoUploadQueue`, `photoUploadQueueProvider`, `PhotoSlot` widget).
- `diagnosis_form.dart` — **new** (2 photo slots + issue picker + parts + estimate + submit).
- `job_detail_screen.dart` — **new** (state-driven phase cards).

**Native config:** `pubspec.yaml`; iOS `Info.plist`; Android manifest.
**Backend dev tooling:** `apps/backend/src/modules/.../dev` route (guarded).

---

## Task 1: Repository extension + result DTOs

**Files:**
- Modify: `apps/technician/lib/features/jobs/data/technician_job_repository.dart`, `technician_job_dto.dart`
- Test: `apps/technician/test/jobs/technician_job_repository_test.dart` (append)

**Interfaces:**
- Consumes: existing `TechnicianJobRepository` (`_dio`, `_ok`, `_guard`, `_msg`), `Result`/`FailureKind`.
- Produces (add to the repo, all `Future<Result<...>>`):
  - `enRoute(String id)` → bodyless `POST /technician/jobs/:id/en-route` → `Result<void>`
  - `arrive(String id, {required double lat, required double lng})` → `POST …/arrive {lat,lng}` → `Result<ArriveResultDto>`
  - `diagnose(String id, String diagnosedIssueId)` → `POST …/diagnose {diagnosedIssueId}` → `Result<void>`
  - `addPart(String id, {required String partsCatalogId, required int qty})` → `POST …/parts {partsCatalogId,qty}` → `Result<String>` (the line id)
  - `removePart(String id, String partId)` → `DELETE …/parts/:partId` → `Result<void>`
  - `partsNeeded(String id)`, `partsAcquired(String id)`, `startRepair(String id)`, `completeRepair(String id)` → bodyless POSTs → `Result<void>`
  - `confirmCompletion(String id, String code)` → `POST …/confirm-completion {code}` → `Result<void>`
  - `confirmCash(String id, String code)` → `POST …/confirm-cash {code}` → `Result<CashResultDto>` (`{id,state,cashDebtPaise}`)
  - `signPhoto(String id, {required String kind, required int contentLengthBytes})` → `POST …/photos/sign {kind,contentLengthBytes}` → `Result<PhotoSignDto>`
  - `confirmPhoto(String id, {required String kind, required String key, required String capturedAt, double? geotagLat, double? geotagLng})` → `POST …/photos {kind,key,capturedAt,geotagLat?,geotagLng?}` → `Result<PhotoConfirmDto>`
- New DTOs (freezed, in `technician_job_dto.dart`):
  - `ArriveResultDto({required String arrivalCode, bool? withinGeofence})`
  - `CashResultDto({required String id, required String state, required int cashDebtPaise})`
  - `PhotoSignDto({required String url, required String key, required String expiresAt})`
  - `PhotoConfirmDto({required String id, required String kind, required String capturedAt})`

- [ ] **Step 1: Add a `_okVoid` helper** to the repo (2xx → `Ok(null)`, else `Failure(failureKindFromStatus, _msg)`) — mirror the customer repo's `_okVoid`, since several new methods are void.

- [ ] **Step 2: Write the failing tests** — append to `technician_job_repository_test.dart` (reuse the existing `dio`/`adapter`/`repo` setUp):

```dart
test('enRoute bodyless POST 200 -> Ok(void)', () async {
  adapter.onPost('/technician/jobs/b1/en-route', (s) => s.reply(200, {'id': 'b1', 'state': 'EN_ROUTE'}));
  expect(await repo.enRoute('b1'), isA<Ok<void>>());
});

test('arrive POSTs {lat,lng} and parses {arrivalCode, withinGeofence}', () async {
  adapter.onPost('/technician/jobs/b1/arrive', (s) => s.reply(200, {'arrivalCode': '482913', 'withinGeofence': true}),
      data: {'lat': 22.24, 'lng': 73.10});
  final v = (await repo.arrive('b1', lat: 22.24, lng: 73.10) as Ok<ArriveResultDto>).value;
  expect(v.arrivalCode, '482913');
  expect(v.withinGeofence, true);
});

test('arrive 422 too far -> Failure with backend message', () async {
  adapter.onPost('/technician/jobs/b1/arrive',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'You are too far from the customer location'}),
      data: {'lat': 0.0, 'lng': 0.0});
  expect((await repo.arrive('b1', lat: 0.0, lng: 0.0) as Failure).message, 'You are too far from the customer location');
});

test('diagnose POSTs {diagnosedIssueId}; 422 photo-gate surfaced', () async {
  adapter.onPost('/technician/jobs/b1/diagnose', (s) => s.reply(200, {'id': 'b1', 'state': 'DIAGNOSED'}),
      data: {'diagnosedIssueId': 'i1'});
  expect(await repo.diagnose('b1', 'i1'), isA<Ok<void>>());
  adapter.onPost('/technician/jobs/b2/diagnose',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': '2 diagnosis photos required (overview + close-up)'}),
      data: {'diagnosedIssueId': 'i1'});
  expect((await repo.diagnose('b2', 'i1') as Failure).message, '2 diagnosis photos required (overview + close-up)');
});

test('addPart POSTs {partsCatalogId,qty} 201 -> Ok(lineId); removePart DELETE 204 -> Ok(void)', () async {
  adapter.onPost('/technician/jobs/b1/parts', (s) => s.reply(201, {'id': 'line1'}),
      data: {'partsCatalogId': 'p1', 'qty': 2});
  expect((await repo.addPart('b1', partsCatalogId: 'p1', qty: 2) as Ok<String>).value, 'line1');
  adapter.onDelete('/technician/jobs/b1/parts/line1', (s) => s.reply(204, null));
  expect(await repo.removePart('b1', 'line1'), isA<Ok<void>>());
});

test('startRepair/completeRepair/partsNeeded/partsAcquired are bodyless POSTs -> Ok(void)', () async {
  for (final ep in ['start-repair', 'complete-repair', 'parts-needed', 'parts-acquired']) {
    adapter.onPost('/technician/jobs/b1/$ep', (s) => s.reply(200, {'id': 'b1', 'state': 'X'}));
  }
  expect(await repo.startRepair('b1'), isA<Ok<void>>());
  expect(await repo.completeRepair('b1'), isA<Ok<void>>());
  expect(await repo.partsNeeded('b1'), isA<Ok<void>>());
  expect(await repo.partsAcquired('b1'), isA<Ok<void>>());
});

test('completeRepair 422 photo-gate -> Failure with message', () async {
  adapter.onPost('/technician/jobs/b3/complete-repair',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': '3 repair photos required (old part removed, new packaging, installed)'}));
  expect((await repo.completeRepair('b3') as Failure).message, startsWith('3 repair photos required'));
});

test('confirmCompletion POSTs {code}; 401 invalid surfaced', () async {
  adapter.onPost('/technician/jobs/b1/confirm-completion', (s) => s.reply(200, {'id': 'b1', 'state': 'CUSTOMER_CONFIRMED'}),
      data: {'code': '123456'});
  expect(await repo.confirmCompletion('b1', '123456'), isA<Ok<void>>());
  adapter.onPost('/technician/jobs/b2/confirm-completion',
      (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired completion code'}),
      data: {'code': '000000'});
  expect((await repo.confirmCompletion('b2', '000000') as Failure).message, 'Invalid or expired completion code');
});

test('confirmCash POSTs {code}, parses {id,state,cashDebtPaise}; 422 cash-limit surfaced', () async {
  adapter.onPost('/technician/jobs/b1/confirm-cash',
      (s) => s.reply(200, {'id': 'b1', 'state': 'PAYMENT_RECEIVED', 'cashDebtPaise': 40100}),
      data: {'code': '654321'});
  final v = (await repo.confirmCash('b1', '654321') as Ok<CashResultDto>).value;
  expect(v.state, 'PAYMENT_RECEIVED');
  expect(v.cashDebtPaise, 40100);
  adapter.onPost('/technician/jobs/b2/confirm-cash',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Outstanding cash debt limit reached — please pay by UPI'}),
      data: {'code': '654321'});
  expect((await repo.confirmCash('b2', '654321') as Failure).message, startsWith('Outstanding cash debt limit reached'));
});

test('signPhoto POSTs {kind,contentLengthBytes} -> {url,key,expiresAt}; confirmPhoto POSTs the full body', () async {
  adapter.onPost('/technician/jobs/b1/photos/sign',
      (s) => s.reply(200, {'url': 'https://dev-r2.local/upload/k', 'key': 'jobs/b1/DIAGNOSIS_OVERVIEW-x.jpg', 'expiresAt': '2026-09-21T00:00:00.000Z'}),
      data: {'kind': 'DIAGNOSIS_OVERVIEW', 'contentLengthBytes': 400000});
  final sign = (await repo.signPhoto('b1', kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 400000) as Ok<PhotoSignDto>).value;
  expect(sign.key, contains('DIAGNOSIS_OVERVIEW'));
  adapter.onPost('/technician/jobs/b1/photos',
      (s) => s.reply(201, {'id': 'ph1', 'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z'}),
      data: {'kind': 'DIAGNOSIS_OVERVIEW', 'key': sign.key, 'capturedAt': '2026-09-20T10:00:00.000Z', 'geotagLat': 22.24, 'geotagLng': 73.10});
  final conf = (await repo.confirmPhoto('b1', kind: 'DIAGNOSIS_OVERVIEW', key: sign.key, capturedAt: '2026-09-20T10:00:00.000Z', geotagLat: 22.24, geotagLng: 73.10) as Ok<PhotoConfirmDto>).value;
  expect(conf.id, 'ph1');
});

test('confirmPhoto omits geotag keys entirely when not provided', () async {
  adapter.onPost('/technician/jobs/b1/photos',
      (s) => s.reply(201, {'id': 'ph2', 'kind': 'REPAIR_OLD_PART', 'capturedAt': '2026-09-20T10:00:00.000Z'}),
      data: {'kind': 'REPAIR_OLD_PART', 'key': 'jobs/b1/REPAIR_OLD_PART-y.jpg', 'capturedAt': '2026-09-20T10:00:00.000Z'});
  expect(await repo.confirmPhoto('b1', kind: 'REPAIR_OLD_PART', key: 'jobs/b1/REPAIR_OLD_PART-y.jpg', capturedAt: '2026-09-20T10:00:00.000Z'), isA<Ok<PhotoConfirmDto>>());
});
```

- [ ] **Step 3: Run to verify they fail**

Run: `flutter test test/jobs/technician_job_repository_test.dart`
Expected: FAIL — methods/DTOs undefined.

- [ ] **Step 4: Add the 4 DTOs** to `technician_job_dto.dart` (freezed + fromJson), per the Interfaces block.

- [ ] **Step 5: Add the repo methods.** Bodyless ones via `_okVoid`; bodied ones pass `data:` and map via `_okVoid` (void) or `_ok<Dto>` (parsed). `addPart` parses `data['id']` as the line id. `confirmPhoto` must build its `data` map with the geotag keys ONLY when both are non-null (so the "omits geotag" test passes and the backend's both-or-neither refine holds):

```dart
Future<Result<PhotoConfirmDto>> confirmPhoto(String id, {required String kind, required String key, required String capturedAt, double? geotagLat, double? geotagLng}) => _guard(() async {
  final body = <String, dynamic>{'kind': kind, 'key': key, 'capturedAt': capturedAt};
  if (geotagLat != null && geotagLng != null) { body['geotagLat'] = geotagLat; body['geotagLng'] = geotagLng; }
  final res = await _dio.post('/technician/jobs/$id/photos', data: body);
  return _ok<PhotoConfirmDto>(res, (d) => PhotoConfirmDto.fromJson((d as Map).cast<String, dynamic>()));
});
```

- [ ] **Step 6: build_runner + run + analyze**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/jobs/technician_job_repository_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/jobs/data/technician_job_repository.dart apps/technician/lib/features/jobs/data/technician_job_dto.dart apps/technician/lib/features/jobs/data/technician_job_dto.g.dart apps/technician/lib/features/jobs/data/technician_job_dto.freezed.dart apps/technician/test/jobs/technician_job_repository_test.dart
git commit -m "feat(technician): job-flow repository methods (en-route..confirm-cash, photos) + result DTOs (slice 2)"
```

---

## Task 2: CatalogRepository (issues + parts)

**Files:**
- Create: `apps/technician/lib/features/jobs/data/catalog_dtos.dart`, `catalog_repository.dart`
- Test: `apps/technician/test/jobs/catalog_repository_test.dart`

**Interfaces:**
- Produces:
  - `DiagnosedIssueDto({required String id, required String name, required String categoryId, required String status})` + fromJson.
  - `PartCatalogDto({required String id, required String sku, required String name, String? categoryId, required int ceilingPricePaise, required String status})` + fromJson.
  - `CatalogRepository.issues({String? categoryId}) -> Result<List<DiagnosedIssueDto>>` → `GET /catalog/issues?categoryId=`
  - `CatalogRepository.parts({String? categoryId}) -> Result<List<PartCatalogDto>>` → `GET /catalog/parts?categoryId=`
  - `catalogRepositoryProvider`.

- [ ] **Step 1: Write the failing test** — `test/jobs/catalog_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';

void main() {
  late Dio dio; late DioAdapter adapter; late CatalogRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = CatalogRepository(dio);
  });

  test('issues(categoryId) GETs the filtered list', () async {
    adapter.onGet('/catalog/issues', (s) => s.reply(200, [
      {'id': 'i1', 'name': 'Fan capacitor failure', 'categoryId': 'c1', 'status': 'ACTIVE'},
    ]), queryParameters: {'categoryId': 'c1'});
    final v = (await repo.issues(categoryId: 'c1') as Ok<List<DiagnosedIssueDto>>).value;
    expect(v.single.name, 'Fan capacitor failure');
  });

  test('parts(categoryId) GETs the list incl. a generic null-category part', () async {
    adapter.onGet('/catalog/parts', (s) => s.reply(200, [
      {'id': 'p1', 'sku': 'FAN-CAP', 'name': 'Fan capacitor 2.5 MFD', 'categoryId': 'c1', 'ceilingPricePaise': 12000, 'status': 'ACTIVE'},
      {'id': 'p2', 'sku': 'GEN', 'name': 'Generic', 'categoryId': null, 'ceilingPricePaise': 5000, 'status': 'ACTIVE'},
    ]), queryParameters: {'categoryId': 'c1'});
    final v = (await repo.parts(categoryId: 'c1') as Ok<List<PartCatalogDto>>).value;
    expect(v, hasLength(2));
    expect(v[1].categoryId, isNull);
  });

  test('issues 500 -> Failure(server)', () async {
    adapter.onGet('/catalog/issues', (s) => s.reply(500, {'code': 'X', 'message': 'boom'}));
    expect((await repo.issues() as Failure).kind, FailureKind.server);
  });
}
```

- [ ] **Step 2: Run — fail.** `flutter test test/jobs/catalog_repository_test.dart`

- [ ] **Step 3: Create the DTOs + repository.** Mirror `technician_job_repository.dart`'s `_guard`/`_parseList` idiom (a 2xx non-list body → `Failure(server)`). Pass `queryParameters: {if (categoryId != null) 'categoryId': categoryId}`.

- [ ] **Step 4: build_runner + run + analyze** → pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/data/catalog_dtos.dart apps/technician/lib/features/jobs/data/catalog_repository.dart apps/technician/lib/features/jobs/data/catalog_dtos.g.dart apps/technician/lib/features/jobs/data/catalog_dtos.freezed.dart apps/technician/test/jobs/catalog_repository_test.dart
git commit -m "feat(technician): CatalogRepository — issues + parts pickers (slice 2)"
```

---

## Task 3: `job_action.dart` — pure state→action mapper

**Files:**
- Create: `apps/technician/lib/features/jobs/presentation/job_action.dart`
- Test: `apps/technician/test/jobs/job_action_test.dart`

**Interfaces:**
- Consumes: `TechnicianJobDto` (needs `.state`).
- Produces:
  - `enum JobAction { enRoute, arrive, waitingConfirm, diagnose, waitingApproval, startRepair, partsNeeded, partsAcquired, completeRepair, confirmCompletion, confirmCash, terminal }`
  - `JobAction jobActionFor(TechnicianJobDto b)`
  - `List<String> requiredPhotoKinds(String state)` — `['DIAGNOSIS_OVERVIEW','DIAGNOSIS_CLOSEUP']` for ARRIVED, `['REPAIR_OLD_PART','REPAIR_NEW_PACKAGING','REPAIR_INSTALLED']` for REPAIR_IN_PROGRESS, else `[]`.
  - `bool isTerminalJob(TechnicianJobDto b)` — state ∈ {PAYMENT_RECEIVED, CLOSED, CANCELLED_BY_CUSTOMER, CANCELLED_BY_TECHNICIAN, DECLINED_BY_CUSTOMER}. (DECLINED is terminal for the TECHNICIAN's job view EXCEPT it still allows confirm-cash — see note; treat DECLINED as non-terminal so the poll keeps running for the cash step, and jobActionFor(DECLINED)→confirmCash.)

**Mapping (from the design table):**
- CREATED/DISPATCHED → `terminal` (shouldn't appear in a tech's mine list pre-accept, but safe) — actually these won't be assigned; map unknown/pre-accept → `terminal` (read-only).
- ACCEPTED → enRoute; EN_ROUTE → arrive; ARRIVED → diagnose; DIAGNOSED → waitingApproval; CUSTOMER_APPROVED → startRepair; PARTS_REQUESTED → partsAcquired; PARTS_ACQUIRED → startRepair; REPAIR_IN_PROGRESS → completeRepair; REPAIR_COMPLETE → confirmCompletion; CUSTOMER_CONFIRMED → confirmCash; DECLINED_BY_CUSTOMER → confirmCash; PAYMENT_RECEIVED/CLOSED/CANCELLED_* → terminal; unknown → terminal.

- [ ] **Step 1: Write the failing test** — `test/jobs/job_action_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_dto.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_action.dart';

TechnicianJobDto _j(String state) => TechnicianJobDto.fromJson({
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Svc', 'requiredSkill': 'FAN'}, 'zone': {'name': 'Padra'},
  'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'x', 'line2': null, 'landmark': null, 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
});

void main() {
  final cases = <String, JobAction>{
    'ACCEPTED': JobAction.enRoute,
    'EN_ROUTE': JobAction.arrive,
    'ARRIVED': JobAction.diagnose,
    'DIAGNOSED': JobAction.waitingApproval,
    'CUSTOMER_APPROVED': JobAction.startRepair,
    'PARTS_REQUESTED': JobAction.partsAcquired,
    'PARTS_ACQUIRED': JobAction.startRepair,
    'REPAIR_IN_PROGRESS': JobAction.completeRepair,
    'REPAIR_COMPLETE': JobAction.confirmCompletion,
    'CUSTOMER_CONFIRMED': JobAction.confirmCash,
    'DECLINED_BY_CUSTOMER': JobAction.confirmCash,
    'PAYMENT_RECEIVED': JobAction.terminal,
    'CLOSED': JobAction.terminal,
    'CANCELLED_BY_CUSTOMER': JobAction.terminal,
    'CANCELLED_BY_TECHNICIAN': JobAction.terminal,
  };
  cases.forEach((state, expected) {
    test('jobActionFor($state) -> $expected', () => expect(jobActionFor(_j(state)), expected));
  });

  test('requiredPhotoKinds by state', () {
    expect(requiredPhotoKinds('ARRIVED'), ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']);
    expect(requiredPhotoKinds('REPAIR_IN_PROGRESS'), ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED']);
    expect(requiredPhotoKinds('ACCEPTED'), isEmpty);
  });

  test('unknown state -> terminal (never throws / never a wrong action)', () {
    expect(jobActionFor(_j('SOME_FUTURE_STATE')), JobAction.terminal);
  });
}
```

- [ ] **Step 2: Run — fail.** **Step 3: Create `job_action.dart`** (pure Dart, imports only the DTO) with the switch mapping above. **Step 4: Run + analyze** → pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/job_action.dart apps/technician/test/jobs/job_action_test.dart
git commit -m "feat(technician): job_action — pure state -> technician action mapper (slice 2)"
```

---

## Task 4: `JobDetail` adaptive-poll controller

**Files:**
- Create: `apps/technician/lib/features/jobs/presentation/job_detail_controller.dart`
- Test: `apps/technician/test/jobs/job_detail_controller_test.dart`

**Interfaces:**
- Consumes: `technicianJobRepositoryProvider` (its `mine()`), `TechnicianJobDto`, `isTerminalJob` (Task 3), `Result`.
- Produces: `@riverpod class JobDetail extends _$JobDetail` with `Future<TechnicianJobDto> build(String bookingId)` + `refetch()`; `jobDetailProvider`. Poll interval `const jobPollInterval = Duration(seconds: 5)`.

**Design notes:** There is no single-job GET — so the controller calls `mine()` and finds the job by id (`firstWhere(id)`); if not found → throw (first load) / keep-last-good (poll). Otherwise identical to the customer Slice-4 `BookingTracking` controller: `_arm` starts a 5s `Timer.periodic` only if `!isTerminalJob(dto)`; poll `Ok` → `state = AsyncData`, re-arm; `Failure` OR not-found → keep last-good; `refetch()` reloads, no AsyncLoading flash; `ref.onDispose` cancels the timer; guard callbacks with `ref.mounted`. Store `bookingId` in a field (reuse Slice-4's `_bookingId` pattern).

- [ ] **Step 1: Write the failing test** — `test/jobs/job_detail_controller_test.dart`, using `fakeAsync` + a scripted fake repo whose `mine()` returns a settable `Result<List<TechnicianJobDto>>` (the controller finds the job by id within the list). Assert: first load finds the job; poll advances every 5s; stops once terminal (PAYMENT_RECEIVED); keep-last-good when `mine()` returns Failure; first-load not-found → AsyncError. (Mirror `apps/customer/test/booking/booking_tracking_controller_test.dart` structure — read it for the fakeAsync + ProviderContainer harness.)

- [ ] **Step 2: Run — fail.** **Step 3: Create the controller** (adapt the customer Slice-4 controller; `_fetchOrThrow` = `mine()` then `firstWhere(id)`, throw if absent). **Step 4: build_runner + run + analyze** → pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/job_detail_controller.dart apps/technician/lib/features/jobs/presentation/job_detail_controller.g.dart apps/technician/test/jobs/job_detail_controller_test.dart
git commit -m "feat(technician): JobDetail controller — adaptive poll over mine(), find-by-id, refetch (slice 2)"
```

---

## Task 5: Camera-evidence photo pipeline (dep + ADR + seams)

**Files:**
- Modify: `apps/technician/pubspec.yaml` (+ lock), `apps/technician/ios/Runner/Info.plist`, `apps/technician/android/app/src/main/AndroidManifest.xml`
- Create: `apps/technician/lib/features/jobs/presentation/photo_capture.dart`
- Test: `apps/technician/test/jobs/photo_upload_queue_test.dart`

**Interfaces:**
- Produces:
  - `abstract class CameraService { Future<CapturedPhoto?> capture(); }` where `CapturedPhoto({required List<int> bytes, required String capturedAt, double? lat, double? lng})`. A real `ImagePickerCameraService` implements it via `ImagePicker().pickImage(source: ImageSource.camera)` + location + compress; the constraint: **no `ImageSource.gallery` anywhere**. `cameraServiceProvider` (overridable/fakeable).
  - `enum PhotoSlotState { none, uploading, done, failedRetry }`
  - `class PhotoUploadQueue` — `Future<void> enqueue({required String bookingId, required String kind, required CapturedPhoto photo})`; exposes a `PhotoSlotState stateOf(String kind)` + a listenable/`Notifier` of `Map<String,PhotoSlotState>` so the UI observes per-slot state. On enqueue it runs sign → PUT-to-url → confirm; on failure marks `failedRetry` and retries with backoff. `photoUploadQueueProvider` (family by bookingId, or a single provider keyed internally).
  - `PhotoSlot` widget — shows a slot's label + state + a capture/retake button; on tap calls `CameraService.capture()` then `queue.enqueue`.

**Design notes:**
- `flutter pub add image_picker flutter_image_compress geolocator` (or equivalents); pin versions; commit pubspec + lock. Add iOS `NSCameraUsageDescription` + `NSLocationWhenInUseUsageDescription`; Android `CAMERA` + `ACCESS_FINE_LOCATION` (runtime-requested).
- The PUT step: `dio.put(sign.url, data: Stream.fromIterable([bytes]), options: Options(headers: {'Content-Length': bytes.length}, contentType: 'image/jpeg'))`. **Dev affordance:** if `sign.url` contains `dev-r2.local`, instead of the PUT call the dev hook `POST /dev/photos/mark-uploaded {key}` (Task 8 adds the backend route) so `confirm` succeeds locally. Detect via `url.contains('dev-r2.local')`.
- Compress to <500KB before measuring `contentLengthBytes` for `signPhoto`.
- The queue is the tested unit; the real `CameraService`/geolocator/compress are on-device only (thin, injected).

- [ ] **Step 1: Add deps + permissions** (`flutter pub add ...`; Info.plist + manifest entries). Run `flutter pub get`.

- [ ] **Step 2: Write the failing test** — `test/jobs/photo_upload_queue_test.dart` with a fake repo (records sign/confirm calls + a settable outcome) and a fake "PUT" seam:
  - enqueue a `CapturedPhoto` → the queue calls `signPhoto(kind, contentLengthBytes)`, then PUTs, then `confirmPhoto` with `{kind, key, capturedAt, geotag both-or-neither}`; slot state goes `uploading` → `done`.
  - a failing PUT/confirm → slot `failedRetry`; a retry then succeeds → `done`.
  - a photo with no lat/lng → confirm called without geotag keys.

- [ ] **Step 3: Run — fail.** **Step 4: Implement `photo_capture.dart`** (the seams + queue + `PhotoSlot`). Keep `CameraService.capture()` camera-only. **Step 5: run + analyze** → pass; clean.

- [ ] **Step 6: Camera-only guard test** — add a test asserting the concrete `ImagePickerCameraService` never references `ImageSource.gallery` (e.g. a source-level guard: the implementation only passes `ImageSource.camera`). If a pure-unit assertion isn't feasible, add a code comment + a review note; prefer a test that constructs the service and confirms its capture path is camera-only via the injected picker seam.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/pubspec.yaml apps/technician/pubspec.lock apps/technician/ios/Runner/Info.plist apps/technician/android/app/src/main/AndroidManifest.xml apps/technician/lib/features/jobs/presentation/photo_capture.dart apps/technician/test/jobs/photo_upload_queue_test.dart
git commit -m "feat(technician): camera-evidence photo pipeline — camera-only capture + retry upload queue (slice 2, ADR-0007)"
```

---

## Task 6: `job_detail_screen.dart` — the non-photo phase cards + route

**Files:**
- Create: `apps/technician/lib/features/jobs/presentation/job_detail_screen.dart`
- Modify: `apps/technician/lib/core/router/app_router.dart` (add `/job/:id`), `apps/technician/lib/features/jobs/presentation/jobs_home_screen.dart` (tap a my-job → push `/job/:id`)
- Test: `apps/technician/test/jobs/job_detail_screen_test.dart`

**Interfaces:**
- Consumes: `jobDetailProvider` + `.notifier.refetch()` (Task 4); `jobActionFor` (Task 3); `technicianJobRepositoryProvider` (Task 1); `rupees`, theme, `Result`.
- Produces: `JobDetailScreen({required String bookingId})`; route `/job/:id`.

**Design notes (this task wires every card EXCEPT the two photo phases — diagnose card is a placeholder here, filled in Task 7; repair card's photo slots are Task 8; but en-route/arrive/parts-needed/parts-acquired/start-repair/confirm-completion/confirm-cash/terminal are all done here):**
- `ConsumerStatefulWidget`. `ref.watch(jobDetailProvider(bookingId))` → `AsyncValue<TechnicianJobDto>`; loading → spinner; error → retry (`ref.invalidate`); data → the job info card (service, address, masked phone, slot, `rupees` fees) + the phase-action card via `jobActionFor`.
- Cards + keys:
  - `enRoute` → button `Key('enRouteBtn')` → `repo.enRoute` → refetch.
  - `arrive` → button `Key('arriveBtn')` → get one-shot location (inject a `LocationService` seam; in tests a fake) → `repo.arrive(lat,lng)`; on `Ok` show the arrival code (`Key('arrivalCode')` = `arrivalCode`) + "read this to your customer; waiting for them to confirm…"; 422 geofence → inline message. (No state change — the poll flips to ARRIVED when the customer confirms.)
  - `waitingApproval` → read-only "waiting for the customer to approve the estimate".
  - `startRepair` → `Key('startRepairBtn')` → `repo.startRepair` → refetch. (If cart non-empty, ALSO offer `Key('partsNeededBtn')` → `partsNeeded`.)
  - `partsAcquired` → `Key('partsAcquiredBtn')` → `repo.partsAcquired` → refetch.
  - `confirmCompletion` → a 6-char code field `Key('completionCodeField')` + `Key('confirmCompletionBtn')` → `repo.confirmCompletion(code)` → refetch; 401/409 inline.
  - `confirmCash` → a 6-char code field `Key('cashCodeField')` + `Key('confirmCashBtn')` → `repo.confirmCash(code)` → refetch; 422 cash-limit inline.
  - `diagnose` → render the `DiagnosisForm` (Task 7) — for THIS task, a placeholder `Key('diagnosePlaceholder')` "diagnosis form — task 7"; Task 7 replaces it.
  - `completeRepair` → render the repair-photos card (Task 8) — for THIS task, a placeholder `Key('repairPlaceholder')`; Task 8 replaces it.
  - `terminal` → summary (state, "paid"/"cancelled"/"closed"). Root `Key('jobDetailScreen')`.
- Per-card busy flag; every action success → `refetch`; `Failure` → SnackBar (409 stale) or inline (geofence/code). Guard `setState` with `if(mounted)`.

- [ ] **Step 1: Write the failing widget tests** — `test/jobs/job_detail_screen_test.dart` (fake repo recording calls + fake `jobDetailProvider` state + fake location seam; mirror Slice-1 `jobs_home_widget_test.dart` harness). Cover: ACCEPTED→enRoute tap calls `enRoute`; EN_ROUTE→arrive tap calls `arrive` and on Ok shows `arrivalCode`; arrive 422 → inline "too far"; CUSTOMER_APPROVED→startRepair tap calls `startRepair`; REPAIR_COMPLETE→enter code + confirm calls `confirmCompletion(code)`; CUSTOMER_CONFIRMED→enter code + confirm calls `confirmCash(code)`; terminal → summary; diagnose/completeRepair states show their placeholders (assert the placeholder keys, replaced in T7/T8).

- [ ] **Step 2: Run — fail. Step 3: Implement the screen + route + jobs-home tap. Step 4: run + analyze** → pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/lib/core/router/app_router.dart apps/technician/lib/features/jobs/presentation/jobs_home_screen.dart apps/technician/test/jobs/job_detail_screen_test.dart
git commit -m "feat(technician): job-detail screen — state-driven phase cards (en-route..cash) + route (slice 2)"
```

---

## Task 7: Diagnosis form (2 photos + issue picker + parts + estimate)

**Files:**
- Create: `apps/technician/lib/features/jobs/presentation/diagnosis_form.dart`
- Modify: `job_detail_screen.dart` (replace the `diagnose` placeholder with `DiagnosisForm`)
- Test: `apps/technician/test/jobs/diagnosis_form_test.dart`

**Interfaces:**
- Consumes: `catalogRepositoryProvider` (issues + parts), `technicianJobRepositoryProvider` (addPart/removePart/diagnose), `photoUploadQueueProvider` + `PhotoSlot` (Task 5, the 2 diagnosis slots), `jobDetailProvider.notifier.refetch()`, `rupees`.
- Produces: `DiagnosisForm({required TechnicianJobDto job})`.

**Design notes:**
- Two `PhotoSlot`s: `DIAGNOSIS_OVERVIEW`, `DIAGNOSIS_CLOSEUP`.
- Issue picker: `catalog.issues(categoryId: <job category>)` → a dropdown/radio (`Key('issuePicker')`). (The job's categoryId isn't in the DTO directly — derive from `requiredSkill`? No — the DTO lacks categoryId. RULING for the implementer: `issues()` with NO categoryId returns all ACTIVE issues; filter client-side is not possible without the category. Call `repo.issues()` (all) and let the tech pick; the backend re-validates category-match on diagnose and returns 422 `'That issue does not apply to this service'` if wrong — surface that inline. This keeps Slice 2 single-repo; a categoryId on the DTO is a deferred follow-up.)
- Parts: `catalog.parts()` list → add (qty stepper, `Key('addPartBtn_<id>')`) → `repo.addPart`; added parts tracked in local state with their line ids; remove (`Key('removePartBtn_<lineId>')`) → `repo.removePart`. Show an **indicative estimate**: `rupees(job.laborPaise + Σ(part.ceilingPricePaise*qty) − job.visitFeePaise)` floored at 0, labeled "indicative".
- Submit `Key('submitDiagnosisBtn')` → **disabled until both diagnosis photos are `done`** (read `photoUploadQueue.stateOf(kind)`) AND an issue is selected → `repo.diagnose(issueId)` → on Ok refetch; 422 (photo-gate or category) → inline.

- [ ] **Step 1: Write the failing widget tests** (fake catalog + job repos + fake photo queue with settable slot states): issue picker renders from `issues()`; add/remove part calls the repo + updates the estimate; submit disabled until both photos `done` + issue chosen; submit calls `diagnose(issueId)`; a 422 category error shows inline.

- [ ] **Step 2: Run — fail. Step 3: Implement `DiagnosisForm` + wire into the screen's diagnose branch. Step 4: run + analyze** → pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/diagnosis_form.dart apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/test/jobs/diagnosis_form_test.dart
git commit -m "feat(technician): diagnosis form — 2 photos + issue picker + parts + estimate + submit (slice 2)"
```

---

## Task 8: Repair phase (3 photos) + dev photo hook + wire-up

**Files:**
- Modify: `apps/technician/lib/features/jobs/presentation/job_detail_screen.dart` (replace the `completeRepair` placeholder)
- Create: `apps/backend/src/modules/dev/dev.routes.ts` (or similar) — the dev-only mark-uploaded route; register it in `app.ts` guarded by `NODE_ENV !== 'production'`
- Test: `apps/technician/test/jobs/job_detail_screen_test.dart` (append repair cases); `apps/backend/tests/dev/mark-uploaded.test.ts`

**Interfaces:**
- Consumes: `photoUploadQueueProvider` + `PhotoSlot` (3 repair slots), `technicianJobRepositoryProvider.completeRepair`.
- Produces: the repair-phase card; the backend `POST /dev/photos/mark-uploaded {key}` route (non-prod only).

**Design notes:**
- Repair card: three `PhotoSlot`s (`REPAIR_OLD_PART`, `REPAIR_NEW_PACKAGING`, `REPAIR_INSTALLED`) + `Key('completeRepairBtn')` **disabled until all 3 are `done`** → `repo.completeRepair` → refetch; 422 → inline.
- Backend dev route: `POST /dev/photos/mark-uploaded` — body `{key: string}`; guarded so it is ONLY registered/served when `config.NODE_ENV !== 'production'` (return 404 otherwise, or don't register it). It calls the module-singleton `photoStorage`'s `markUploaded(key)` — **only `DevPhotoStorage` has that method**, so cast/guard: if `photoStorage` is a `DevPhotoStorage`, call it; else 404. This makes the app's `confirm` succeed locally after it "PUT"s to the dev hook. Add a vitest asserting: in test env the route marks a key and a subsequent `objectExists` (via a confirm) passes; and that it is a no-op/404 shape when not dev. (Keep it tiny; it's dev tooling.)

- [ ] **Step 1: Write the failing tests** — (a) widget: REPAIR_IN_PROGRESS renders 3 slots, completeRepair disabled until all 3 `done`, then tap calls `completeRepair`; (b) backend vitest: `POST /dev/photos/mark-uploaded {key}` marks the key so a photo `confirm` for that key then succeeds (in the test/dev env).

- [ ] **Step 2: Run — fail. Step 3: Implement** the repair card + the guarded backend route. **Step 4: run** the technician suite + the backend test + analyze.

- [ ] **Step 5: Full technician suite + backend build**

Run (from `apps/technician`): `flutter test && flutter analyze`
Run (from `apps/backend`): `set -a && source .env && set +a && pnpm vitest run tests/dev/mark-uploaded.test.ts && pnpm build`
Expected: all pass; analyze clean; tsc clean.

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/test/jobs/job_detail_screen_test.dart apps/backend/src/modules/dev/dev.routes.ts apps/backend/src/app.ts apps/backend/tests/dev/mark-uploaded.test.ts
git commit -m "feat(technician): repair-phase 3-photo gate + complete-repair; dev mark-uploaded hook for local photo testing (slice 2)"
```

---

## Self-Review

**1. Spec coverage:**
- Repo: en-route/arrive/diagnose/parts±/parts-needed/parts-acquired/start-repair/complete-repair/confirm-completion/confirm-cash/photo sign+confirm → Task 1. ✓
- Catalog issues/parts → Task 2. ✓
- `jobActionFor` + requiredPhotoKinds → Task 3. ✓
- Adaptive-poll controller over `mine()` (no single-job GET) → Task 4. ✓
- Camera-evidence pipeline (camera-only, geotag+timestamp, <500KB, presigned PUT+confirm, retry queue, per-slot state) + ADR-0007 deps/permissions → Task 5. ✓
- State-driven screen, non-photo cards, two-sided handshake UI (arrive shows code; completion/cash enter customer's code) → Task 6. ✓
- Diagnosis form (2 photos + issue + parts + estimate) → Task 7. ✓
- Repair 3-photo gate + complete + dev mark-uploaded hook → Task 8. ✓
- App-side parts tracking → Task 7 (local state). ✓
- Gate buttons disabled until photos done → Tasks 7 (diagnosis) + 8 (repair). ✓
- Deferred smoke + categoryId-on-DTO → noted (spec + Task 7 ruling). ✓

**2. Placeholder scan:** No TBD/TODO in production steps. Tasks 6/7/8 use explicit inter-task placeholders (diagnose/repair cards) with named keys, each replaced by the next task — a deliberate, tracked decomposition, not a gap. Task 7 carries a RULING (issue picker uses all-issues since the DTO lacks categoryId; backend re-validates) — a real decision, not a placeholder.

**3. Type consistency:** `TechnicianJobDto`, `ArriveResultDto`/`CashResultDto`/`PhotoSignDto`/`PhotoConfirmDto`, `DiagnosedIssueDto`/`PartCatalogDto`, `JobAction`/`jobActionFor`/`requiredPhotoKinds`/`isTerminalJob`, `jobDetailProvider`/`refetch`, `CameraService`/`CapturedPhoto`/`PhotoUploadQueue`/`PhotoSlotState`/`photoUploadQueueProvider`, the ~13 repo methods, and the widget keys (`enRouteBtn`/`arriveBtn`/`arrivalCode`/`startRepairBtn`/`confirmCompletionBtn`/`confirmCashBtn`/`submitDiagnosisBtn`/`completeRepairBtn`/`jobDetailScreen`) are used consistently across tasks. Photo-kind strings match the backend enum exactly. `confirm-completion`/`confirm-cash` send the 6-char code as entered.
