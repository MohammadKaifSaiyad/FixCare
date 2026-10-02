import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/network/not_verified_interceptor.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late int calls;
  setUp(() {
    calls = 0;
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.interceptors.add(NotVerifiedInterceptor(() => calls++));
    adapter = DioAdapter(dio: dio);
  });

  test('403 TECHNICIAN_NOT_VERIFIED → callback, response passed through', () async {
    adapter.onGet('/technician/jobs/mine', (s) => s.reply(403, {'code': 'TECHNICIAN_NOT_VERIFIED', 'message': 'Verified technician required'}));
    final res = await dio.get('/technician/jobs/mine');
    expect(res.statusCode, 403);
    expect(calls, 1);
  });

  test('other 403s, other codes and successes → no callback', () async {
    adapter.onGet('/a', (s) => s.reply(403, {'code': 'JOB_NOT_ASSIGNED', 'message': 'x'}));
    adapter.onGet('/b', (s) => s.reply(409, {'code': 'TECHNICIAN_NOT_VERIFIED', 'message': 'x'}));
    adapter.onGet('/c', (s) => s.reply(200, {'ok': true}));
    await dio.get('/a');
    await dio.get('/b');
    await dio.get('/c');
    expect(calls, 0);
  });
}
