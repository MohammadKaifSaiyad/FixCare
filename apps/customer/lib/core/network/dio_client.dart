import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
import '../../features/auth/data/auth_repository.dart';

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
    // TODO(task5): replace with the real auth controller's session-lost
    // handler, e.g. `() => ref.read(authControllerProvider.notifier).onAuthLost()`.
    // Left as a no-op for this task since authControllerProvider does not
    // exist yet — Task 5 wires the real callback.
    () {},
    dio,
  ));

  return dio;
});
