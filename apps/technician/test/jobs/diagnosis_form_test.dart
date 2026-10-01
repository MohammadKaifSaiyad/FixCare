import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/diagnosis_form.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_action.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_controller.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';

Map<String, dynamic> _jobJson({
  String id = 'b1',
  String state = 'ARRIVED',
  List<Map<String, dynamic>> photos = const [],
  String? categoryId = 'cat-fan',
}) => {
  'id': id, 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN', 'categoryId': categoryId},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': null, 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': photos,
};

TechnicianJobDto _dto({String id = 'b1', List<Map<String, dynamic>> photos = const [], String? categoryId = 'cat-fan'}) =>
    TechnicianJobDto.fromJson(_jobJson(id: id, photos: photos, categoryId: categoryId));

/// Fake catalog repo: issues() is scripted (Ok or Failure), with a call count
/// so the retry test can assert a re-fetch happened.
class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());

  Result<List<DiagnosedIssueDto>> issuesResult =
      const Ok([DiagnosedIssueDto(id: 'i1', name: 'Fan capacitor failure', categoryId: 'c1', status: 'ACTIVE')]);
  int issuesCalls = 0;
  final List<String?> issuesCategoryArgs = [];
  List<PartCatalogDto> catalogParts = const [];

  @override
  Future<Result<List<DiagnosedIssueDto>>> issues({String? categoryId}) async {
    issuesCategoryArgs.add(categoryId);
    issuesCalls++;
    return issuesResult;
  }

  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async => Ok(catalogParts);
}

/// Fake job repo: handles job(id) (recorded, for asserting a refetch happened),
/// diagnose() (recorded + scripted), and the photo sign/confirm calls the
/// queue drives (always succeed immediately — no retry/backoff involved in
/// these tests).
class _FakeJobRepo extends TechnicianJobRepository {
  // Private `_job`: a public `job` field would collide with TechnicianJobRepository.job(id).
  _FakeJobRepo({required this._job}) : super(Dio());

  final TechnicianJobDto _job;
  int jobCalls = 0;
  int diagnoseCalls = 0;
  ({String id, String issueId})? lastDiagnose;
  Result<void> diagnoseResult = const Ok(null);
  Completer<void>? addGate;

  @override
  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) async {
    if (addGate != null) await addGate!.future;
    return const Ok('l1');
  }

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async =>
      throw StateError('the job-detail controller must not call mine()');

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    return Ok(TechnicianJobDetailDto(job: _job));
  }

  @override
  Future<Result<void>> diagnose(String id, String diagnosedIssueId) async {
    diagnoseCalls++;
    lastDiagnose = (id: id, issueId: diagnosedIssueId);
    return diagnoseResult;
  }

  @override
  Future<Result<PhotoSignDto>> signPhoto(String id, {required String kind, required int contentLengthBytes}) async {
    return Ok(PhotoSignDto(url: 'https://r2.example.com/upload', key: 'key-$kind', expiresAt: 'x'));
  }

  @override
  Future<Result<PhotoConfirmDto>> confirmPhoto(String id,
      {required String kind, required String key, required String capturedAt, double? geotagLat, double? geotagLng}) async {
    return Ok(PhotoConfirmDto(id: 'p-$kind', kind: kind, capturedAt: capturedAt));
  }
}

CapturedPhoto _photo() => const CapturedPhoto(bytes: [1, 2, 3], capturedAt: '2026-09-20T09:30:00.000Z');

Future<void> _pump(
  WidgetTester tester, {
  required TechnicianJobDto job,
  required _FakeJobRepo jobRepo,
  required _FakeCatalogRepo catalogRepo,
  required PhotoUploadQueue queue,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        technicianJobRepositoryProvider.overrideWithValue(jobRepo),
        catalogRepositoryProvider.overrideWithValue(catalogRepo),
        photoUploadQueueProvider.overrideWithValue(queue),
      ],
      // JobDetailScreen watches jobDetailProvider for the life of the form; mirror that so the autoDispose
      // notifier the parts section refetches after a cart edit is not torn down mid-flight.
      child: Consumer(
        builder: (context, ref, child) {
          ref.listen(jobDetailProvider(job.id), (_, _) {});
          return child!;
        },
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DiagnosisForm(detail: TechnicianJobDetailDto(job: job))))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Dispose the tree — a `DiagnosisForm` submit reaches into `jobDetailProvider`,
/// which arms a 5s poll timer once built; this cancels it so the test doesn't
/// fail with "A Timer is still pending".
Future<void> _disposeTree(WidgetTester tester) => tester.pumpWidget(const SizedBox());

FilledButton _submitBtn(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('submitDiagnosisBtn')));

List<Map<String, dynamic>> _bothServerPhotos() => [
  {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T09:30:00.000Z', 'url': 'https://r2.example.com/a'},
  {'kind': 'DIAGNOSIS_CLOSEUP', 'capturedAt': '2026-09-20T09:31:00.000Z', 'url': 'https://r2.example.com/b'},
];

/// Scroll a keyed widget into view, then tap it (the form is taller than the test viewport).
Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<void> _pickIssue(WidgetTester tester) async {
  await _tapKey(tester, const Key('issuePicker'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fan capacitor failure').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('issue picker lists issues from issues()', (tester) async {
    final job = _dto();
    final catalogRepo = _FakeCatalogRepo()
      ..issuesResult = const Ok([
        DiagnosedIssueDto(id: 'i1', name: 'Fan capacitor failure', categoryId: 'c1', status: 'ACTIVE'),
        DiagnosedIssueDto(id: 'i2', name: 'Bearing worn out', categoryId: 'c1', status: 'ACTIVE'),
      ]);
    final jobRepo = _FakeJobRepo(job: job);
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    await _tapKey(tester, const Key('issuePicker'));
    await tester.pumpAndSettle();
    expect(find.text('Fan capacitor failure'), findsWidgets);
    expect(find.text('Bearing worn out'), findsWidgets);

    await _disposeTree(tester);
  });

  testWidgets('submit disabled with nothing captured/selected', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    expect(_submitBtn(tester).onPressed, isNull);
    expect(find.text('Take both photos and pick the issue to continue.'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('submit disabled with both photos but no issue selected', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await queue.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
    await queue.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    expect(_submitBtn(tester).onPressed, isNull);

    await _disposeTree(tester);
  });

  testWidgets('submit disabled with issue selected but only one photo', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await queue.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    await _tapKey(tester, const Key('issuePicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    expect(_submitBtn(tester).onPressed, isNull);

    await _disposeTree(tester);
  });

  testWidgets(
      'ENABLED with issue + one photo done in queue + other on server -> tap diagnoses and refetches',
      (tester) async {
    final job = _dto(photos: [
      {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
    ]);
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await queue.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    await _tapKey(tester, const Key('issuePicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    expect(_submitBtn(tester).onPressed, isNotNull);

    final jobCallsBefore = jobRepo.jobCalls;
    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendEstimateBtn')));
    await tester.pumpAndSettle();

    expect(jobRepo.diagnoseCalls, 1);
    expect(jobRepo.lastDiagnose, (id: 'b1', issueId: 'i1'));
    expect(jobRepo.jobCalls, greaterThan(jobCallsBefore));

    await _disposeTree(tester);
  });

  testWidgets('diagnose Failure shows the category-mismatch message inline', (tester) async {
    final job = _dto(photos: [
      {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
      {'kind': 'DIAGNOSIS_CLOSEUP', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
    ]);
    final jobRepo = _FakeJobRepo(job: job)
      ..diagnoseResult = const Failure(FailureKind.validation, 'That issue does not apply to this service');
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    await _tapKey(tester, const Key('issuePicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendEstimateBtn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('diagnosisError')), findsOneWidget);
    expect(find.text('That issue does not apply to this service'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('issues() Failure shows the message + issuesRetry, which re-fetches on tap', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo()
      ..issuesResult = const Failure(FailureKind.server, 'Could not load the issue list');
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    expect(find.text('Could not load the issue list'), findsOneWidget);
    expect(find.byKey(const Key('issuesRetry')), findsOneWidget);

    final callsBefore = catalogRepo.issuesCalls;
    await _tapKey(tester, const Key('issuesRetry'));
    await tester.pumpAndSettle();

    expect(catalogRepo.issuesCalls, greaterThan(callsBefore));

    await _disposeTree(tester);
  });

  testWidgets('submit enables live when the queue flips the missing slot to done (notify only)', (tester) async {
    final job = _dto(photos: [
      {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
    ]);
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});

    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    await _tapKey(tester, const Key('issuePicker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    // Still missing DIAGNOSIS_CLOSEUP -> disabled.
    expect(_submitBtn(tester).onPressed, isNull);

    // The queue flips the missing slot to done (this is what enqueue does
    // internally via notifyListeners) — no re-pump of the widget tree, just a
    // single frame so the ListenableBuilder picks it up.
    await queue.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());
    await tester.pump();

    expect(_submitBtn(tester).onPressed, isNotNull);

    await _disposeTree(tester);
  });

  testWidgets('slots are built from requiredPhotoKinds(ARRIVED) with their labels (slots == gate)',
      (tester) async {
    final job = _dto(photos: [
      {'kind': 'DIAGNOSIS_CLOSEUP', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
    ]);
    final jobRepo = _FakeJobRepo(job: job);
    final catalogRepo = _FakeCatalogRepo();
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalogRepo, queue: queue);

    final slots = tester.widgetList<PhotoSlot>(find.byType(PhotoSlot)).toList();
    expect(slots.map((s) => s.kind), requiredPhotoKinds('ARRIVED'));
    expect(slots.map((s) => s.serverHasPhoto), [false, true]);
    expect(find.text('Overview photo'), findsOneWidget);
    expect(find.text('Close-up of the fault'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('Submit asks to confirm; "Not yet" sends nothing, "Send estimate" calls diagnose', (tester) async {
    final job = _dto(photos: _bothServerPhotos());
    final jobRepo = _FakeJobRepo(job: job);
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: _FakeCatalogRepo(), queue: queue);
    await _pickIssue(tester);

    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    expect(find.text("Send this estimate to the customer? You won't be able to change parts after this."), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelSendEstimateBtn')));
    await tester.pumpAndSettle();
    expect(jobRepo.diagnoseCalls, 0);

    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendEstimateBtn')));
    await tester.pumpAndSettle();
    expect(jobRepo.diagnoseCalls, 1);
    expect(jobRepo.lastDiagnose, (id: 'b1', issueId: 'i1'));
    await _disposeTree(tester);
  });

  testWidgets('issues are fetched for the job category; no category (older backend) → unfiltered', (tester) async {
    final catalog = _FakeCatalogRepo();
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalog,
        queue: PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {}));
    expect(catalog.issuesCategoryArgs, ['cat-fan']);
    await _disposeTree(tester);

    final unfiltered = _FakeCatalogRepo();
    final legacyJob = _dto(categoryId: null);
    final legacyRepo = _FakeJobRepo(job: legacyJob);
    await _pump(tester, job: legacyJob, jobRepo: legacyRepo, catalogRepo: unfiltered,
        queue: PhotoUploadQueue(repo: legacyRepo, put: ({required url, required key, required bytes}) async {}));
    expect(unfiltered.issuesCategoryArgs, [null]);
    await _disposeTree(tester);
  });

  testWidgets('Submit is disabled while a part add is still in flight', (tester) async {
    final job = _dto(photos: _bothServerPhotos());
    final jobRepo = _FakeJobRepo(job: job)..addGate = Completer<void>();
    final catalog = _FakeCatalogRepo()
      ..catalogParts = const [PartCatalogDto(id: 'p1', sku: 'CAP', name: 'Capacitor', categoryId: 'cat-fan', ceilingPricePaise: 15000, status: 'ACTIVE')];
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalog,
        queue: PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {}));
    await _pickIssue(tester);
    expect(_submitBtn(tester).onPressed, isNotNull);

    await _tapKey(tester, const Key('addPartBtn_p1'));
    await tester.pump();
    expect(_submitBtn(tester).onPressed, isNull);
    expect(find.text('Updating the parts…'), findsOneWidget);

    jobRepo.addGate!.complete();
    await tester.pumpAndSettle();
    expect(_submitBtn(tester).onPressed, isNotNull);
    await _disposeTree(tester);
  });
}
