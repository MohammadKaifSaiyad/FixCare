import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'booking_dtos.dart';

export 'booking_dtos.dart';

class BookingRepository {
  BookingRepository(this._dio);
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

  // The app sends ONLY these three fields. The customer id is derived from the JWT server-side, and the
  // zone + price are snapshotted server-side from addressId — the app never sends either (Golden Rule 4 /
  // Slice-2 carry-forward).
  Future<Result<BookingDto>> create({
    required String addressId,
    required String serviceId,
    required String scheduledSlot,
  }) => _guard(() async {
    final res = await _dio.post('/me/bookings',
        data: {'addressId': addressId, 'serviceId': serviceId, 'scheduledSlot': scheduledSlot});
    return _ok<BookingDto>(res, (data) => BookingDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<BookingDto>> get(String id) => _guard(() async {
    final res = await _dio.get('/me/bookings/$id');
    return _ok<BookingDto>(res, (data) => BookingDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> cancel(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/cancel');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return const Ok(null);
    return Failure(failureKindFromStatus(status), _msg(res.data));
  });
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.read(dioProvider)));
