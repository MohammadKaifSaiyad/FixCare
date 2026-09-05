import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'catalog_dtos.dart';

export 'catalog_dtos.dart';

class CatalogRepository {
  CatalogRepository(this._dio);
  final Dio _dio;

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

  Future<Result<List<CategoryDto>>> categories() => _guard(() async {
    final res = await _dio.get('/catalog/categories');
    return _ok<List<CategoryDto>>(res, (data) =>
        (data as List).map((e) => CategoryDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });

  Future<Result<List<ServiceDto>>> services({required String zoneId, String? categoryId}) => _guard(() async {
    final res = await _dio.get('/catalog/services', queryParameters: {
      'zoneId': zoneId,
      if (categoryId != null) 'categoryId': categoryId,
    });
    return _ok<List<ServiceDto>>(res, (data) =>
        (data as List).map((e) => ServiceDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(dioProvider)));
