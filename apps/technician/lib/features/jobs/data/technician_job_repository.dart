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

  Result<void> _okVoid(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return const Ok(null);
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

  /// The job-detail screen's poll target: one job + its parts cart. 403 = not yours, 404 = gone.
  Future<Result<TechnicianJobDetailDto>> job(String id) => _guard(() async {
    final res = await _dio.get('/technician/jobs/$id');
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) return Failure(failureKindFromStatus(status), _msg(res.data));
    final data = res.data;
    if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
    final map = data.cast<String, dynamic>();
    final rawParts = map['parts'];
    return Ok(TechnicianJobDetailDto(
      job: TechnicianJobDto.fromJson(map),
      parts: rawParts is List
          ? rawParts.map((e) => JobPartLineDto.fromJson((e as Map).cast<String, dynamic>())).toList()
          : const <JobPartLineDto>[],
    ));
  });

  Future<Result<TechnicianJobDto>> accept(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/accept');
    return _ok<TechnicianJobDto>(res, (data) => TechnicianJobDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> enRoute(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/en-route');
    return _okVoid(res);
  });

  Future<Result<ArriveResultDto>> arrive(String id, {required double lat, required double lng}) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/arrive', data: {'lat': lat, 'lng': lng});
    return _ok<ArriveResultDto>(res, (data) => ArriveResultDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> diagnose(String id, String diagnosedIssueId) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/diagnose', data: {'diagnosedIssueId': diagnosedIssueId});
    return _okVoid(res);
  });

  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/parts', data: {'partsCatalogId': partsCatalogId, 'qty': qty});
    return _ok<String>(res, (data) => (data as Map)['id'] as String);
  });

  Future<Result<void>> removePart(String id, String partId) => _guard(() async {
    final res = await _dio.delete('/technician/jobs/$id/parts/$partId');
    return _okVoid(res);
  });

  Future<Result<void>> partsNeeded(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/parts-needed');
    return _okVoid(res);
  });

  Future<Result<void>> partsAcquired(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/parts-acquired');
    return _okVoid(res);
  });

  Future<Result<void>> startRepair(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/start-repair');
    return _okVoid(res);
  });

  Future<Result<void>> completeRepair(String id) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/complete-repair');
    return _okVoid(res);
  });

  Future<Result<void>> confirmCompletion(String id, String code) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/confirm-completion', data: {'code': code});
    return _okVoid(res);
  });

  Future<Result<CashResultDto>> confirmCash(String id, String code) => _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/confirm-cash', data: {'code': code});
    return _ok<CashResultDto>(res, (data) => CashResultDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<PhotoSignDto>> signPhoto(String id, {required String kind, required int contentLengthBytes}) =>
      _guard(() async {
    final res = await _dio.post('/technician/jobs/$id/photos/sign',
        data: {'kind': kind, 'contentLengthBytes': contentLengthBytes});
    return _ok<PhotoSignDto>(res, (data) => PhotoSignDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<PhotoConfirmDto>> confirmPhoto(String id,
      {required String kind,
      required String key,
      required String capturedAt,
      double? geotagLat,
      double? geotagLng}) => _guard(() async {
    final body = <String, dynamic>{'kind': kind, 'key': key, 'capturedAt': capturedAt};
    if (geotagLat != null && geotagLng != null) {
      body['geotagLat'] = geotagLat;
      body['geotagLng'] = geotagLng;
    }
    final res = await _dio.post('/technician/jobs/$id/photos', data: body);
    return _ok<PhotoConfirmDto>(res, (d) => PhotoConfirmDto.fromJson((d as Map).cast<String, dynamic>()));
  });
}

final technicianJobRepositoryProvider =
    Provider<TechnicianJobRepository>((ref) => TechnicianJobRepository(ref.read(dioProvider)));
