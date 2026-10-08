import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';

Map<String, dynamic> summaryJson() => {
      'owedPaise': 33000, 'netPayoutPaise': 13000, 'pendingPaise': 48000, 'cashDebtPaise': 20000,
      'cashDebtLimitPaise': 50000, 'acceptBlocked': false, 'payoutMinPaise': 10000,
      'pending': [
        {'bookingId': 'b1', 'bookingNumber': 'FC-1', 'serviceName': 'AC gas refill', 'amountPaise': 48000, 'releasesAt': '2026-10-07T08:30:00.000Z', 'onHold': false},
        {'bookingId': 'b2', 'bookingNumber': 'FC-2', 'serviceName': 'Fan repair', 'amountPaise': 8000, 'releasesAt': null, 'onHold': true},
      ],
      'latestPayoutRequest': {'id': 'p1', 'status': 'REJECTED', 'amountPaise': 20000, 'requestedAt': '2026-10-03T00:00:00.000Z', 'reviewedAt': '2026-10-04T00:00:00.000Z', 'reviewNote': 'Bank details not confirmed', 'paidPaise': null},
    };

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late EarningsRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = EarningsRepository(dio);
  });

  test('summary is a bodyless GET and parses every field', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.reply(200, summaryJson()));
    final v = (await repo.summary() as Ok<EarningsSummaryDto>).value;
    expect(v.owedPaise, 33000);
    expect(v.netPayoutPaise, 13000);
    expect(v.pending, hasLength(2));
    expect(v.pending.last.onHold, true);
    expect(v.pending.last.releasesAt, isNull);
    expect(v.latestPayoutRequest!.status, 'REJECTED');
    expect(v.latestPayoutRequest!.reviewNote, 'Bank details not confirmed');
    expect(v.latestPayoutRequest!.paidPaise, isNull);
  });

  test('a PAID payout request parses paidPaise (can differ from the requested amount)', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.reply(200, {
          ...summaryJson(),
          'latestPayoutRequest': {'id': 'p3', 'status': 'PAID', 'amountPaise': 20000, 'paidPaise': 12000, 'requestedAt': '2026-10-03T00:00:00.000Z', 'reviewedAt': '2026-10-04T00:00:00.000Z', 'reviewNote': null},
        }));
    final r = (await repo.summary() as Ok<EarningsSummaryDto>).value.latestPayoutRequest!;
    expect(r.status, 'PAID');
    expect(r.amountPaise, 20000);
    expect(r.paidPaise, 12000);
  });

  test('summary with no request parses latestPayoutRequest as null', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.reply(200, {...summaryJson(), 'pending': <Object>[], 'latestPayoutRequest': null}));
    expect((await repo.summary() as Ok<EarningsSummaryDto>).value.latestPayoutRequest, isNull);
  });

  test('ledger sends limit (+ before when given) and parses the page', () async {
    adapter.onGet('/technician/me/ledger', (s) => s.reply(200, {
          'entries': [
            {'id': 'e1', 'type': 'EARNING_CREDIT', 'amountPaise': 48000, 'bookingNumber': 'FC-1', 'serviceName': 'AC gas refill', 'createdAt': '2026-10-01T00:00:00.000Z'},
            {'id': 'e2', 'type': 'PAYOUT', 'amountPaise': 10000, 'bookingNumber': null, 'serviceName': null, 'createdAt': '2026-09-30T00:00:00.000Z'},
          ],
          'nextCursor': 'abc',
        }), queryParameters: {'limit': 20, 'before': 'xyz'});
    final v = (await repo.ledger(before: 'xyz') as Ok<LedgerPageDto>).value;
    expect(v.entries.map((e) => e.type), ['EARNING_CREDIT', 'PAYOUT']);
    expect(v.entries.last.bookingNumber, isNull);
    expect(v.nextCursor, 'abc');
  });

  test('requestPayout is a bodyless POST; 409 keeps code + message', () async {
    adapter.onPost('/technician/me/payout-requests', (s) => s.reply(200, {'id': 'p2', 'status': 'REQUESTED', 'amountPaise': 13000, 'requestedAt': '2026-10-07T00:00:00.000Z', 'reviewedAt': null, 'reviewNote': null}));
    expect((await repo.requestPayout() as Ok<PayoutRequestDto>).value.status, 'REQUESTED');
    adapter.onPost('/technician/me/payout-requests', (s) => s.reply(409, {'code': 'PAYOUT_ALREADY_REQUESTED', 'message': 'You already have a payout request in progress'}));
    final f = await repo.requestPayout() as Failure;
    expect(f.code, 'PAYOUT_ALREADY_REQUESTED');
    expect(f.message, 'You already have a payout request in progress');
  });

  test('network error → Failure(network)', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.throws(0, DioException.connectionError(requestOptions: RequestOptions(path: '/technician/me/earnings'), reason: 'down')));
    expect((await repo.summary() as Failure).kind, FailureKind.network);
  });
}
