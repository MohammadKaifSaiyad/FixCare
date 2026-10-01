import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_action.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';
import 'package:fixcare_technician/features/jobs/presentation/repair_photos_card.dart';

Map<String, dynamic> _jobJson({
  String id = 'b1',
  List<Map<String, dynamic>> photos = const [],
}) => {
  'id': id, 'bookingNumber': 'FC-1', 'state': 'REPAIR_IN_PROGRESS', 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': null, 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': photos,
};

TechnicianJobDto _dto({List<Map<String, dynamic>> photos = const []}) =>
    TechnicianJobDto.fromJson(_jobJson(photos: photos));

Map<String, dynamic> _serverPhoto(String kind) =>
    {'kind': kind, 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'};

/// Fake job repo: mine() (recorded, to assert a refetch), completeRepair()
/// (recorded + scripted, or throwing), and the photo sign/confirm calls the
/// queue drives (always succeed immediately).
class _FakeJobRepo extends TechnicianJobRepository {
  // Private `_job`: a public `job` field would collide with TechnicianJobRepository.job(id).
  _FakeJobRepo({required this._job}) : super(Dio());

  final TechnicianJobDto _job;
  int mineCalls = 0;
  final List<String> completeRepairCalls = [];
  Result<void> completeRepairResult = const Ok(null);
  bool completeRepairThrows = false;

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async {
    mineCalls++;
    return Ok([_job]);
  }

  @override
  Future<Result<void>> completeRepair(String id) async {
    completeRepairCalls.add(id);
    if (completeRepairThrows) throw StateError('boom');
    return completeRepairResult;
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

PhotoUploadQueue _queue(_FakeJobRepo repo) =>
    PhotoUploadQueue(repo: repo, put: ({required url, required key, required bytes}) async {});

Future<void> _pump(
  WidgetTester tester, {
  required TechnicianJobDto job,
  required _FakeJobRepo jobRepo,
  required PhotoUploadQueue queue,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        technicianJobRepositoryProvider.overrideWithValue(jobRepo),
        photoUploadQueueProvider.overrideWithValue(queue),
      ],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: RepairPhotosCard(job: job)))),
    ),
  );
  await tester.pumpAndSettle();
}

/// Dispose the tree — a successful complete-repair refetches through
/// `jobDetailProvider`, which arms a 5s poll timer once built; this cancels it
/// so the test doesn't fail with "A Timer is still pending".
Future<void> _disposeTree(WidgetTester tester) => tester.pumpWidget(const SizedBox());

FilledButton _completeBtn(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('completeRepairBtn')));

const _helper = 'Take all 3 photos to complete the repair.';

void main() {
  test('every required photo kind (diagnosis + repair) has a slot label', () {
    for (final state in const ['ARRIVED', 'REPAIR_IN_PROGRESS']) {
      for (final kind in requiredPhotoKinds(state)) {
        expect(photoSlotLabels[kind], isNotNull, reason: 'missing label for $kind');
      }
    }
    expect(photoSlotLabels['REPAIR_OLD_PART'], 'Old part removed');
    expect(photoSlotLabels['REPAIR_NEW_PACKAGING'], 'New part packaging');
    expect(photoSlotLabels['REPAIR_INSTALLED'], 'New part installed');
  });

  testWidgets('renders one PhotoSlot per required repair kind, in order, with labels', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    await _pump(tester, job: job, jobRepo: jobRepo, queue: _queue(jobRepo));

    final slots = tester.widgetList<PhotoSlot>(find.byType(PhotoSlot)).toList();
    expect(slots.map((s) => s.kind), requiredPhotoKinds('REPAIR_IN_PROGRESS'));
    expect(slots.every((s) => s.bookingId == 'b1'), isTrue);
    expect(find.text('Old part removed'), findsOneWidget);
    expect(find.text('New part packaging'), findsOneWidget);
    expect(find.text('New part installed'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('serverHasPhoto is true only for kinds already on the server', (tester) async {
    final job = _dto(photos: [_serverPhoto('REPAIR_NEW_PACKAGING')]);
    final jobRepo = _FakeJobRepo(job: job);
    await _pump(tester, job: job, jobRepo: jobRepo, queue: _queue(jobRepo));

    final byKind = {for (final s in tester.widgetList<PhotoSlot>(find.byType(PhotoSlot))) s.kind: s.serverHasPhoto};
    expect(byKind, {'REPAIR_OLD_PART': false, 'REPAIR_NEW_PACKAGING': true, 'REPAIR_INSTALLED': false});

    await _disposeTree(tester);
  });

  testWidgets('disabled with nothing captured, helper text shown', (tester) async {
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    await _pump(tester, job: job, jobRepo: jobRepo, queue: _queue(jobRepo));

    expect(_completeBtn(tester).onPressed, isNull);
    expect(find.text(_helper), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('disabled with 2 of 3 ready (one queue-done, one on server)', (tester) async {
    final job = _dto(photos: [_serverPhoto('REPAIR_OLD_PART')]);
    final jobRepo = _FakeJobRepo(job: job);
    final queue = _queue(jobRepo);
    await queue.enqueue(bookingId: 'b1', kind: 'REPAIR_NEW_PACKAGING', photo: _photo());

    await _pump(tester, job: job, jobRepo: jobRepo, queue: queue);

    expect(_completeBtn(tester).onPressed, isNull);
    expect(find.text(_helper), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('ENABLED with all 3 (mix of queue-done + server) -> tap calls completeRepair(b1) and refetches',
      (tester) async {
    final job = _dto(photos: [_serverPhoto('REPAIR_OLD_PART')]);
    final jobRepo = _FakeJobRepo(job: job);
    final queue = _queue(jobRepo);
    await queue.enqueue(bookingId: 'b1', kind: 'REPAIR_NEW_PACKAGING', photo: _photo());
    await queue.enqueue(bookingId: 'b1', kind: 'REPAIR_INSTALLED', photo: _photo());

    await _pump(tester, job: job, jobRepo: jobRepo, queue: queue);

    expect(_completeBtn(tester).onPressed, isNotNull);
    expect(find.text(_helper), findsNothing);

    final mineBefore = jobRepo.mineCalls;
    await tester.tap(find.byKey(const Key('completeRepairBtn')));
    await tester.pumpAndSettle();

    expect(jobRepo.completeRepairCalls, ['b1']);
    expect(jobRepo.mineCalls, greaterThan(mineBefore));
    expect(find.byKey(const Key('completeRepairError')), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('enables live when the queue flips the last slot to done (notify only)', (tester) async {
    final job = _dto(photos: [_serverPhoto('REPAIR_OLD_PART'), _serverPhoto('REPAIR_NEW_PACKAGING')]);
    final jobRepo = _FakeJobRepo(job: job);
    final queue = _queue(jobRepo);
    await _pump(tester, job: job, jobRepo: jobRepo, queue: queue);

    expect(_completeBtn(tester).onPressed, isNull);

    await queue.enqueue(bookingId: 'b1', kind: 'REPAIR_INSTALLED', photo: _photo());
    await tester.pump();

    expect(_completeBtn(tester).onPressed, isNotNull);

    await _disposeTree(tester);
  });

  testWidgets('completeRepair Failure shows the backend message verbatim inline, no refetch', (tester) async {
    const msg = '3 repair photos required (old part removed, new packaging, installed)';
    final job = _dto(photos: [
      _serverPhoto('REPAIR_OLD_PART'),
      _serverPhoto('REPAIR_NEW_PACKAGING'),
      _serverPhoto('REPAIR_INSTALLED'),
    ]);
    final jobRepo = _FakeJobRepo(job: job)..completeRepairResult = const Failure(FailureKind.validation, msg);
    await _pump(tester, job: job, jobRepo: jobRepo, queue: _queue(jobRepo));

    final mineBefore = jobRepo.mineCalls;
    await tester.tap(find.byKey(const Key('completeRepairBtn')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('completeRepairError')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('completeRepairError'))).data, msg);
    expect(jobRepo.mineCalls, mineBefore);
    // busy reset: the technician can try again.
    expect(_completeBtn(tester).onPressed, isNotNull);

    await _disposeTree(tester);
  });

  testWidgets('an unexpected throw shows "Something went wrong." and re-enables the button', (tester) async {
    final job = _dto(photos: [
      _serverPhoto('REPAIR_OLD_PART'),
      _serverPhoto('REPAIR_NEW_PACKAGING'),
      _serverPhoto('REPAIR_INSTALLED'),
    ]);
    final jobRepo = _FakeJobRepo(job: job)..completeRepairThrows = true;
    await _pump(tester, job: job, jobRepo: jobRepo, queue: _queue(jobRepo));

    await tester.tap(find.byKey(const Key('completeRepairBtn')));
    await tester.pumpAndSettle();

    expect(jobRepo.completeRepairCalls, ['b1']);
    expect(tester.widget<Text>(find.byKey(const Key('completeRepairError'))).data, 'Something went wrong.');
    expect(_completeBtn(tester).onPressed, isNotNull);

    await _disposeTree(tester);
  });
}
