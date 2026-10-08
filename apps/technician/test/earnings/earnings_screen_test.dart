import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/earnings_providers.dart';
import 'package:fixcare_technician/features/earnings/presentation/earnings_screen.dart';

EarningsSummaryDto summary({int owed = 33000, int net = 13000, int debt = 20000, bool blocked = false, PayoutRequestDto? latest}) => EarningsSummaryDto(
      owedPaise: owed, netPayoutPaise: net, pendingPaise: 48000, cashDebtPaise: debt, cashDebtLimitPaise: 50000,
      acceptBlocked: blocked, payoutMinPaise: 10000, latestPayoutRequest: latest);

PayoutRequestDto req(String status, {String? note, int? paid}) => PayoutRequestDto(
    id: 'p1', status: status, amountPaise: 13000, requestedAt: '2026-10-03T06:00:00.000Z',
    reviewedAt: status == 'REQUESTED' ? null : '2026-10-04T06:00:00.000Z', reviewNote: note, paidPaise: paid);

class _FakeRepo extends EarningsRepository {
  _FakeRepo(this.summaries) : super(Dio());
  final List<Result<EarningsSummaryDto>> summaries;
  int summaryCalls = 0;
  int requestCalls = 0;
  Completer<void>? gate;
  Result<PayoutRequestDto> requestResult = Ok(req('REQUESTED'));
  @override
  Future<Result<EarningsSummaryDto>> summary() async {
    final r = summaries[summaryCalls < summaries.length ? summaryCalls : summaries.length - 1];
    summaryCalls++;
    if (summaryCalls > 1 && gate != null) await gate!.future;
    return r;
  }
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async => const Ok(LedgerPageDto());
  @override
  Future<Result<PayoutRequestDto>> requestPayout() async {
    requestCalls++;
    return requestResult;
  }
}

void main() {
  late _FakeRepo repo;
  Future<void> pump(WidgetTester tester, List<Result<EarningsSummaryDto>> summaries) async {
    repo = _FakeRepo(summaries);
    await tester.pumpWidget(ProviderScope(
      overrides: [earningsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: EarningsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('summary block: owed, pending, cash to hand over', (tester) async {
    await pump(tester, [Ok(summary())]);
    expect(find.text('₹330'), findsOneWidget);
    expect(find.byKey(const Key('pendingTotalText')), findsOneWidget);
    expect(find.textContaining('₹200'), findsWidgets); // cash debt
    expect(find.byKey(const Key('pausedText')), findsNothing);
  });

  testWidgets('blocked: paused line with the debt and the limit', (tester) async {
    await pump(tester, [Ok(summary(debt: 60000, blocked: true, net: 0))]);
    expect(find.text('New jobs are paused until your cash is settled (₹600 of ₹500 limit)'), findsOneWidget);
  });

  testWidgets('eligible → confirm dialog (with the cash clause) → request → summary refreshed', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Request ₹130? FixCare transfers it and confirms here. Your ₹200 cash is settled first.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pumpAndSettle();
    expect(repo.requestCalls, 1);
    expect(repo.summaryCalls, 2);
    expect(find.text('₹130 requested on 3 Oct — FixCare will transfer it soon'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsNothing);
  });

  testWidgets('success snackbar shows the SERVER amount, even when it differs from the dialog', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    repo.requestResult = Ok(PayoutRequestDto(id: 'p2', status: 'REQUESTED', amountPaise: 15000, requestedAt: '2026-10-03T06:00:00.000Z'));
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pump(); // request resolved
    await tester.pump();
    expect(find.text('Payout of ₹150 requested'), findsOneWidget);
  });

  testWidgets('the request button stays disabled until the refreshed summary has loaded', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    repo.gate = Completer<void>(); // gates every summary fetch after the first
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pump();
    await tester.pump();
    expect(repo.requestCalls, 1);
    expect(repo.summaryCalls, 2); // refresh in flight
    expect(tester.widget<FilledButton>(find.byKey(const Key('requestPayoutBtn'))).onPressed, isNull);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('requestPayoutBtn')), findsNothing); // now the open request replaces the button
    expect(repo.requestCalls, 1);
  });

  testWidgets('no cash debt → dialog without the cash clause; cancel sends nothing', (tester) async {
    await pump(tester, [Ok(summary(debt: 0, net: 33000))]);
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Request ₹330? FixCare transfers it and confirms here.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelPayoutBtn')));
    await tester.pumpAndSettle();
    expect(repo.requestCalls, 0);
  });

  testWidgets('below the minimum → disabled + "Payouts start at ₹100"', (tester) async {
    await pump(tester, [Ok(summary(net: 9000))]);
    expect(tester.widget<FilledButton>(find.byKey(const Key('requestPayoutBtn'))).onPressed, isNull);
    expect(find.text('Payouts start at ₹100'), findsOneWidget);
  });

  testWidgets('latest paid / rejected states (button back when eligible)', (tester) async {
    await pump(tester, [Ok(summary(latest: req('PAID')))]);
    expect(find.text('₹130 paid on 4 Oct'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose the first ProviderScope so the second pump starts fresh
    await pump(tester, [Ok(summary(latest: req('REJECTED', note: 'Bank details not confirmed')))]);
    expect(find.text('Not paid: Bank details not confirmed'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsOneWidget);
  });

  testWidgets('paid shows the amount actually paid, not the requested amount', (tester) async {
    await pump(tester, [Ok(summary(latest: req('PAID', paid: 12000)))]);
    expect(find.text('₹120 paid on 4 Oct'), findsOneWidget);
    expect(find.textContaining('₹130 paid'), findsNothing);
  });

  testWidgets('409 already requested → message verbatim + summary refreshed', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    repo.requestResult = const Failure(FailureKind.unknown, 'You already have a payout request in progress', code: 'PAYOUT_ALREADY_REQUESTED');
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('You already have a payout request in progress'), findsOneWidget);
    expect(repo.summaryCalls, 2);
    expect(find.text('₹130 requested on 3 Oct — FixCare will transfer it soon'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsNothing);
  });

  testWidgets('load error → message + Retry reloads', (tester) async {
    await pump(tester, [const Failure(FailureKind.network, 'Network error. Check your connection.'), Ok(summary())]);
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('earningsRetryBtn')));
    await tester.pumpAndSettle();
    expect(find.text('₹330'), findsOneWidget);
  });

  testWidgets('a 500-char reject reason wraps at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, [Ok(summary(latest: req('REJECTED', note: 'word ' * 100)))]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening Earnings re-fetches even when the summary is already cached', (tester) async {
    repo = _FakeRepo([Ok(summary())]);
    final container = ProviderContainer(overrides: [earningsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    final sub = container.listen(earningsSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(earningsSummaryProvider.future);
    expect(repo.summaryCalls, 1);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: EarningsScreen())));
    await tester.pumpAndSettle();
    expect(repo.summaryCalls, 2);
  });

  testWidgets('during a reload the numbers and the payout button stay visible', (tester) async {
    repo = _FakeRepo([Ok(summary()), Ok(summary(owed: 40000))]);
    repo.gate = Completer<void>();
    final container = ProviderContainer(overrides: [earningsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const MaterialApp(home: EarningsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('₹330'), findsOneWidget);
    container.invalidate(earningsSummaryProvider); // gated reload
    await tester.pump();
    expect(find.text('₹330'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    repo.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('₹400'), findsOneWidget);
  });
}
