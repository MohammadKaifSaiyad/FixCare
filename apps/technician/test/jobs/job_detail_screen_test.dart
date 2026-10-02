import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/format.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/theme.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/diagnosis_form.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_screen.dart';
import 'package:fixcare_technician/features/jobs/presentation/location_service.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';
import 'package:fixcare_technician/features/jobs/presentation/repair_photos_card.dart';
import 'package:fixcare_technician/features/jobs/presentation/settings_opener.dart';

Map<String, dynamic> _job({String id = 'b1', String state = 'ACCEPTED'}) => {
  'id': id, 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': null, 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
};

TechnicianJobDto _dto({String id = 'b1', String state = 'ACCEPTED'}) =>
    TechnicianJobDto.fromJson(_job(id: id, state: state));

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.result = const LocationFix(22.3, 73.2)});
  final LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

class _FakeSettingsOpener implements SettingsOpener {
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

class _SwitchableLocationService implements LocationService {
  _SwitchableLocationService(this.result);
  LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

/// Fake repo whose `job(id)` reflects a mutable internal state, so that
/// `refetch()` (which the screen calls after every action) observes the
/// effect of that action — mirrors a real backend round-trip. The job-detail
/// controller polls the single-job GET only, so `mine()` throws.
class _FakeRepo extends TechnicianJobRepository {
  _FakeRepo({required String initialState})
      : _state = initialState,
        super(Dio());

  final String id = 'b1';
  String _state;

  /// When non-null, `job()` returns this instead of the job — e.g. a 403/404
  /// (reassigned/cancelled out from under the technician) or a network failure.
  Result<TechnicianJobDetailDto>? jobResultOverride;

  /// The server-side parts cart the single-job GET returns alongside the job.
  List<JobPartLineDto> parts = const [];

  /// The backend's computed customer quote the single-job GET returns (null = an older backend).
  JobQuoteDto? quote = const JobQuoteDto(laborPaise: 20000, partsPaise: 15000, visitFeeCreditPaise: 9900, totalPayablePaise: 25100);

  int jobCalls = 0;
  int enRouteCalls = 0;
  int startRepairCalls = 0;
  int partsNeededCalls = 0;
  int partsAcquiredCalls = 0;
  ({double lat, double lng})? lastArrive;
  String? lastCompletionCode;
  String? lastCashCode;

  Result<void>? enRouteResult;
  Result<ArriveResultDto>? arriveResult;
  Result<void>? startRepairResult;
  Result<void>? partsNeededResult;
  Result<void>? partsAcquiredResult;
  Result<void>? confirmCompletionResult;
  Result<CashResultDto>? confirmCashResult;

  /// When true, `enRoute` throws instead of returning a Result — simulates a
  /// non-Dio failure (e.g. a malformed-response TypeError) that the repo's
  /// `_guard` (DioException-only) would not catch.
  bool enRouteThrows = false;

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async =>
      throw StateError('the job-detail controller must not call mine()');

  @override
  Future<Result<TechnicianJobDetailDto>> job(String bookingId) async {
    jobCalls++;
    return jobResultOverride ?? Ok(TechnicianJobDetailDto(job: _dto(id: id, state: _state), parts: parts, customerQuote: quote));
  }

  @override
  Future<Result<void>> enRoute(String bookingId) async {
    enRouteCalls++;
    if (enRouteThrows) throw StateError('boom');
    final r = enRouteResult ?? const Ok(null);
    if (r is Ok<void>) _state = 'EN_ROUTE';
    return r;
  }

  @override
  Future<Result<ArriveResultDto>> arrive(String bookingId, {required double lat, required double lng}) async {
    lastArrive = (lat: lat, lng: lng);
    return arriveResult ?? Ok(ArriveResultDto(arrivalCode: '482913'));
  }

  @override
  Future<Result<void>> startRepair(String bookingId) async {
    startRepairCalls++;
    final r = startRepairResult ?? const Ok(null);
    if (r is Ok<void>) _state = 'REPAIR_IN_PROGRESS';
    return r;
  }

  @override
  Future<Result<void>> partsNeeded(String bookingId) async {
    partsNeededCalls++;
    final r = partsNeededResult ?? const Ok(null);
    if (r is Ok<void>) _state = 'PARTS_REQUESTED';
    return r;
  }

  @override
  Future<Result<void>> partsAcquired(String bookingId) async {
    partsAcquiredCalls++;
    final r = partsAcquiredResult ?? const Ok(null);
    if (r is Ok<void>) _state = 'PARTS_ACQUIRED';
    return r;
  }

  @override
  Future<Result<void>> confirmCompletion(String bookingId, String code) async {
    lastCompletionCode = code;
    final r = confirmCompletionResult ?? const Ok(null);
    if (r is Ok<void>) _state = 'CUSTOMER_CONFIRMED';
    return r;
  }

  @override
  Future<Result<CashResultDto>> confirmCash(String bookingId, String code) async {
    lastCashCode = code;
    final r = confirmCashResult ?? Ok(CashResultDto(id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise: 0));
    if (r is Ok<CashResultDto>) _state = 'PAYMENT_RECEIVED';
    return r;
  }
}

/// A catalog repo the diagnosis form / parts cart can load without hitting
/// the real dioProvider — defaults to empty lists (these job_detail_screen
/// tests only assert the right card is shown, not catalog content).
class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());

  Result<List<DiagnosedIssueDto>> issuesResult = const Ok(<DiagnosedIssueDto>[]);
  Result<List<PartCatalogDto>> partsResult = const Ok(<PartCatalogDto>[]);

  @override
  Future<Result<List<DiagnosedIssueDto>>> issues({String? categoryId}) async => issuesResult;

  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async => partsResult;
}

Future<void> _pump(
  WidgetTester tester,
  TechnicianJobRepository repo, {
  LocationService? location,
  CatalogRepository? catalog,
  SettingsOpener? opener,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        technicianJobRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(location ?? _FakeLocationService()),
        catalogRepositoryProvider.overrideWithValue(catalog ?? _FakeCatalogRepo()),
        settingsOpenerProvider.overrideWithValue(opener ?? _FakeSettingsOpener()),
      ],
      child: const MaterialApp(home: JobDetailScreen(bookingId: 'b1')),
    ),
  );
  await tester.pumpAndSettle();
}

/// Dispose the widget tree so the controller's `Timer.periodic` is cancelled
/// via `ref.onDispose` — otherwise the test fails with "A Timer is still
/// pending" (the controller polls every 5s for any non-terminal job).
Future<void> _disposeTree(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('ACCEPTED -> tap enRouteBtn calls enRoute and advances to arrive card', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED');
    await _pump(tester, repo);

    expect(find.byKey(const Key('enRouteBtn')), findsOneWidget);
    await tester.tap(find.byKey(const Key('enRouteBtn')));
    await tester.pumpAndSettle();

    expect(repo.enRouteCalls, 1);
    expect(find.byKey(const Key('arriveBtn')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('EN_ROUTE -> tap arriveBtn calls arrive with the location and shows arrivalCode', (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo, location: _FakeLocationService(result: const LocationFix(22.3, 73.2)));

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();

    expect(repo.lastArrive, (lat: 22.3, lng: 73.2));
    expect(find.byKey(const Key('arrivalCode')), findsOneWidget);
    expect(find.text('482913'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('arrive Failure shows the geofence message inline', (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE')
      ..arriveResult = const Failure(FailureKind.unknown, 'You are too far from the customer location');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();

    expect(find.text('You are too far from the customer location'), findsOneWidget);
    expect(find.byKey(const Key('arrivalCode')), findsNothing);

    await _disposeTree(tester);
  });

  const problemCopy = {
    LocationProblemKind.servicesOff: 'Location is turned off. Turn it on and try again.',
    LocationProblemKind.denied:
        "FixCare needs your location to confirm you've arrived. Allow it and try again.",
    LocationProblemKind.deniedForever: 'Location permission is blocked. Allow it in Settings to confirm arrival.',
    LocationProblemKind.reducedAccuracy:
        'Turn on Precise location for FixCare. The arrival check needs your exact position.',
    LocationProblemKind.unavailable:
        "Couldn't get your location. Move near a window or step outside, then try again.",
  };
  const problemButton = {
    LocationProblemKind.servicesOff: 'openLocationSettings',
    LocationProblemKind.deniedForever: 'openAppSettings',
    LocationProblemKind.reducedAccuracy: 'openAppSettings',
  };

  for (final kind in LocationProblemKind.values) {
    testWidgets('location problem $kind -> its inline message, the right settings link, arrive NOT called',
        (tester) async {
      final repo = _FakeRepo(initialState: 'EN_ROUTE');
      await _pump(tester, repo, location: _FakeLocationService(result: LocationProblem(kind)));

      await tester.tap(find.byKey(const Key('arriveBtn')));
      await tester.pumpAndSettle();

      expect(repo.lastArrive, isNull);
      expect(find.text(problemCopy[kind]!), findsOneWidget);
      final expectedButton = problemButton[kind];
      for (final key in const ['openLocationSettings', 'openAppSettings']) {
        expect(find.byKey(Key(key)), key == expectedButton ? findsOneWidget : findsNothing, reason: '$kind/$key');
      }

      await _disposeTree(tester);
    });
  }

  testWidgets('servicesOff: openLocationSettings opens the device location settings', (tester) async {
    final opener = _FakeSettingsOpener();
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo,
        location: _FakeLocationService(result: const LocationProblem(LocationProblemKind.servicesOff)),
        opener: opener);

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openLocationSettings')));
    await tester.pump();

    expect(opener.locationSettingsCalls, 1);
    expect(opener.appSettingsCalls, 0);

    await _disposeTree(tester);
  });

  testWidgets('deniedForever: openAppSettings opens the app settings page', (tester) async {
    final opener = _FakeSettingsOpener();
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo,
        location: _FakeLocationService(result: const LocationProblem(LocationProblemKind.deniedForever)),
        opener: opener);

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openAppSettings')));
    await tester.pump();

    expect(opener.appSettingsCalls, 1);
    expect(opener.locationSettingsCalls, 0);

    await _disposeTree(tester);
  });

  testWidgets('a retry after a location problem clears the message and arrives', (tester) async {
    final location = _SwitchableLocationService(const LocationProblem(LocationProblemKind.servicesOff));
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo, location: location);

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openLocationSettings')), findsOneWidget);

    location.result = const LocationFix(22.3, 73.2);
    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();

    expect(repo.lastArrive, (lat: 22.3, lng: 73.2));
    expect(find.text(problemCopy[LocationProblemKind.servicesOff]!), findsNothing);
    expect(find.byKey(const Key('openLocationSettings')), findsNothing);
    expect(find.byKey(const Key('arrivalCode')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('CUSTOMER_APPROVED shows partsNeededBtn and startRepairBtn; each calls its action', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_APPROVED');
    await _pump(tester, repo);

    expect(find.byKey(const Key('partsNeededBtn')), findsOneWidget);
    expect(find.byKey(const Key('startRepairBtn')), findsOneWidget);

    await tester.tap(find.byKey(const Key('partsNeededBtn')));
    await tester.pumpAndSettle();
    expect(repo.partsNeededCalls, 1);

    await _disposeTree(tester);
  });

  testWidgets('CUSTOMER_APPROVED -> tap startRepairBtn calls startRepair', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_APPROVED');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('startRepairBtn')));
    await tester.pumpAndSettle();
    expect(repo.startRepairCalls, 1);

    await _disposeTree(tester);
  });

  testWidgets('PARTS_ACQUIRED shows startRepairBtn but not partsNeededBtn', (tester) async {
    final repo = _FakeRepo(initialState: 'PARTS_ACQUIRED');
    await _pump(tester, repo);

    expect(find.byKey(const Key('startRepairBtn')), findsOneWidget);
    expect(find.byKey(const Key('partsNeededBtn')), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('PARTS_REQUESTED -> tap partsAcquiredBtn calls partsAcquired', (tester) async {
    final repo = _FakeRepo(initialState: 'PARTS_REQUESTED');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('partsAcquiredBtn')));
    await tester.pumpAndSettle();
    expect(repo.partsAcquiredCalls, 1);

    await _disposeTree(tester);
  });

  testWidgets('one-tap throw resets busy and shows a generic SnackBar', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED')..enRouteThrows = true;
    await _pump(tester, repo);

    final buttonFinder = find.byKey(const Key('enRouteBtn'));
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(repo.enRouteCalls, 1);
    expect(find.text('Something went wrong.'), findsOneWidget);
    // Busy was reset (not stuck disabled) — the button is enabled again.
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);

    await _disposeTree(tester);
  });

  testWidgets('one-tap Failure shows a SnackBar with the message', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED')
      ..enRouteResult = const Failure(FailureKind.unknown, 'This job is no longer available');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('enRouteBtn')));
    await tester.pumpAndSettle();

    expect(find.text('This job is no longer available'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('REPAIR_COMPLETE: confirm disabled under 6 chars, enabled and submits at 6', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_COMPLETE');
    await _pump(tester, repo);

    final buttonFinder = find.byKey(const Key('confirmCompletionBtn'));
    FilledButton button() => tester.widget<FilledButton>(buttonFinder);
    expect(button().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('completionCodeField')), '12345');
    await tester.pump();
    expect(button().onPressed, isNull);

    await tester.enterText(find.byKey(const Key('completionCodeField')), '123456');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();

    expect(repo.lastCompletionCode, '123456');

    await _disposeTree(tester);
  });

  testWidgets('code field strips non-digit characters', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_COMPLETE');
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('completionCodeField')), 'ab12.3');
    await tester.pump();

    expect(find.text('123'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('confirmCompletionBtn'))).onPressed, isNull);

    await _disposeTree(tester);
  });

  testWidgets('confirmCompletion Failure shows the message inline', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_COMPLETE')
      ..confirmCompletionResult = const Failure(FailureKind.unauthorized, 'Invalid code');
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('completionCodeField')), '123456');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCompletionBtn')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid code'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('CUSTOMER_CONFIRMED -> enter code and confirm calls confirmCash', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED');
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('cashCodeField')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCashBtn')));
    await tester.pumpAndSettle();

    expect(repo.lastCashCode, '654321');

    await _disposeTree(tester);
  });

  testWidgets('DECLINED_BY_CUSTOMER shows the cash code field', (tester) async {
    final repo = _FakeRepo(initialState: 'DECLINED_BY_CUSTOMER');
    await _pump(tester, repo);

    expect(find.byKey(const Key('cashCodeField')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('confirmCash Failure shows the cash-limit message inline', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED')
      ..confirmCashResult = const Failure(FailureKind.unknown, 'Daily cash collection limit reached');
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('cashCodeField')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCashBtn')));
    await tester.pumpAndSettle();

    expect(find.text('Daily cash collection limit reached'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('DIAGNOSED shows the read-only estimate-sent card with the frozen total', (tester) async {
    final repo = _FakeRepo(initialState: 'DIAGNOSED')
      ..parts = const [
        JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000),
      ];
    await _pump(tester, repo);
    expect(find.byKey(const Key('waitingApprovalCard')), findsOneWidget);
    expect(find.byKey(const Key('estimateTotal')), findsOneWidget);
    expect(find.text('Total: ₹251'), findsOneWidget, reason: "the backend's quote, verbatim");
    await _disposeTree(tester);
  });

  testWidgets('ARRIVED shows the diagnosis form', (tester) async {
    final repo = _FakeRepo(initialState: 'ARRIVED');
    await _pump(tester, repo);
    expect(find.byType(DiagnosisForm), findsOneWidget);
    expect(find.byKey(const Key('issuePicker')), findsOneWidget);
    expect(find.byKey(const Key('partsFilter')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('REPAIR_IN_PROGRESS shows the repair-photos card (3 slots, complete disabled)', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_IN_PROGRESS');
    await _pump(tester, repo);
    expect(find.byType(RepairPhotosCard), findsOneWidget);
    expect(find.byType(PhotoSlot), findsNWidgets(3));
    expect(find.byKey(const Key('repairPlaceholder')), findsNothing);
    // No photos on the job and none captured -> the gate is closed.
    expect(tester.widget<FilledButton>(find.byKey(const Key('completeRepairBtn'))).onPressed, isNull);
    await _disposeTree(tester);
  });

  testWidgets('PAYMENT_RECEIVED shows terminalSummary', (tester) async {
    final repo = _FakeRepo(initialState: 'PAYMENT_RECEIVED');
    await _pump(tester, repo);
    expect(find.byKey(const Key('terminalSummary')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('job-info card shows masked phone and rupees fees', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED');
    await _pump(tester, repo);

    expect(find.text('••••••8384'), findsOneWidget);
    expect(find.textContaining('₹99'), findsOneWidget);
    expect(find.textContaining('₹200'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('error state shows jobDetailRetry, which reloads on tap', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED')
      ..jobResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.');
    await _pump(tester, repo);

    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);
    expect(find.text("Couldn't load this job."), findsOneWidget);
    expect(find.text('This job is no longer assigned to you.'), findsNothing);

    repo.jobResultOverride = null;
    await tester.tap(find.byKey(const Key('jobDetailRetry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jobDetailRetry')), findsNothing);
    expect(find.byKey(const Key('enRouteBtn')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('a 403 from the single-job GET shows "This job is no longer assigned to you."', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED')
      ..jobResultOverride = const Failure(FailureKind.forbidden, 'This job is not assigned to you', code: 'JOB_NOT_ASSIGNED');
    await _pump(tester, repo);
    expect(find.text('This job is no longer assigned to you.'), findsOneWidget);
    expect(find.text("Couldn't load this job."), findsNothing);
    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('a 404 WITHOUT a job code (route-not-found on an older backend) on first load shows the generic error + Retry, not the vanished copy',
      (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED')
      ..jobResultOverride = const Failure(FailureKind.notFound, 'Route GET:/technician/jobs/b1 not found');
    await _pump(tester, repo);
    expect(find.text("Couldn't load this job."), findsOneWidget);
    expect(find.text('This job is no longer assigned to you.'), findsNothing);
    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('a 403 "Verified technician required" (suspended) shows that message verbatim, not the vanished copy, and stops polling',
      (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo);
    expect(find.byKey(const Key('arriveBtn')), findsOneWidget);

    repo.jobResultOverride = const Failure(FailureKind.forbidden, 'Verified technician required');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(find.text('Verified technician required'), findsOneWidget);
    expect(find.text('This job is no longer assigned to you.'), findsNothing);
    expect(find.text("Couldn't load this job."), findsNothing);
    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);
    final calls = repo.jobCalls;
    await tester.pump(const Duration(seconds: 30));
    expect(repo.jobCalls, calls, reason: 'polling stopped');

    await _disposeTree(tester);
  });

  testWidgets('a job reassigned/cancelled mid-poll (404) shows its own message, not the generic one',
      (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo);
    expect(find.byKey(const Key('arriveBtn')), findsOneWidget);

    repo.jobResultOverride = const Failure(FailureKind.notFound, 'Job not found', code: 'JOB_NOT_FOUND');
    await tester.pump(const Duration(seconds: 5)); // the next poll sees the 404 — no 3-miss grace any more
    await tester.pump();

    expect(find.text('This job is no longer assigned to you.'), findsOneWidget);
    expect(find.text("Couldn't load this job."), findsNothing);
    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('a vanish that clears (transient 404 blip, job unchanged) returns to the job on resume', (tester) async {
    final binding = tester.binding;
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo);

    repo.jobResultOverride = const Failure(FailureKind.notFound, 'Job not found', code: 'JOB_NOT_FOUND');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('This job is no longer assigned to you.'), findsOneWidget);

    repo.jobResultOverride = null; // the blip is over; the job is exactly as before
    for (final st in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    for (final st in const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump();
    await tester.pump();

    expect(find.text('This job is no longer assigned to you.'), findsNothing);
    expect(find.byKey(const Key('arriveBtn')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('arrive Failure text uses FixCareColors.errorText (not Colors.red)', (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE')
      ..arriveResult = const Failure(FailureKind.unknown, 'You are too far from the customer location');
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('You are too far from the customer location'));
    expect(text.style?.color, FixCareColors.errorText);

    await _disposeTree(tester);
  });

  testWidgets('job-info card shows the scheduled slot in local time, not the raw ISO string', (tester) async {
    final repo = _FakeRepo(initialState: 'ACCEPTED');
    await _pump(tester, repo);

    expect(find.text('Scheduled: ${formatScheduledSlot('2026-09-20T09:00:00.000Z')}'), findsOneWidget);
    expect(find.textContaining('2026-09-20T'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('completion code card tells the technician where the code comes from', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_COMPLETE');
    await _pump(tester, repo);

    expect(
      find.text('Ask the customer for the 6-digit code in their app after they confirm the work is done.'),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('CUSTOMER_CONFIRMED shows the UPI-first awaiting-payment text', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED');
    await _pump(tester, repo);

    expect(find.byKey(const Key('awaitingPaymentText')), findsOneWidget);
    expect(
      find.text(
        'Waiting for the customer to pay in the FixCare app. Most customers pay by UPI — this updates on its own when they do.',
      ),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('DECLINED_BY_CUSTOMER shows the declined + awaiting-payment text', (tester) async {
    final repo = _FakeRepo(initialState: 'DECLINED_BY_CUSTOMER');
    await _pump(tester, repo);

    expect(find.byKey(const Key('awaitingPaymentText')), findsOneWidget);
    expect(
      find.text(
        'The customer declined the repair. Waiting for them to pay the visit fee in the FixCare app. This updates on its own when they do.',
      ),
      findsOneWidget,
    );

    await _disposeTree(tester);
  });

  testWidgets('the cash section is a secondary, opt-in path and still records cash with the 6-digit code',
      (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED');
    await _pump(tester, repo);

    expect(find.text('Customer paying cash instead?'), findsOneWidget);
    expect(
      find.text(
        'Only if the customer chose cash in their app: collect it, then enter the 6-digit receipt code shown in their app.',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('cashCodeField')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCashBtn')));
    await tester.pumpAndSettle();

    expect(repo.lastCashCode, '654321');

    await _disposeTree(tester);
  });

  testWidgets('confirmCash Ok shows the updated cash balance due to FixCare (Golden Rule 3)', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED')
      ..confirmCashResult = Ok(CashResultDto(id: 'b1', state: 'PAYMENT_RECEIVED', cashDebtPaise: 45050));
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('cashCodeField')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCashBtn')));
    await tester.pumpAndSettle();

    expect(find.text('Cash recorded. Your cash balance due to FixCare: ₹450.50'), findsOneWidget);
    expect(find.byKey(const Key('terminalSummary')), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('confirmCash Failure shows no cash-recorded notice', (tester) async {
    final repo = _FakeRepo(initialState: 'CUSTOMER_CONFIRMED')
      ..confirmCashResult = const Failure(FailureKind.unauthorized, 'Invalid code');
    await _pump(tester, repo);

    await tester.enterText(find.byKey(const Key('cashCodeField')), '654321');
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirmCashBtn')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cash recorded'), findsNothing);

    await _disposeTree(tester);
  });

  testWidgets('app backgrounded pauses the poll; foregrounded refetches once and re-arms', (tester) async {
    final binding = tester.binding;
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo);
    final base = repo.jobCalls;

    for (final s in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump(const Duration(seconds: 30));
    expect(repo.jobCalls, base, reason: 'no polling while backgrounded');

    for (final s in const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pump();
    expect(repo.jobCalls, base + 1, reason: 'an immediate refetch on resume');

    await tester.pump(const Duration(seconds: 5));
    expect(repo.jobCalls, base + 2, reason: 'polling re-armed');

    await _disposeTree(tester);
  });
}
