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

  // NOTE: http_mock_adapter matches on the request body given in `data:`. These
  // bodies are the ACTUAL backend contract (auth.schemas.ts): send + verify BOTH
  // require `role`, and verify's code field is `otp` (^\d{6}$) — NOT `code`. If
  // the repository sends a different shape the mock won't match and the test
  // fails, so these double as contract-guard tests for the request body.

  test('sendOtp posts {phone, role} and 200 → Ok with devOtp', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(200, {'ok': true, 'devOtp': '123456'}),
        data: {'phone': '9999999999', 'role': 'CUSTOMER'});
    final r = await repo.sendOtp('9999999999');
    expect(r, isA<Ok<SendOtpResponse>>());
    expect((r as Ok<SendOtpResponse>).value.devOtp, '123456');
  });

  test('sendOtp 429 → Failure(rateLimited) with the backend {code,message} envelope', () async {
    adapter.onPost('/auth/otp/send',
        (s) => s.reply(429, {'code': 'TOO_MANY_REQUESTS', 'message': 'Too many OTP requests. Try again later.'}),
        data: {'phone': '9999999999', 'role': 'CUSTOMER'});
    final r = await repo.sendOtp('9999999999');
    final f = r as Failure;
    expect(f.kind, FailureKind.rateLimited);
    // The message must come from the `message` key, not collapse to the generic.
    expect(f.message, 'Too many OTP requests. Try again later.');
  });

  test('verifyOtp posts {phone, role, otp} and 200 → Ok with tokens + user', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'role': 'CUSTOMER', 'status': 'ACTIVE'}}),
        data: {'phone': '9999999999', 'role': 'CUSTOMER', 'otp': '123456'});
    final r = await repo.verifyOtp('9999999999', '123456');
    final v = (r as Ok<VerifyResponse>).value;
    expect(v.accessToken, 'a');
    expect(v.user.id, 'u1');
  });

  test('verifyOtp 401 → Failure(unauthorized) with the server message', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Wrong or expired code'}),
        data: {'phone': '9999999999', 'role': 'CUSTOMER', 'otp': '000000'});
    final r = await repo.verifyOtp('9999999999', '000000');
    final f = r as Failure;
    expect(f.kind, FailureKind.unauthorized);
    expect(f.message, 'Wrong or expired code');
  });

  test('refresh 200 → Ok (no user field)', () async {
    adapter.onPost('/auth/refresh', (s) => s.reply(200, {'accessToken': 'a2', 'refreshToken': 'r2'}),
        data: {'refreshToken': 'r1'});
    final r = await repo.refresh('r1');
    expect((r as Ok<RefreshResponse>).value.accessToken, 'a2');
  });

  test('logout posts {refreshToken} and 200 → Ok', () async {
    adapter.onPost('/auth/logout', (s) => s.reply(200, {'ok': true}),
        data: {'refreshToken': 'r1'});
    final r = await repo.logout('r1');
    expect(r, isA<Ok<void>>());
  });
}
