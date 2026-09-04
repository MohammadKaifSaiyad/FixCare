import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/data/auth_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = AuthRepository(dio);
  });

  test('sendOtp 200 → Ok with devOtp', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(200, {'ok': true, 'devOtp': '123456'}),
        data: {'phone': '9999999999'});
    final r = await repo.sendOtp('9999999999');
    expect(r, isA<Ok<SendOtpResponse>>());
    expect((r as Ok<SendOtpResponse>).value.devOtp, '123456');
  });

  test('sendOtp 429 → Failure(rateLimited)', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(429, {'error': 'slow down'}),
        data: {'phone': '9999999999'});
    final r = await repo.sendOtp('9999999999');
    expect((r as Failure).kind, FailureKind.rateLimited);
  });

  test('verifyOtp 200 → Ok with tokens + user', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'role': 'CUSTOMER', 'status': 'ACTIVE'}}),
        data: {'phone': '9999999999', 'code': '123456'});
    final r = await repo.verifyOtp('9999999999', '123456');
    final v = (r as Ok<VerifyResponse>).value;
    expect(v.accessToken, 'a');
    expect(v.user.id, 'u1');
  });

  test('verifyOtp 401 → Failure(unauthorized)', () async {
    adapter.onPost('/auth/otp/verify', (s) => s.reply(401, {'error': 'bad code'}),
        data: {'phone': '9999999999', 'code': '000000'});
    final r = await repo.verifyOtp('9999999999', '000000');
    expect((r as Failure).kind, FailureKind.unauthorized);
  });

  test('refresh 200 → Ok (no user field)', () async {
    adapter.onPost('/auth/refresh', (s) => s.reply(200, {'accessToken': 'a2', 'refreshToken': 'r2'}),
        data: {'refreshToken': 'r1'});
    final r = await repo.refresh('r1');
    expect((r as Ok<RefreshResponse>).value.accessToken, 'a2');
  });
}
