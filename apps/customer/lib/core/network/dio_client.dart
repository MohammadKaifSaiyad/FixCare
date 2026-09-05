import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_controller.dart';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
    // Do not throw on any status — repositories map status → Result.
    validateStatus: (_) => true,
  ));

  // Separate, bare Dio for refresh/retry — it carries NO interceptor, so
  // routing refresh/retry calls through it can never recurse back into
  // this same AuthInterceptor. This also breaks what would otherwise be a
  // provider cycle: dio -> interceptor -> AuthRepository -> dio.
  final refreshDio = Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    validateStatus: (_) => true,
  ));

  final store = ref.read(tokenStoreProvider);
  final refreshRepo = AuthRepository(refreshDio);

  dio.interceptors.add(AuthInterceptor(
    store,
    refreshRepo.refresh,
    // Lazy ref.read at call time (not build time) so we don't force the
    // auth controller to build during dio construction, and to avoid a
    // provider cycle. When a refresh fails, drop to unauthenticated.
    () => ref.read(authControllerProvider.notifier).onAuthLost(),
    // Retry through the bare, interceptor-free dio — a retried request that
    // 401s again must NOT re-enter this interceptor (no recursive refresh).
    refreshDio,
  ));

  return dio;
});
