import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/diagnosis_form.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_screen.dart';
import 'package:fixcare_technician/features/jobs/presentation/location_service.dart';

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
  _FakeLocationService({this.result});
  final ({double lat, double lng})? result;

  @override
  Future<({double lat, double lng})?> current() async => result;
}

/// Fake repo whose `mine()` reflects a mutable internal state, so that
/// `refetch()` (which the screen calls after every action) observes the
/// effect of that action — mirrors a real backend round-trip.
class _FakeRepo extends TechnicianJobRepository {
  _FakeRepo({required String initialState, this.id = 'b1'})
      : _state = initialState,
        super(Dio());

  final String id;
  String _state;

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
  Future<Result<List<TechnicianJobDto>>> mine() async => Ok([_dto(id: id, state: _state)]);

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
    return confirmCashResult ?? Ok(CashResultDto(id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise: 0));
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
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        technicianJobRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider
            .overrideWithValue(location ?? _FakeLocationService(result: (lat: 22.3, lng: 73.2))),
        catalogRepositoryProvider.overrideWithValue(catalog ?? _FakeCatalogRepo()),
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
    await _pump(tester, repo, location: _FakeLocationService(result: (lat: 22.3, lng: 73.2)));

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

  testWidgets('location null shows an inline message and does not call arrive', (tester) async {
    final repo = _FakeRepo(initialState: 'EN_ROUTE');
    await _pump(tester, repo, location: _FakeLocationService(result: null));

    await tester.tap(find.byKey(const Key('arriveBtn')));
    await tester.pumpAndSettle();

    expect(repo.lastArrive, isNull);
    expect(
      find.text("Couldn't get your location. Make sure location is on and try again."),
      findsOneWidget,
    );

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

  testWidgets('DIAGNOSED shows waitingApprovalCard', (tester) async {
    final repo = _FakeRepo(initialState: 'DIAGNOSED');
    await _pump(tester, repo);
    expect(find.byKey(const Key('waitingApprovalCard')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('ARRIVED shows the diagnosis form', (tester) async {
    final repo = _FakeRepo(initialState: 'ARRIVED');
    await _pump(tester, repo);
    expect(find.byType(DiagnosisForm), findsOneWidget);
    expect(find.byKey(const Key('issuePicker')), findsOneWidget);
    await _disposeTree(tester);
  });

  testWidgets('REPAIR_IN_PROGRESS shows repairPlaceholder', (tester) async {
    final repo = _FakeRepo(initialState: 'REPAIR_IN_PROGRESS');
    await _pump(tester, repo);
    expect(find.byKey(const Key('repairPlaceholder')), findsOneWidget);
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
    final repo = _FakeRepo(initialState: 'ACCEPTED', id: 'other');
    await _pump(tester, repo);

    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);

    await _disposeTree(tester);
  });
}
