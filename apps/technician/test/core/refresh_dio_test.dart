import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/network/auth_interceptor.dart';
import 'package:fixcare_technician/core/network/dio_client.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/storage/token_store.dart';
import 'package:fixcare_technician/features/auth/data/auth_dtos.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.status, this.body);
  final int status;
  final String body;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(body, status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};
  setUp(() {
    backing.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write':
            backing[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'read':
            return backing[call.arguments['key']];
          case 'delete':
            backing.remove(call.arguments['key']);
            return null;
        }
        return null;
      },
    );
  });

  test('a request that 401s, refreshes, and whose RETRY answers 403 TECHNICIAN_NOT_VERIFIED reports the suspension', () async {
    final store = TokenStore();
    await store.save(access: 'old', refresh: 'r1');
    var notVerified = 0;
    // The production refresh/retry client — it must carry the suspension detector.
    final refreshDio = buildRefreshDio(() => notVerified++);
    refreshDio.httpClientAdapter = _Adapter(403, '{"code":"TECHNICIAN_NOT_VERIFIED","message":"Verified technician required"}');
    final dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.httpClientAdapter = _Adapter(401, '{}');
    dio.interceptors.add(AuthInterceptor(
      store,
      (r) async => const Ok(RefreshResponse(accessToken: 'new', refreshToken: 'r2')),
      () {},
      refreshDio,
    ));
    final res = await dio.get<Map<String, dynamic>>('/technician/jobs/mine');
    expect(res.statusCode, 403);
    expect(notVerified, 1);
  });
}
