import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/statement_section.dart';

LedgerEntryDto e(String id, String type, int paise, {String? booking, String? service}) =>
    LedgerEntryDto(id: id, type: type, amountPaise: paise, bookingNumber: booking, serviceName: service, createdAt: '2026-10-01T06:00:00.000Z');

class _FakeRepo extends EarningsRepository {
  _FakeRepo(this.pages) : super(Dio());
  final Map<String?, Result<LedgerPageDto>> pages;
  final calls = <String?>[];
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async {
    calls.add(before);
    return pages[before] ?? const Ok(LedgerPageDto());
  }
}

void main() {
  test('every ledger type has a label and an effect', () {
    expect(ledgerRowLabel(e('1', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'AC gas refill')), 'Earned · FC-1 · AC gas refill');
    expect(ledgerRowEffect(e('1', 'EARNING_CREDIT', 48000)), 'Owed +₹480');
    expect(ledgerRowLabel(e('2', 'COMMISSION', 12000, booking: 'FC-1')), 'FixCare fee (20%) · FC-1');
    expect(ledgerRowEffect(e('2', 'COMMISSION', 12000)), 'Info · ₹120');
    expect(ledgerRowEffect(e('3', 'CASH_COLLECTED', 50000)), 'Cash to hand over +₹500');
    expect(ledgerRowLabel(e('4', 'CASH_DEBT_OFFSET', 5000)), 'Cash settled from earnings');
    expect(ledgerRowEffect(e('4', 'CASH_DEBT_OFFSET', 5000)), 'Owed −₹50 · Cash −₹50');
    expect(ledgerRowEffect(e('5', 'PAYOUT', 10000)), 'Owed −₹100');
    expect(ledgerRowLabel(e('5', 'PAYOUT', 10000)), 'Paid to you');
    expect(ledgerRowEffect(e('6', 'DEBT_REPAYMENT', 2000)), 'Cash −₹20');
    expect(ledgerRowLabel(e('6', 'DEBT_REPAYMENT', 2000)), 'Cash handed over');
    expect(ledgerRowLabel(e('7', 'DISPUTE_REVERSAL', 3000, booking: 'FC-9')), 'Customer refunded after a dispute · FC-9');
    expect(ledgerRowEffect(e('7', 'DISPUTE_REVERSAL', 3000)), 'Info · ₹30');
    expect(ledgerRowEffect(e('8', 'SOMETHING_NEW', 100)), 'Info · ₹1'); // unknown types never crash
  });

  Future<_FakeRepo> pump(WidgetTester tester, Map<String?, Result<LedgerPageDto>> pages, {List<PendingReleaseDto> pending = const []}) async {
    final repo = _FakeRepo(pages);
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(), // a second pump in one test needs a fresh container
      overrides: [earningsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: ListView(children: [StatementSection(pending: pending)]))),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('pending rows: release time or on hold', (tester) async {
    await pump(tester, {}, pending: const [
      PendingReleaseDto(bookingId: 'b1', bookingNumber: 'FC-1', serviceName: 'AC gas refill', amountPaise: 48000, releasesAt: '2026-10-05T08:30:00.000Z'),
      PendingReleaseDto(bookingId: 'b2', bookingNumber: 'FC-2', serviceName: 'Fan repair', amountPaise: 8000, onHold: true),
    ]);
    expect(find.byKey(const Key('pending_b1')), findsOneWidget);
    expect(find.textContaining('Releases '), findsOneWidget);
    expect(find.text('On hold — under dispute'), findsOneWidget);
  });

  testWidgets('pending row with no release time and not on hold says "Releases soon"', (tester) async {
    await pump(tester, {}, pending: const [
      PendingReleaseDto(bookingId: 'b3', bookingNumber: 'FC-3', serviceName: 'Geyser', amountPaise: 9000),
    ]);
    expect(tester.takeException(), isNull);
    expect(find.text('Releases soon'), findsOneWidget);
  });

  testWidgets('history rows + Load more appends once; hidden at the end', (tester) async {
    final repo = await pump(tester, {
      null: Ok(LedgerPageDto(entries: [e('a', 'PAYOUT', 10000)], nextCursor: 'c1')),
      'c1': Ok(LedgerPageDto(entries: [e('b', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'AC gas refill')])),
    });
    expect(find.byKey(const Key('ledgerRow_a')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('loadMoreBtn')));
    await tester.tap(find.byKey(const Key('loadMoreBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledgerRow_b')), findsOneWidget);
    expect(find.byKey(const Key('loadMoreBtn')), findsNothing);
    expect(repo.calls, [null, 'c1']);
  });

  testWidgets('empty history → "No money movements yet"; error → Retry', (tester) async {
    await pump(tester, {null: const Ok(LedgerPageDto())});
    expect(find.byKey(const Key('ledgerEmpty')), findsOneWidget);
    await pump(tester, {null: const Failure(FailureKind.network, 'Network error. Check your connection.')});
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    expect(find.byKey(const Key('ledgerRetryBtn')), findsOneWidget);
  });

  testWidgets('long service names wrap at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, {null: Ok(LedgerPageDto(entries: [e('a', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'Split AC deep cleaning and gas refill with leak test ' * 3)]))});
    expect(tester.takeException(), isNull);
  });
}
