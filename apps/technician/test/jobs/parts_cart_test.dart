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
  /// Sticky: while set, job() returns this instead of the server cart (e.g. the refetch after an add fails).
  Result<TechnicianJobDetailDto>? jobResultOverride;

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    return jobResultOverride ?? Ok(TechnicianJobDetailDto(job: _job(categoryId: categoryId), parts: List.of(serverParts)));
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
  _FakeCatalog({this.catalogParts = const [_capacitor]}) : super(Dio());
  final List<PartCatalogDto> catalogParts;
  final List<String?> partsCategoryArgs = [];
  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async {
    partsCategoryArgs.add(categoryId);
    return Ok(catalogParts);
  }
}

List<PartCatalogDto> _manyParts(int n, {String name = 'Part'}) => [
      for (var i = 1; i <= n; i++)
        PartCatalogDto(id: 'p$i', sku: 'SKU$i', name: '$name $i', categoryId: 'cat-fan', ceilingPricePaise: 1000 * i, status: 'ACTIVE'),
    ];

/// A job-detail notifier whose refetch() throws — the parts section must still reset its busy state.
class _RefetchThrows extends JobDetail {
  @override
  Future<TechnicianJobDetailDto> build(String bookingId) async => TechnicianJobDetailDto(job: _job());
  @override
  Future<bool> refetch() async => throw StateError('boom');
}

FilledButton _addBtn(WidgetTester tester, String partId) => tester.widget<FilledButton>(find.byKey(Key('addPartBtn_$partId')));

/// Renders PartsSection the way the diagnosis form does: from the live jobDetailProvider.
Future<void> _pump(WidgetTester tester, _FakeJobRepo repo, _FakeCatalog catalog,
    {ValueChanged<bool>? onBusy, bool enabled = true, JobDetail Function()? jobDetail}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      technicianJobRepositoryProvider.overrideWithValue(repo),
      catalogRepositoryProvider.overrideWithValue(catalog),
      if (jobDetail != null) jobDetailProvider.overrideWith2((_) => jobDetail()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          final async = ref.watch(jobDetailProvider('b1'));
          return switch (async) {
            AsyncData(value: final d) =>
              SingleChildScrollView(child: PartsSection(detail: d, enabled: enabled, onBusyChanged: onBusy ?? (_) {})),
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

  group('PartsSection — unconfirmed cart, locked while sending, lighter list', () {
    testWidgets('the refetch after an add fails → "Couldn\'t confirm the latest parts." + busy stays true; Retry success clears it', (tester) async {
      final repo = _FakeJobRepo();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add);
      repo.jobResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.');
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsOneWidget);
      expect(find.text("Couldn't confirm the latest parts."), findsOneWidget);
      expect(busy.last, isTrue, reason: 'Submit stays blocked while the cart on screen is unconfirmed');
      expect(_addBtn(tester, 'p1').onPressed, isNotNull, reason: 'the per-part busy state was reset');

      repo.jobResultOverride = null;
      await tester.tap(find.byKey(const Key('cartUnconfirmedRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsNothing);
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget);
      expect(busy.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a Retry that fails again keeps the notice and the block', (tester) async {
      final repo = _FakeJobRepo();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add);
      repo.jobResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.');
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cartUnconfirmedRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsOneWidget);
      expect(busy.last, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a later poll that delivers an updated job clears the unconfirmed notice', (tester) async {
      final repo = _FakeJobRepo();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add);
      repo.jobResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.');
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsOneWidget);

      repo.jobResultOverride = null; // the next poll succeeds and carries the line the add created
      await tester.pump(jobPollInterval);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget);
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsNothing);
      expect(busy.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a refetch that THROWS still resets busy (and marks the cart unconfirmed)', (tester) async {
      final repo = _FakeJobRepo();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add, jobDetail: _RefetchThrows.new);
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(repo.addCalls, 1);
      expect(_addBtn(tester, 'p1').onPressed, isNotNull, reason: 'busy reset despite the throw');
      expect(find.byKey(const Key('cartUnconfirmedNotice')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('enabled: false (the estimate is being sent) disables filter, qty, add and remove', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      await _pump(tester, repo, _FakeCatalog(), enabled: false);
      expect(_addBtn(tester, 'p1').onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('qtyPlus_p1'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('qtyMinus_p1'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('removePartBtn_l9'))).onPressed, isNull);
      expect(tester.widget<TextField>(find.byKey(const Key('partsFilter'))).enabled, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an empty filter shows at most 8 parts + "Type to find more parts (N more)"; a filter shows every match', (tester) async {
      await _pump(tester, _FakeJobRepo(), _FakeCatalog(catalogParts: _manyParts(12, name: 'Capacitor')));
      expect(find.byKey(const Key('addPartBtn_p8')), findsOneWidget);
      expect(find.byKey(const Key('addPartBtn_p9')), findsNothing);
      expect(find.byKey(const Key('partsMoreHint')), findsOneWidget);
      expect(find.text('Type to find more parts (4 more)'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('partsFilter')), 'capacitor');
      await tester.pumpAndSettle();
      for (var i = 1; i <= 12; i++) {
        expect(find.byKey(Key('addPartBtn_p$i')), findsOneWidget);
      }
      expect(find.byKey(const Key('partsMoreHint')), findsNothing);

      await tester.enterText(find.byKey(const Key('partsFilter')), 'capacitor 1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addPartBtn_p1')), findsOneWidget);
      expect(find.byKey(const Key('addPartBtn_p10')), findsOneWidget);
      expect(find.byKey(const Key('addPartBtn_p2')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('8 or fewer parts → no "more" hint', (tester) async {
      await _pump(tester, _FakeJobRepo(), _FakeCatalog(catalogParts: _manyParts(8)));
      expect(find.byKey(const Key('addPartBtn_p8')), findsOneWidget);
      expect(find.byKey(const Key('partsMoreHint')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('empty states: an empty catalog and a filter with no match both show "No matching parts"', (tester) async {
      await _pump(tester, _FakeJobRepo(), _FakeCatalog(catalogParts: const []));
      expect(find.byKey(const Key('partsEmpty')), findsOneWidget);
      expect(find.text('No matching parts'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await _pump(tester, _FakeJobRepo(), _FakeCatalog());
      expect(find.byKey(const Key('partsEmpty')), findsNothing);
      await tester.enterText(find.byKey(const Key('partsFilter')), 'zzz');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partsEmpty')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('qty and remove icon buttons carry tooltips (TalkBack)', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      await _pump(tester, repo, _FakeCatalog());
      expect(tester.widget<IconButton>(find.byKey(const Key('qtyMinus_p1'))).tooltip, 'Fewer');
      expect(tester.widget<IconButton>(find.byKey(const Key('qtyPlus_p1'))).tooltip, 'More');
      expect(tester.widget<IconButton>(find.byKey(const Key('removePartBtn_l9'))).tooltip, 'Remove part');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('qty is per part row and survives a rebuild from the poll', (tester) async {
      final repo = _FakeJobRepo();
      await _pump(tester, repo, _FakeCatalog(catalogParts: _manyParts(2)));
      await tester.tap(find.byKey(const Key('qtyPlus_p2')));
      await tester.tap(find.byKey(const Key('qtyPlus_p2')));
      await tester.pump();
      repo.serverParts.add(const JobPartLineDto(id: 'l7', partsCatalogId: 'p1', sku: 'SKU1', name: 'Part 1', qty: 1, ceilingPricePaise: 1000));
      await tester.pump(jobPollInterval); // a poll delivers a changed job → the section rebuilds
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cartLine_l7')), findsOneWidget);
      await tester.tap(find.byKey(const Key('addPartBtn_p2')));
      await tester.pumpAndSettle();
      expect(repo.lastAdd, (partsCatalogId: 'p2', qty: 3));
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
