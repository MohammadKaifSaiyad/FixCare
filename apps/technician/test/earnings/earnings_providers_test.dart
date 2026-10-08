import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/earnings_providers.dart';

LedgerEntryDto _e(String id) => LedgerEntryDto(id: id, type: 'EARNING_CREDIT', amountPaise: 100, createdAt: '2026-10-01T00:00:00.000Z');

class _FakeRepo extends EarningsRepository {
  _FakeRepo() : super(Dio());
  int summaryCalls = 0;
  Result<EarningsSummaryDto> summaryResult = const Failure(FailureKind.server, 'boom');
  final pages = <String?, Result<LedgerPageDto>>{};
  final ledgerCalls = <String?>[];
  Completer<void>? gate;
  final gates = <String?, Completer<void>>{};
  @override
  Future<Result<EarningsSummaryDto>> summary() async {
    summaryCalls++;
    return summaryResult;
  }
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async {
    ledgerCalls.add(before);
    if (gate case final g?) await g.future;
    if (gates[before] case final g?) await g.future;
    return pages[before] ?? const Ok(LedgerPageDto());
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer c;
  setUp(() {
    repo = _FakeRepo();
    c = ProviderContainer(overrides: [earningsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
  });

  test('summary failure surfaces as EarningsLoadException and is NOT auto-retried', () async {
    final sub = c.listen(earningsSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    await expectLater(c.read(earningsSummaryProvider.future), throwsA(isA<EarningsLoadException>()));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(repo.summaryCalls, 1);
  });

  test('ledger: first page, loadMore appends with the cursor, stops at the end', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a'), _e('b')], nextCursor: 'c1'));
    repo.pages['c1'] = Ok(LedgerPageDto(entries: [_e('c')]));
    final first = await c.read(ledgerControllerProvider.future);
    expect(first.entries.map((e) => e.id), ['a', 'b']);
    await c.read(ledgerControllerProvider.notifier).loadMore();
    final after = c.read(ledgerControllerProvider).value!;
    expect(after.entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(after.nextCursor, isNull);
    await c.read(ledgerControllerProvider.notifier).loadMore();
    expect(repo.ledgerCalls, [null, 'c1']); // no call past the end
  });

  test('loadMore while one is in flight is a no-op; a failure is kept as loadMoreError', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a')], nextCursor: 'c1'));
    await c.read(ledgerControllerProvider.future);
    repo.gate = Completer<void>();
    repo.pages['c1'] = const Failure(FailureKind.network, 'Network error. Check your connection.');
    final n = c.read(ledgerControllerProvider.notifier);
    final f1 = n.loadMore();
    final f2 = n.loadMore();
    repo.gate!.complete();
    await Future.wait([f1, f2]);
    expect(repo.ledgerCalls, [null, 'c1']);
    final s = c.read(ledgerControllerProvider).value!;
    expect(s.entries.map((e) => e.id), ['a']);
    expect(s.loadMoreError, 'Network error. Check your connection.');
    expect(s.loadingMore, false);
  });

  test('a loadMore that lands after a refresh is dropped', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a')], nextCursor: 'c1'));
    await c.read(ledgerControllerProvider.future);
    repo.gates[null] = Completer<void>();
    repo.gates['c1'] = Completer<void>();
    repo.pages['c1'] = Ok(LedgerPageDto(entries: [_e('stale')]));
    final n = c.read(ledgerControllerProvider.notifier);
    final more = n.loadMore();
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('fresh')]));
    final refreshed = n.refresh();
    repo.gates[null]!.complete();
    await refreshed;
    expect(c.read(ledgerControllerProvider).value!.entries.map((e) => e.id), ['fresh']);
    repo.gates['c1']!.complete();
    await more;
    final s = c.read(ledgerControllerProvider).value!;
    expect(s.entries.map((e) => e.id), ['fresh']);
    expect(s.loadingMore, false);
    expect(s.loadMoreError, isNull);
  });
}
