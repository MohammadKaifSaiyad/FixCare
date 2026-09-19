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
}
