import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'catalog_dtos.dart';
import '../../profile/data/technician_profile_dto.dart';

export 'catalog_dtos.dart';

class CatalogRepository {
  CatalogRepository(this._dio);
  final Dio _dio;

  // Backend error envelope is { code, message } (errorHandler.ts). The message is
  // surfaced verbatim (403 "Verified technician required", 409 "This job is no
  // longer available", 422 cash-debt); anything that BRANCHES uses the stable
  // `code` (Failure.code, e.g. JOB_NOT_FOUND / ESTIMATE_CHANGED), never the text.
  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Future<Result<T>> _guard<T>(Future<Result<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data), code: errorCodeOf(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Result<List<DiagnosedIssueDto>> _parseIssuesList(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! List) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(data.map((e) => DiagnosedIssueDto.fromJson((e as Map).cast<String, dynamic>())).toList());
    }
    return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
  }

  Result<List<PartCatalogDto>> _parsePartsList(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! List) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(data.map((e) => PartCatalogDto.fromJson((e as Map).cast<String, dynamic>())).toList());
    }
    return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
  }

  Future<Result<List<DiagnosedIssueDto>>> issues({String? categoryId}) => _guard(() async {
    final res = await _dio.get('/catalog/issues', queryParameters: {if (categoryId case final String id) 'categoryId': id});
    return _parseIssuesList(res);
  });

  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) => _guard(() async {
    final res = await _dio.get('/catalog/parts', queryParameters: {if (categoryId case final String id) 'categoryId': id});
    return _parsePartsList(res);
  });

  Future<Result<List<ZoneRefDto>>> zones() => _guard(() async {
    final res = await _dio.get('/catalog/zones');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! List) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(data.map((e) => ZoneRefDto.fromJson((e as Map).cast<String, dynamic>())).toList());
    }
    return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
  });
}

final catalogRepositoryProvider =
    Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(dioProvider)));
