import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'auth_dtos.dart';

export 'auth_dtos.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  // This is the customer app: every OTP registration/login is a CUSTOMER. The
  // backend requires `role` on both /auth/otp/send and /auth/otp/verify (it's
  // ignored for an existing user — their stored role wins — but must be present
  // to pass validation, and it picks the profile type for a brand-new phone).
  static const _role = 'CUSTOMER';

  Future<Result<T>> _post<T>(String path, Object body, T Function(Map<String, dynamic>) parse) async {
    try {
      final res = await _dio.post(path, data: body);
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final data = res.data;
        if (data is! Map) {
          // A 2xx with a non-JSON-object body (empty body, HTML from a proxy)
          // is not something a caller can parse — treat it as a server fault
          // rather than letting an `as Map` cast throw past the Result contract.
          return Failure(FailureKind.server, 'Unexpected response from the server.');
        }
        return Ok(parse(data.cast<String, dynamic>()));
      }
      return Failure(failureKindFromStatus(status), _msg(res.data));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  // The backend error envelope is { code, message } (see errorHandler.ts).
  String _msg(dynamic data) {
    if (data is Map && data['message'] is String) return data['message'] as String;
    return 'Something went wrong.';
  }

  Future<Result<SendOtpResponse>> sendOtp(String phone) =>
      _post('/auth/otp/send', {'phone': phone, 'role': _role}, SendOtpResponse.fromJson);

  Future<Result<VerifyResponse>> verifyOtp(String phone, String otp) =>
      _post('/auth/otp/verify', {'phone': phone, 'role': _role, 'otp': otp}, VerifyResponse.fromJson);

  Future<Result<RefreshResponse>> refresh(String refreshToken) =>
      _post('/auth/refresh', {'refreshToken': refreshToken}, RefreshResponse.fromJson);

  Future<Result<void>> logout(String refreshToken) async {
    final r = await _post('/auth/logout', {'refreshToken': refreshToken}, (_) => null);
    return r is Ok ? const Ok(null) : r as Failure<void>;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.read(dioProvider)));
