import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/parts_cart.dart';

Map<String, dynamic> _jobJson({String id = 'b1'}) => {
  'id': id, 'bookingNumber': 'FC-1', 'state': 'DIAGNOSED', 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': null, 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
};

TechnicianJobDto _dto({String id = 'b1'}) => TechnicianJobDto.fromJson(_jobJson(id: id));

class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());

  Result<List<PartCatalogDto>> partsResult = const Ok([
    PartCatalogDto(id: 'p1', sku: 'FAN-CAP', name: 'Fan capacitor 2.5 MFD', categoryId: 'c1', ceilingPricePaise: 15000, status: 'ACTIVE'),
    PartCatalogDto(id: 'p2', sku: 'FAN-BRG', name: 'Bearing set', categoryId: 'c1', ceilingPricePaise: 8000, status: 'ACTIVE'),
  ]);

  int partsCalls = 0;

  /// When true, parts() throws (a non-Dio failure -> the provider's AsyncError).
  bool partsThrows = false;

  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async {
    partsCalls++;
    if (partsThrows) throw StateError('boom');
    return partsResult;
  }

  @override
  Future<Result<List<DiagnosedIssueDto>>> issues({String? categoryId}) async => const Ok([]);
}

class _FakeJobRepo extends TechnicianJobRepository {
  _FakeJobRepo() : super(Dio());

  int addPartCalls = 0;
  ({String id, String partsCatalogId, int qty})? lastAddPart;
  Result<String> addPartResult = const Ok('line-1');

  int removePartCalls = 0;
  ({String id, String partId})? lastRemovePart;
  Result<void> removePartResult = const Ok(null);

  @override
  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) async {
    addPartCalls++;
    lastAddPart = (id: id, partsCatalogId: partsCatalogId, qty: qty);
    return addPartResult;
  }

  @override
  Future<Result<void>> removePart(String id, String partId) async {
    removePartCalls++;
    lastRemovePart = (id: id, partId: partId);
    return removePartResult;
  }
}

Future<void> _pump(WidgetTester tester, ProviderContainer container, TechnicianJobDto job) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: PartsCartCard(job: job))),
    ),
  );
}

void main() {
  group('indicativeEstimatePaise', () {
    test('labor 20000 + 2x15000 - visitFee 9900 = 40100', () {
      final job = _dto();
      const part = PartCatalogDto(
        id: 'p1', sku: 'FAN-CAP', name: 'Fan capacitor', categoryId: 'c1', ceilingPricePaise: 15000, status: 'ACTIVE',
      );
      final lines = [const CartLine(lineId: 'l1', part: part, qty: 2)];
      expect(indicativeEstimatePaise(job, lines), 40100);
    });

    test('floors at 0 when visit fee exceeds labor + parts', () {
      final job = TechnicianJobDto.fromJson(_jobJson()..addAll({'laborPaise': 500, 'visitFeePaise': 9900}));
      expect(indicativeEstimatePaise(job, const []), 0);
    });
  });

  testWidgets('parts render from parts()', (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    expect(find.text('Fan capacitor 2.5 MFD'), findsOneWidget);
    expect(find.text('Bearing set'), findsOneWidget);
  });

  testWidgets('add with qty 2 calls addPart(qty:2), cartLine appears, estimate updates', (tester) async {
    final jobRepo = _FakeJobRepo()..addPartResult = const Ok('line-1');
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('qtyPlus_p1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('addPartBtn_p1')));
    await tester.pumpAndSettle();

    expect(jobRepo.addPartCalls, 1);
    expect(jobRepo.lastAddPart, (id: 'b1', partsCatalogId: 'p1', qty: 2));
    expect(find.byKey(const Key('cartLine_line-1')), findsOneWidget);
    expect(find.textContaining('Fan capacitor 2.5 MFD × 2'), findsOneWidget);

    // Estimate: labor 20000 + 2*15000 - visitFee 9900 = 40100 = ₹401
    expect(
      tester.widget<Text>(find.byKey(const Key('indicativeEstimate'))).data,
      'Indicative estimate: ₹401',
    );
  });

  testWidgets('remove calls removePart, line disappears, estimate reverts', (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addPartBtn_p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cartLine_line-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('removePartBtn_line-1')));
    await tester.pumpAndSettle();

    expect(jobRepo.removePartCalls, 1);
    expect(jobRepo.lastRemovePart, (id: 'b1', partId: 'line-1'));
    expect(find.byKey(const Key('cartLine_line-1')), findsNothing);
    // Back to labor 20000 - visitFee 9900 = 10100 = ₹101
    expect(
      tester.widget<Text>(find.byKey(const Key('indicativeEstimate'))).data,
      'Indicative estimate: ₹101',
    );
  });

  testWidgets('addPart Failure (frozen cart) shows a SnackBar with the message verbatim', (tester) async {
    final jobRepo = _FakeJobRepo()
      ..addPartResult = const Failure(FailureKind.unknown, 'The cart is frozen — the booking is no longer in DIAGNOSED');
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addPartBtn_p1')));
    await tester.pumpAndSettle();

    expect(find.text('The cart is frozen — the booking is no longer in DIAGNOSED'), findsOneWidget);
    expect(find.byKey(const Key('cartLine_line-1')), findsNothing);
  });

  testWidgets('parts filter narrows the list by name', (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('partsFilter')), 'bearing');
    await tester.pumpAndSettle();

    expect(find.text('Bearing set'), findsOneWidget);
    expect(find.text('Fan capacitor 2.5 MFD'), findsNothing);
  });

  testWidgets('cart survives disposing and re-pumping the card in the same container (keepAlive)', (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo();
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addPartBtn_p1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cartLine_line-1')), findsOneWidget);

    // Dispose the widget tree entirely, then re-pump the card in the SAME
    // container — the cart line must still be there (keepAlive provider).
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cartLine_line-1')), findsOneWidget);
  });

  testWidgets('parts() Failure shows the message + partsRetry; retry re-fetches and the list recovers',
      (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo()
      ..partsResult = const Failure(FailureKind.network, 'Network error. Check your connection.');
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    expect(find.byKey(const Key('partsRetry')), findsOneWidget);

    // The blip clears; retry must recover without leaving the screen.
    catalogRepo.partsResult = const Ok([
      PartCatalogDto(id: 'p1', sku: 'FAN-CAP', name: 'Fan capacitor 2.5 MFD', categoryId: 'c1', ceilingPricePaise: 15000, status: 'ACTIVE'),
    ]);
    final callsBefore = catalogRepo.partsCalls;
    await tester.tap(find.byKey(const Key('partsRetry')));
    await tester.pumpAndSettle();

    expect(catalogRepo.partsCalls, greaterThan(callsBefore));
    expect(find.text('Fan capacitor 2.5 MFD'), findsOneWidget);
    expect(find.byKey(const Key('partsRetry')), findsNothing);
  });

  testWidgets('parts() throwing shows "Something went wrong." + partsRetry', (tester) async {
    final jobRepo = _FakeJobRepo();
    final catalogRepo = _FakeCatalogRepo()..partsThrows = true;
    final container = ProviderContainer(overrides: [
      technicianJobRepositoryProvider.overrideWithValue(jobRepo),
      catalogRepositoryProvider.overrideWithValue(catalogRepo),
    ]);
    addTearDown(container.dispose);

    await _pump(tester, container, _dto());
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.byKey(const Key('partsRetry')), findsOneWidget);
  });
}
