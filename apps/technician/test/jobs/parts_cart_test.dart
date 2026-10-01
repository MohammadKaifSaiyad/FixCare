import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_controller.dart';
import 'package:fixcare_technician/features/jobs/presentation/parts_cart.dart';

TechnicianJobDto _job({String state = 'ARRIVED', int labor = 20000, int visit = 9900, String? categoryId = 'cat-fan'}) =>
    TechnicianJobDto.fromJson({
      'id': 'b1', 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-10-01T09:00:00.000Z',
      'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN', 'categoryId': categoryId},
      'zone': {'name': 'Padra'}, 'visitFeePaise': visit, 'laborPaise': labor,
      'address': {'line1': 'A/27 Umiya Nagar', 'pincode': '391440'},
      'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
    });

const _capacitor = PartCatalogDto(id: 'p1', sku: 'CAP', name: 'Capacitor', categoryId: 'cat-fan', ceilingPricePaise: 15000, status: 'ACTIVE');

/// Server-side cart: addPart/removePart mutate it; job() returns it — like the real backend.
class _FakeJobRepo extends TechnicianJobRepository {
  _FakeJobRepo({this.categoryId = 'cat-fan'}) : super(Dio());
  final String? categoryId;
  final List<JobPartLineDto> serverParts = [];
  int jobCalls = 0;
  int addCalls = 0;
  ({String partsCatalogId, int qty})? lastAdd;
  String? lastRemoved;
  Result<String>? addResultOverride;
  bool applyAddDespiteFailure = false;
  Completer<void>? addGate;

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    return Ok(TechnicianJobDetailDto(job: _job(categoryId: categoryId), parts: List.of(serverParts)));
  }

  @override
  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) async {
    addCalls++;
    lastAdd = (partsCatalogId: partsCatalogId, qty: qty);
    if (addGate != null) await addGate!.future;
    final override = addResultOverride;
    if (override == null || applyAddDespiteFailure) {
      serverParts.add(JobPartLineDto(id: 'l${serverParts.length + 1}', partsCatalogId: partsCatalogId, sku: 'CAP', name: 'Capacitor', qty: qty, ceilingPricePaise: 15000));
    }
    return override ?? Ok('l${serverParts.length}');
  }

  @override
  Future<Result<void>> removePart(String id, String partId) async {
    lastRemoved = partId;
    serverParts.removeWhere((p) => p.id == partId);
    return const Ok(null);
  }
}

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog() : super(Dio());
  final List<String?> partsCategoryArgs = [];
  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async {
    partsCategoryArgs.add(categoryId);
    return const Ok([_capacitor]);
  }
}

/// Renders PartsSection the way the diagnosis form does: from the live jobDetailProvider.
Future<void> _pump(WidgetTester tester, _FakeJobRepo repo, _FakeCatalog catalog, {ValueChanged<bool>? onBusy}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      technicianJobRepositoryProvider.overrideWithValue(repo),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          final async = ref.watch(jobDetailProvider('b1'));
          return switch (async) {
            AsyncData(value: final d) => SingleChildScrollView(child: PartsSection(detail: d, onBusyChanged: onBusy ?? (_) {})),
            _ => const SizedBox(),
          };
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('estimatePaise (what the customer will see — mirrors the backend DIAGNOSED quote)', () {
    test('labor 20000 + 2 × 15000 − visit fee 9900 = 40100', () {
      expect(estimatePaise(_job(), const [JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 2, ceilingPricePaise: 15000)]), 40100);
    });
    test('floors at 0 when the visit fee exceeds labor + parts', () {
      expect(estimatePaise(_job(labor: 5000, visit: 9900), const []), 0);
    });
  });

  group('PartsSection', () {
    testWidgets('the cart shown is the server cart; the parts list is fetched for the job category', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      final catalog = _FakeCatalog();
      await _pump(tester, repo, catalog);
      expect(find.byKey(const Key('cartLine_l9')), findsOneWidget);
      expect(catalog.partsCategoryArgs, ['cat-fan']);
      expect(find.text('Customer will see: ₹251'), findsOneWidget); // 20000 + 15000 − 9900 = 25100 paise
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no categoryId (older backend) → the parts list is unfiltered', (tester) async {
      final catalog = _FakeCatalog();
      await _pump(tester, _FakeJobRepo(categoryId: null), catalog);
      expect(catalog.partsCategoryArgs, [null]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('add with qty 2 → addPart(qty: 2) then a refetch renders the server line + new estimate', (tester) async {
      final repo = _FakeJobRepo();
      await _pump(tester, repo, _FakeCatalog());
      final callsBefore = repo.jobCalls;
      await tester.tap(find.byKey(const Key('qtyPlus_p1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(repo.lastAdd, (partsCatalogId: 'p1', qty: 2));
      expect(repo.jobCalls, greaterThan(callsBefore));
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget);
      expect(find.text('Customer will see: ₹401'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('remove → removePart(lineId) then the line disappears', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      await _pump(tester, repo, _FakeCatalog());
      await tester.tap(find.byKey(const Key('removePartBtn_l9')));
      await tester.pumpAndSettle();
      expect(repo.lastRemoved, 'l9');
      expect(find.byKey(const Key('cartLine_l9')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a lost add response the backend applied still converges to the server cart (no ghost, no dupe)', (tester) async {
      final repo = _FakeJobRepo()
        ..addResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.')
        ..applyAddDespiteFailure = true;
      await _pump(tester, repo, _FakeCatalog());
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.text('Network error. Check your connection.'), findsOneWidget); // surfaced
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget); // server truth shown after refetch
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a locked-cart 409 / not-assigned 403 is shown verbatim and refetches', (tester) async {
      final repo = _FakeJobRepo()..addResultOverride = const Failure(FailureKind.unknown, 'The cart is locked — the diagnosis has been submitted');
      await _pump(tester, repo, _FakeCatalog());
      final callsBefore = repo.jobCalls;
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.text('The cart is locked — the diagnosis has been submitted'), findsOneWidget);
      expect(repo.jobCalls, greaterThan(callsBefore));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reports busy while an add is in flight (and a double tap is ignored)', (tester) async {
      final repo = _FakeJobRepo()..addGate = Completer<void>();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add);
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('addPartBtn_p1')), warnIfMissed: false);
      await tester.pump();
      expect(busy.last, isTrue);
      expect(repo.addCalls, 1);
      repo.addGate!.complete();
      await tester.pumpAndSettle();
      expect(busy.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('EstimateSentCard (DIAGNOSED, read-only)', () {
    testWidgets('shows the frozen lines and the total; no edit controls', (tester) async {
      final detail = TechnicianJobDetailDto(job: _job(state: 'DIAGNOSED'), parts: const [JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 2, ceilingPricePaise: 15000)]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EstimateSentCard(detail: detail))));
      expect(find.byKey(const Key('waitingApprovalCard')), findsOneWidget);
      expect(find.text('Estimate sent — waiting for the customer to approve or decline'), findsOneWidget);
      expect(find.byKey(const Key('estimateLine_l1')), findsOneWidget);
      expect(find.text('Total: ₹401'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('labor-only estimate and a total floored at ₹0', (tester) async {
      final detail = TechnicianJobDetailDto(job: _job(state: 'DIAGNOSED', labor: 5000, visit: 9900));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EstimateSentCard(detail: detail))));
      expect(find.byKey(const Key('estimateLaborOnly')), findsOneWidget);
      expect(find.text('Total: ₹0'), findsOneWidget);
    });
  });
}
