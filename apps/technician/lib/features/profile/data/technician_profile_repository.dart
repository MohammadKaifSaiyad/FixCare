import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'technician_profile_dto.dart';

export 'technician_profile_dto.dart';

class TechnicianProfileRepository {
  TechnicianProfileRepository(this._dio);
  final Dio _dio;

  // Backend error envelope is { code, message } (errorHandler.ts).
  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Result<TechnicianProfileDto> _parse(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(TechnicianProfileDto.fromJson(data.cast<String, dynamic>()));
    }
    return Failure(failureKindFromStatus(status), _msg(res.data));
  }

  Future<Result<TechnicianProfileDto>> getProfile() async {
    try {
      return _parse(await _dio.get('/me/profile'));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }
}

final technicianProfileRepositoryProvider =
    Provider<TechnicianProfileRepository>((ref) => TechnicianProfileRepository(ref.read(dioProvider)));
