import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'address_dtos.dart';

export 'address_dtos.dart';

class AddressRepository {
  AddressRepository(this._dio);
  final Dio _dio;

  // Backend error envelope is { code, message } (errorHandler.ts).
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

  Future<Result<List<AddressDto>>> list() => _guard(() async {
    final res = await _dio.get('/me/addresses');
    return _ok<List<AddressDto>>(res, (data) =>
        (data as List).map((e) => AddressDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });

  Future<Result<AddressDto>> create(Map<String, dynamic> body) => _guard(() async {
    _assertLatLngBothOrNeither(body);
    final res = await _dio.post('/me/addresses', data: body);
    return _ok<AddressDto>(res, (data) => AddressDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<AddressDto>> update(String id, Map<String, dynamic> body) => _guard(() async {
    _assertLatLngBothOrNeither(body);
    final res = await _dio.patch('/me/addresses/$id', data: body);
    return _ok<AddressDto>(res, (data) => AddressDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> delete(String id) => _guard(() async {
    final res = await _dio.delete('/me/addresses/$id');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return const Ok(null); // 204, empty body
    return Failure(failureKindFromStatus(status), _msg(res.data));
  });

  Future<Result<ServiceabilityDto>> checkServiceability(String pincode) => _guard(() async {
    final res = await _dio.get('/serviceability', queryParameters: {'pincode': pincode});
    return _ok<ServiceabilityDto>(res, (data) => ServiceabilityDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  // lat & lng are both-or-neither: enforce before the call ever leaves the device.
  void _assertLatLngBothOrNeither(Map<String, dynamic> body) {
    final hasLat = body.containsKey('lat') && body['lat'] != null;
    final hasLng = body.containsKey('lng') && body['lng'] != null;
    if (hasLat != hasLng) {
      throw ArgumentError('lat and lng must both be set or both omitted');
    }
  }
}

final addressRepositoryProvider =
    Provider<AddressRepository>((ref) => AddressRepository(ref.read(dioProvider)));
