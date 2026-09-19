import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'technician_job_dto.dart';

export 'technician_job_dto.dart';

class TechnicianJobRepository {
  TechnicianJobRepository(this._dio);
  final Dio _dio;

  // Backend error envelope is { code, message } (errorHandler.ts). Surfaced
  // verbatim — the UI branches on this exact text (403 "Verified technician
  // required", 409 "This job is no longer available", 422 cash-debt).
  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Result<T> _ok<T>(Response res, T Function(dynamic data) parse) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return Ok(parse(res.data));
    return Failure(failureKindFromStatus(status), _msg(res.data));
  }

  Future<Result<T>> _guard<T>(Future<Result<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Result<List<TechnicianJobDto>> _parseList(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! List) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(data.map((e) => TechnicianJobDto.fromJson((e as Map).cast<String, dynamic>())).toList());
    }
    return Failure(failureKindFromStatus(status), _msg(res.data));
  }

  Future<Result<List<TechnicianJobDto>>> available() => _guard(() async {
    final res = await _dio.get('/technician/jobs/available');
    return _parseList(res);
  });

  Future<Result<List<TechnicianJobDto>>> mine() => _guard(() async {
    final res = await _dio.get('/technician/jobs/mine');
    return _parseList(res);
  });

  Future<Result<TechnicianJobDto>> accept(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/accept');
    return _ok<TechnicianJobDto>(res, (data) => TechnicianJobDto.fromJson((data as Map).cast<String, dynamic>()));
  });
}

final technicianJobRepositoryProvider =
    Provider<TechnicianJobRepository>((ref) => TechnicianJobRepository(ref.read(dioProvider)));
