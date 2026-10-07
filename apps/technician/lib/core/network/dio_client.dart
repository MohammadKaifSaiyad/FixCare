import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
import 'not_verified_interceptor.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_controller.dart';

/// The bare Dio used for token refresh and for re-sending a request after it. It carries NO auth interceptor
/// (so it can never recurse into a refresh) but DOES carry the suspension detector: a retried request is the one
/// that sees ops' 403 TECHNICIAN_NOT_VERIFIED when the technician was suspended and their access token expired.
Dio buildRefreshDio(void Function() onNotVerified) {
  final d = Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    validateStatus: (_) => true,
  ));
  d.interceptors.add(NotVerifiedInterceptor(onNotVerified));
  return d;
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    // NOTE: do NOT set a global contentType. dio sets `application/json`
    // automatically when a request carries a Map body (POST/PATCH). Setting it
    // globally also stamps it on bodyless requests (GET/DELETE), and the
    // backend (Fastify) then rejects an empty body with content-type
    // application/json (FST_ERR_CTP_EMPTY_JSON_BODY) — which broke DELETE
    // /me/addresses/:id. Leaving it unset lets bodyless requests send no
    // content-type, and bodied ones still get application/json.
    // Do not throw on any status — repositories map status → Result.
    validateStatus: (_) => true,
  ));

  // Lazy read at call time (no provider cycle); refreshProfile de-dupes a burst of 403s into one fetch.
  void onNotVerified() => unawaited(ref.read(authControllerProvider.notifier).refreshProfile());

  // Separate, bare Dio for refresh/retry — it carries NO AuthInterceptor, so
  // routing refresh/retry calls through it can never recurse back into
  // this same AuthInterceptor. This also breaks what would otherwise be a
  // provider cycle: dio -> interceptor -> AuthRepository -> dio.
  final refreshDio = buildRefreshDio(onNotVerified);

  final store = ref.read(tokenStoreProvider);
  final refreshRepo = AuthRepository(refreshDio);

  // Sees the responses that come back through this client. A request retried after a token refresh goes through
  // refreshDio instead (the AuthInterceptor resolves it directly), so that client carries its own detector.
  dio.interceptors.add(NotVerifiedInterceptor(onNotVerified));

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
