import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
    // Do not throw on any status — repositories map status → Result.
    validateStatus: (_) => true,
  ));
  // Auth interceptor is attached in Task 4 (authInterceptorProvider).
});
