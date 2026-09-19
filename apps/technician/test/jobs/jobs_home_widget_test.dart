import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/jobs_home_screen.dart';

Map<String, dynamic> _job({String id = 'b1', String bookingNumber = 'FC-1'}) => {
  'id': id, 'bookingNumber': bookingNumber, 'state': 'DISPATCHED', 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': 'Padra', 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
};

TechnicianJobDto _dto({String id = 'b1'}) => TechnicianJobDto.fromJson(_job(id: id));

/// Fake repo recording calls; behavior per test is driven by the closures.
class _FakeJobRepo extends TechnicianJobRepository {
  _FakeJobRepo({
    List<TechnicianJobDto>? available,
    List<TechnicianJobDto>? mine,
    Result<TechnicianJobDto>? acceptResult,
  }) : _available = available ?? [_dto()],
       _mine = mine ?? [],
       _acceptResult = acceptResult ?? Ok(_dto(id: 'b1')),
       super(Dio());

  final List<TechnicianJobDto> _available;
  List<TechnicianJobDto> _mine;
  final Result<TechnicianJobDto> _acceptResult;
  int acceptCalls = 0;
  String? lastAcceptedId;

  @override
  Future<Result<List<TechnicianJobDto>>> available() async => Ok(_available);

  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => Ok(_mine);

  @override
  Future<Result<TechnicianJobDto>> accept(String id) async {
    acceptCalls++;
    lastAcceptedId = id;
    // A real async gap (not just a microtask) so the busy flag's rebuild is
    // observable between two taps in a test — mirrors a real network hop.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final result = _acceptResult;
    if (result is Ok<TechnicianJobDto>) {
      _mine = [..._mine, result.value];
    }
    return _acceptResult;
  }
}

class _EmptyJobRepo extends TechnicianJobRepository {
  _EmptyJobRepo() : super(Dio());
  @override
  Future<Result<List<TechnicianJobDto>>> available() async => const Ok(<TechnicianJobDto>[]);
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async => const Ok(<TechnicianJobDto>[]);
}

Future<void> _pump(WidgetTester tester, TechnicianJobRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: JobsHomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('available list renders a card with service, rupees, masked phone, address',
      (tester) async {
    await _pump(tester, _FakeJobRepo());

    expect(find.byKey(const Key('jobsHomeScreen')), findsOneWidget);
    expect(find.text('Ceiling fan repair'), findsOneWidget);
    expect(find.textContaining('₹99'), findsOneWidget);
    expect(find.textContaining('₹200'), findsOneWidget);
    expect(find.text('••••••8384'), findsOneWidget);
    expect(find.textContaining('A/27 Umiya Nagar'), findsOneWidget);
  });

  testWidgets('empty available list shows noJobsEmpty', (tester) async {
    await _pump(tester, _EmptyJobRepo());
    expect(find.byKey(const Key('noJobsEmpty')), findsOneWidget);
  });

  testWidgets('tap acceptJob_b1 -> Ok refreshes both lists', (tester) async {
    final repo = _FakeJobRepo(available: [_dto(id: 'b1')], mine: []);
    await _pump(tester, repo);

    // Before accept: "My jobs" section shows its empty state, no state text.
    expect(find.text('No accepted jobs yet'), findsOneWidget);
    expect(find.byKey(const Key('acceptJob_b1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('acceptJob_b1')));
    await tester.pumpAndSettle();

    expect(repo.acceptCalls, 1);
    expect(repo.lastAcceptedId, 'b1');
    // Both lists were refreshed via the notifiers: my-jobs' repo call now
    // returns the accepted job, so its empty state is gone and a card with
    // its state text renders.
    expect(find.text('No accepted jobs yet'), findsNothing);
    expect(find.textContaining('State: DISPATCHED'), findsOneWidget);
  });

  testWidgets('tap acceptJob_b1 -> 409 Failure shows SnackBar with message', (tester) async {
    final repo = _FakeJobRepo(
      available: [_dto(id: 'b1')],
      acceptResult: const Failure(FailureKind.unknown, 'This job is no longer available'),
    );
    await _pump(tester, repo);

    await tester.tap(find.byKey(const Key('acceptJob_b1')));
    await tester.pumpAndSettle();

    expect(repo.acceptCalls, 1);
    expect(find.text('This job is no longer available'), findsOneWidget);
  });

  testWidgets('per-card busy flag blocks double-tap', (tester) async {
    final repo = _FakeJobRepo(available: [_dto(id: 'b1')]);
    await _pump(tester, repo);

    // Tap once but don't settle — the request is in-flight synchronously
    // resolved by the fake, so simulate rapid double-tap via two taps before
    // a frame is fully processed.
    final finder = find.byKey(const Key('acceptJob_b1'));
    await tester.tap(finder);
    await tester.pump(); // flip the busy flag (accept's delayed future hasn't resolved yet)
    await tester.tap(finder); // no-op: button is disabled while busy
    await tester.pumpAndSettle();

    expect(repo.acceptCalls, 1);
  });
}
