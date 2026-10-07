import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'earnings_dtos.dart';

export 'earnings_dtos.dart';

class EarningsRepository {
  EarningsRepository(this._dio);
  final Dio _dio;

  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Future<Result<T>> _call<T>(Future<Response> Function() send, T Function(Map<String, dynamic>) parse) async {
    try {
      final res = await send();
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final data = res.data;
        if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
        return Ok(parse(data.cast<String, dynamic>()));
      }
      return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data), code: errorCodeOf(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Future<Result<EarningsSummaryDto>> summary() => _call(() => _dio.get('/technician/me/earnings'), EarningsSummaryDto.fromJson);

  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) => _call(
        () => _dio.get('/technician/me/ledger', queryParameters: {'limit': limit, if (before case final String b) 'before': b}),
        LedgerPageDto.fromJson,
      );

  /// Bodyless: the backend computes the net amount.
  Future<Result<PayoutRequestDto>> requestPayout() => _call(() => _dio.post('/technician/me/payout-requests'), PayoutRequestDto.fromJson);
}

final earningsRepositoryProvider = Provider<EarningsRepository>((ref) => EarningsRepository(ref.read(dioProvider)));
