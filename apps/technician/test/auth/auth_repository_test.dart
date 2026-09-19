import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/data/auth_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = AuthRepository(dio);
  });

  test('sendOtp posts EXACTLY {phone, role:TECHNICIAN} and parses devOtp', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(200, {'ok': true, 'devOtp': '123456'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN'});
    final r = await repo.sendOtp('9990001111');
    expect((r as Ok<SendOtpResponse>).value.devOtp, '123456');
  });

  test('verifyOtp posts {phone, role:TECHNICIAN, otp} and parses tokens + user', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'role': 'TECHNICIAN', 'status': 'ACTIVE'}}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN', 'otp': '123456'});
    final r = await repo.verifyOtp('9990001111', '123456');
    final v = (r as Ok<VerifyResponse>).value;
    expect(v.accessToken, 'a');
    expect(v.user.role, 'TECHNICIAN');
  });

  test('sendOtp 429 -> Failure(rateLimited) with backend message', () async {
    adapter.onPost('/auth/otp/send',
        (s) => s.reply(429, {'code': 'TOO_MANY_REQUESTS', 'message': 'Too many OTP requests. Try again later.'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN'});
    final r = await repo.sendOtp('9990001111');
    final f = r as Failure;
    expect(f.kind, FailureKind.rateLimited);
    expect(f.message, 'Too many OTP requests. Try again later.');
  });

  test('verifyOtp 401 -> Failure(unauthorized)', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired OTP'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN', 'otp': '000000'});
    final r = await repo.verifyOtp('9990001111', '000000');
    expect((r as Failure).kind, FailureKind.unauthorized);
  });
}
