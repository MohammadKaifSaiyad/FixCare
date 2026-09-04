import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'auth_dtos.dart';

export 'auth_dtos.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<Result<T>> _post<T>(String path, Object body, T Function(Map<String, dynamic>) parse) async {
    try {
      final res = await _dio.post(path, data: body);
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return Ok(parse((res.data as Map).cast<String, dynamic>()));
      }
      return Failure(failureKindFromStatus(status), _msg(res.data));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  String _msg(dynamic data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return 'Something went wrong.';
  }

  Future<Result<SendOtpResponse>> sendOtp(String phone) =>
      _post('/auth/otp/send', {'phone': phone}, SendOtpResponse.fromJson);

  Future<Result<VerifyResponse>> verifyOtp(String phone, String code) =>
      _post('/auth/otp/verify', {'phone': phone, 'code': code}, VerifyResponse.fromJson);

  Future<Result<RefreshResponse>> refresh(String refreshToken) =>
      _post('/auth/refresh', {'refreshToken': refreshToken}, RefreshResponse.fromJson);

  Future<Result<void>> logout(String refreshToken) async {
    final r = await _post('/auth/logout', {'refreshToken': refreshToken}, (_) => null);
    return r is Ok ? const Ok(null) : r as Failure<void>;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.read(dioProvider)));
