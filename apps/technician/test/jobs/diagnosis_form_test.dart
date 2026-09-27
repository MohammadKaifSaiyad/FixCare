import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/diagnosis_form.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';

Map<String, dynamic> _jobJson({
  String id = 'b1',
  String state = 'ARRIVED',
  List<Map<String, dynamic>> photos = const [],
}) => {
  'id': id, 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': null, 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': photos,
};

TechnicianJobDto _dto({String id = 'b1', List<Map<String, dynamic>> photos = const []}) =>
    TechnicianJobDto.fromJson(_jobJson(id: id, photos: photos));

/// Fake catalog repo: issues() is scripted (Ok or Failure), with a call count
/// so the retry test can assert a re-fetch happened.
class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());

  Result<List<DiagnosedIssueDto>> issuesResult =
      const Ok([DiagnosedIssueDto(id: 'i1', name: 'Fan capacitor failure', categoryId: 'c1', status: 'ACTIVE')]);
  int issuesCalls = 0;

  @override
  Future<Result<List<DiagnosedIssueDto>>> issues({String? categoryId}) async {
    issuesCalls++;
    return issuesResult;
  }

  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async => const Ok([]);
}

/// Fake job repo: handles mine() (recorded, for asserting a refetch happened),
/// diagnose() (recorded + scripted), and the photo sign/confirm calls the
/// queue drives (always succeed immediately — no retry/backoff involved in
/// these tests).
class _FakeJobRepo extends TechnicianJobRepository {
  _FakeJobRepo({required this.job}) : super(Dio());

  TechnicianJobDto job;
  int mineCalls = 0;
  int diagnoseCalls = 0;
  ({String id, String issueId})? lastDiagnose;
  Result<void> diagnoseResult = const Ok(null);

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async {
    mineCalls++;
    return Ok([job]);
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
      child: MaterialApp(home: Scaffold(body: DiagnosisForm(job: job))),
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

    await tester.tap(find.byKey(const Key('issuePicker')));
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

    await tester.tap(find.byKey(const Key('issuePicker')));
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

    await tester.tap(find.byKey(const Key('issuePicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    expect(_submitBtn(tester).onPressed, isNotNull);

    final mineCallsBefore = jobRepo.mineCalls;
    await tester.tap(find.byKey(const Key('submitDiagnosisBtn')));
    await tester.pumpAndSettle();

    expect(jobRepo.diagnoseCalls, 1);
    expect(jobRepo.lastDiagnose, (id: 'b1', issueId: 'i1'));
    expect(jobRepo.mineCalls, greaterThan(mineCallsBefore));

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

    await tester.tap(find.byKey(const Key('issuePicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fan capacitor failure').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitDiagnosisBtn')));
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
    await tester.tap(find.byKey(const Key('issuesRetry')));
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

    await tester.tap(find.byKey(const Key('issuePicker')));
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
}
