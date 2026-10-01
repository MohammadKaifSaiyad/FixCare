import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';

Map<String, dynamic> _job() => {
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': 'DISPATCHED', 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': 'Padra', 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
};

void main() {
  late Dio dio; late DioAdapter adapter; late TechnicianJobRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = TechnicianJobRepository(dio);
  });

  test('available parses a job list (full address, masked phone, no name)', () async {
    adapter.onGet('/technician/jobs/available', (s) => s.reply(200, [_job()]));
    final v = (await repo.available() as Ok<List<TechnicianJobDto>>).value;
    expect(v.single.bookingNumber, 'FC-1');
    expect(v.single.address.line1, 'A/27 Umiya Nagar');
    expect(v.single.customer.maskedPhone, '••••••8384');
  });

  test('available 403 Verified technician required -> Failure with that message', () async {
    adapter.onGet('/technician/jobs/available',
        (s) => s.reply(403, {'code': 'FORBIDDEN', 'message': 'Verified technician required'}));
    expect((await repo.available() as Failure).message, 'Verified technician required');
  });

  test('accept is a bodyless POST and parses the job', () async {
    adapter.onPost('/technician/jobs/b1/accept', (s) => s.reply(200, {..._job(), 'state': 'ACCEPTED'}));
    final v = (await repo.accept('b1') as Ok<TechnicianJobDto>).value;
    expect(v.state, 'ACCEPTED');
  });

  test('accept 409 already taken -> Failure with that message', () async {
    adapter.onPost('/technician/jobs/b1/accept',
        (s) => s.reply(409, {'code': 'CONFLICT', 'message': 'This job is no longer available'}));
    expect((await repo.accept('b1') as Failure).message, 'This job is no longer available');
  });

  test('accept 422 cash-debt -> Failure with that message', () async {
    adapter.onPost('/technician/jobs/b1/accept',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Settle your cash debt to accept new jobs'}));
    expect((await repo.accept('b1') as Failure).message, 'Settle your cash debt to accept new jobs');
  });

  test('enRoute bodyless POST 200 -> Ok(void)', () async {
    adapter.onPost('/technician/jobs/b1/en-route', (s) => s.reply(200, {'id': 'b1', 'state': 'EN_ROUTE'}));
    expect(await repo.enRoute('b1'), isA<Ok<void>>());
  });

  test('arrive POSTs {lat,lng} and parses {arrivalCode, withinGeofence}', () async {
    adapter.onPost('/technician/jobs/b1/arrive', (s) => s.reply(200, {'arrivalCode': '482913', 'withinGeofence': true}),
        data: {'lat': 22.24, 'lng': 73.10});
    final v = (await repo.arrive('b1', lat: 22.24, lng: 73.10) as Ok<ArriveResultDto>).value;
    expect(v.arrivalCode, '482913');
    expect(v.withinGeofence, true);
  });

  test('arrive 422 too far -> Failure with backend message', () async {
    adapter.onPost('/technician/jobs/b1/arrive',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'You are too far from the customer location'}),
        data: {'lat': 0.0, 'lng': 0.0});
    expect((await repo.arrive('b1', lat: 0.0, lng: 0.0) as Failure).message, 'You are too far from the customer location');
  });

  test('diagnose POSTs {diagnosedIssueId}; 422 photo-gate surfaced', () async {
    adapter.onPost('/technician/jobs/b1/diagnose', (s) => s.reply(200, {'id': 'b1', 'state': 'DIAGNOSED'}),
        data: {'diagnosedIssueId': 'i1'});
    expect(await repo.diagnose('b1', 'i1'), isA<Ok<void>>());
    adapter.onPost('/technician/jobs/b2/diagnose',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': '2 diagnosis photos required (overview + close-up)'}),
        data: {'diagnosedIssueId': 'i1'});
    expect((await repo.diagnose('b2', 'i1') as Failure).message, '2 diagnosis photos required (overview + close-up)');
  });

  test('addPart POSTs {partsCatalogId,qty} 201 -> Ok(lineId); removePart DELETE 204 -> Ok(void)', () async {
    adapter.onPost('/technician/jobs/b1/parts', (s) => s.reply(201, {'id': 'line1'}),
        data: {'partsCatalogId': 'p1', 'qty': 2});
    expect((await repo.addPart('b1', partsCatalogId: 'p1', qty: 2) as Ok<String>).value, 'line1');
    adapter.onDelete('/technician/jobs/b1/parts/line1', (s) => s.reply(204, null));
    expect(await repo.removePart('b1', 'line1'), isA<Ok<void>>());
  });

  test('startRepair/completeRepair/partsNeeded/partsAcquired are bodyless POSTs -> Ok(void)', () async {
    for (final ep in ['start-repair', 'complete-repair', 'parts-needed', 'parts-acquired']) {
      adapter.onPost('/technician/jobs/b1/$ep', (s) => s.reply(200, {'id': 'b1', 'state': 'X'}));
    }
    expect(await repo.startRepair('b1'), isA<Ok<void>>());
    expect(await repo.completeRepair('b1'), isA<Ok<void>>());
    expect(await repo.partsNeeded('b1'), isA<Ok<void>>());
    expect(await repo.partsAcquired('b1'), isA<Ok<void>>());
  });

  test('completeRepair 422 photo-gate -> Failure with message', () async {
    adapter.onPost('/technician/jobs/b3/complete-repair',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': '3 repair photos required (old part removed, new packaging, installed)'}));
    expect((await repo.completeRepair('b3') as Failure).message, startsWith('3 repair photos required'));
  });

  test('confirmCompletion POSTs {code}; 401 invalid surfaced', () async {
    adapter.onPost('/technician/jobs/b1/confirm-completion', (s) => s.reply(200, {'id': 'b1', 'state': 'CUSTOMER_CONFIRMED'}),
        data: {'code': '123456'});
    expect(await repo.confirmCompletion('b1', '123456'), isA<Ok<void>>());
    adapter.onPost('/technician/jobs/b2/confirm-completion',
        (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired completion code'}),
        data: {'code': '000000'});
    expect((await repo.confirmCompletion('b2', '000000') as Failure).message, 'Invalid or expired completion code');
  });

  test('confirmCash POSTs {code}, parses {id,state,cashDebtPaise}; 422 cash-limit surfaced', () async {
    adapter.onPost('/technician/jobs/b1/confirm-cash',
        (s) => s.reply(200, {'id': 'b1', 'state': 'PAYMENT_RECEIVED', 'cashDebtPaise': 40100}),
        data: {'code': '654321'});
    final v = (await repo.confirmCash('b1', '654321') as Ok<CashResultDto>).value;
    expect(v.state, 'PAYMENT_RECEIVED');
    expect(v.cashDebtPaise, 40100);
    adapter.onPost('/technician/jobs/b2/confirm-cash',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Outstanding cash debt limit reached — please pay by UPI'}),
        data: {'code': '654321'});
    expect((await repo.confirmCash('b2', '654321') as Failure).message, startsWith('Outstanding cash debt limit reached'));
  });

  test('signPhoto POSTs {kind,contentLengthBytes} -> {url,key,expiresAt}; confirmPhoto POSTs the full body', () async {
    adapter.onPost('/technician/jobs/b1/photos/sign',
        (s) => s.reply(200, {'url': 'https://dev-r2.local/upload/k', 'key': 'jobs/b1/DIAGNOSIS_OVERVIEW-x.jpg', 'expiresAt': '2026-09-21T00:00:00.000Z'}),
        data: {'kind': 'DIAGNOSIS_OVERVIEW', 'contentLengthBytes': 400000});
    final sign = (await repo.signPhoto('b1', kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 400000) as Ok<PhotoSignDto>).value;
    expect(sign.key, contains('DIAGNOSIS_OVERVIEW'));
    adapter.onPost('/technician/jobs/b1/photos',
        (s) => s.reply(201, {'id': 'ph1', 'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z'}),
        data: {'kind': 'DIAGNOSIS_OVERVIEW', 'key': sign.key, 'capturedAt': '2026-09-20T10:00:00.000Z', 'geotagLat': 22.24, 'geotagLng': 73.10});
    final conf = (await repo.confirmPhoto('b1', kind: 'DIAGNOSIS_OVERVIEW', key: sign.key, capturedAt: '2026-09-20T10:00:00.000Z', geotagLat: 22.24, geotagLng: 73.10) as Ok<PhotoConfirmDto>).value;
    expect(conf.id, 'ph1');
  });

  test('mine() 408 -> Failure(network), not unknown (transient: a slow gateway timeout, not a rejection)', () async {
    adapter.onGet('/technician/jobs/mine', (s) => s.reply(408, {'code': 'REQUEST_TIMEOUT', 'message': 'Request timed out'}));
    final f = await repo.mine() as Failure;
    expect(f.kind, FailureKind.network);
    expect(f.message, 'Request timed out');
  });

  test('confirmPhoto omits geotag keys entirely when not provided', () async {
    adapter.onPost('/technician/jobs/b1/photos',
        (s) => s.reply(201, {'id': 'ph2', 'kind': 'REPAIR_OLD_PART', 'capturedAt': '2026-09-20T10:00:00.000Z'}),
        data: {'kind': 'REPAIR_OLD_PART', 'key': 'jobs/b1/REPAIR_OLD_PART-y.jpg', 'capturedAt': '2026-09-20T10:00:00.000Z'});
    expect(await repo.confirmPhoto('b1', kind: 'REPAIR_OLD_PART', key: 'jobs/b1/REPAIR_OLD_PART-y.jpg', capturedAt: '2026-09-20T10:00:00.000Z'), isA<Ok<PhotoConfirmDto>>());
  });
}
