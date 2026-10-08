import 'package:dio/dio.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/money_card.dart';

EarningsSummaryDto _summary({int debt = 20000, bool blocked = false}) => EarningsSummaryDto(
    owedPaise: 33000, netPayoutPaise: 13000, pendingPaise: 48000, cashDebtPaise: debt, cashDebtLimitPaise: 50000, acceptBlocked: blocked, payoutMinPaise: 10000);

class _FakeRepo extends EarningsRepository {
  _FakeRepo(this.results) : super(Dio());
  final List<Result<EarningsSummaryDto>> results;
  int calls = 0;
  Completer<void>? gateSecondCall;
  @override
  Future<Result<EarningsSummaryDto>> summary() async {
    final i = calls++;
    if (i == 1) await gateSecondCall?.future;
    return results[i < results.length ? i : results.length - 1];
  }
}

void main() {
  Future<_FakeRepo> pump(WidgetTester tester, List<Result<EarningsSummaryDto>> results, {Completer<void>? gate}) async {
    final repo = _FakeRepo(results)..gateSecondCall = gate;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: MoneyCard())),
      GoRoute(path: '/earnings', builder: (_, _) => const Text('EARNINGS PAGE')),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [earningsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows owed, pending and cash to hand over; no paused line', (tester) async {
    await pump(tester, [Ok(_summary())]);
    expect(find.byKey(const Key('moneyCard')), findsOneWidget);
    expect(find.text('Owed to you ₹330'), findsOneWidget);
    expect(find.text('₹480 pending'), findsOneWidget);
    expect(find.text('Cash to hand over ₹200'), findsOneWidget);
    expect(find.textContaining('New jobs are paused'), findsNothing);
  });

  testWidgets('blocked → paused line with the debt and the limit', (tester) async {
    await pump(tester, [Ok(_summary(debt: 60000, blocked: true))]);
    expect(find.text('New jobs are paused until your cash is settled (₹600 of ₹500 limit)'), findsOneWidget);
  });

  testWidgets('load failure → one-line error with the message; Retry reloads', (tester) async {
    final repo = await pump(tester, [const Failure(FailureKind.network, 'Network error. Check your connection.'), Ok(_summary())]);
    expect(find.byKey(const Key('moneyCardError')), findsOneWidget);
    expect(find.textContaining('Network error. Check your connection.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('moneyCardRetryBtn')));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.byKey(const Key('moneyCard')), findsOneWidget);
    expect(find.byKey(const Key('moneyCardError')), findsNothing);
  });

  testWidgets('tap opens /earnings; coming back fetches the summary again', (tester) async {
    final repo = await pump(tester, [Ok(_summary())]);
    expect(repo.calls, 1);
    await tester.tap(find.byKey(const Key('moneyCard')));
    await tester.pumpAndSettle();
    expect(find.text('EARNINGS PAGE'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moneyCard')), findsOneWidget);
    expect(repo.calls, 2);
  });

  testWidgets('a reload keeps showing the old numbers (no blank spacer), then swaps in the new ones', (tester) async {
    final gate = Completer<void>();
    final repo = await pump(tester, [Ok(_summary()), Ok(_summary(debt: 0))], gate: gate);
    await tester.tap(find.byKey(const Key('moneyCard')));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(repo.calls, 2); // reload in flight
    expect(find.byKey(const Key('moneyCard')), findsOneWidget);
    expect(find.text('Cash to hand over ₹200'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Cash to hand over ₹200'), findsNothing);
    expect(find.text('Owed to you ₹330'), findsOneWidget);
  });

  testWidgets('a failed reload shows the error row, not the stale card', (tester) async {
    await pump(tester, [Ok(_summary()), const Failure(FailureKind.network, 'down')]);
    await tester.tap(find.byKey(const Key('moneyCard')));
    await tester.pumpAndSettle();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('moneyCardError')), findsOneWidget);
    expect(find.byKey(const Key('moneyCard')), findsNothing);
  });
}
