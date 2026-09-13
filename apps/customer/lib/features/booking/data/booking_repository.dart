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
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(parse(data));
    }
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
    return _okVoid(res);
  });

  Future<Result<void>> confirmArrival(String id, String code) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/confirm-arrival', data: {'code': code});
    return _okVoid(res);
  });

  Future<Result<void>> approve(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/approve');
    return _okVoid(res);
  });

  Future<Result<void>> decline(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/decline');
    return _okVoid(res);
  });

  Future<Result<CompletionOtpDto>> requestCompletionOtp(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/request-completion-otp');
    return _ok<CompletionOtpDto>(res, (data) => CompletionOtpDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<PaymentInitDto>> initiatePayment(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/pay');
    return _ok<PaymentInitDto>(res, (data) => PaymentInitDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<CashInitDto>> initiateCashPayment(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/pay-cash');
    return _ok<CashInitDto>(res, (data) => CashInitDto.fromJson((data as Map).cast<String, dynamic>()));
  });
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.read(dioProvider)));
