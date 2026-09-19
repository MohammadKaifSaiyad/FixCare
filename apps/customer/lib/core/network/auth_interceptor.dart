import 'package:dio/dio.dart';

import '../../features/auth/data/auth_dtos.dart';
import '../result.dart';
import '../storage/token_store.dart';

/// Attaches the bearer access token to outgoing requests and, on a 401
/// response (for any path other than `/auth/*`), performs a single-flight
/// token refresh and retries the original request exactly once.
///
/// Single-flight: when N requests 401 concurrently, only the first to reach
/// [onResponse] starts [_doRefresh]; every other concurrent 401 awaits the
/// SAME in-flight future rather than calling refresh again. This is the
/// load-bearing invariant — see test/auth/auth_interceptor_test.dart.
///
/// Session teardown: the session is torn down (tokens cleared + [_onAuthLost])
/// on BOTH an unrefreshable 401 AND a retried-401 — i.e. when refresh succeeds
/// but the retried request is STILL rejected (new token already revoked / clock
/// skew / server-side logout race). In either case the user is ejected rather
/// than left looping 401s with a dead token.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._refresh, this._onAuthLost, this._retryDio);

  final TokenStore _store;
  final Future<Result<RefreshResponse>> Function(String refreshToken) _refresh;
  final void Function() _onAuthLost;
  final Dio _retryDio;

  // Single-flight guard. Holds the in-progress refresh's outcome so that
  // concurrent 401s can await the exact same future instead of triggering
  // their own refresh call.
  Future<bool>? _inFlight;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!options.path.startsWith('/auth/')) {
      final access = await _store.readAccess();
      if (access != null) {
        options.headers['Authorization'] = 'Bearer $access';
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.statusCode != 401 || response.requestOptions.path.startsWith('/auth/')) {
      handler.next(response);
      return;
    }

    final refreshed = await _refreshOnce();
    if (!refreshed) {
      _onAuthLost();
      handler.next(response); // surface the original 401
      return;
    }

    try {
      final retried = await _retry(response.requestOptions);
      if (retried.statusCode == 401) {
        // Refresh succeeded but the retried request 401s again (new token
        // already revoked / clock skew / server-side logout race). Without
        // this, the caller sees a 401 but the session is never torn down —
        // the user is stuck on an authenticated route with a dead token,
        // looping 401s with no recovery. Treat this exactly like an
        // unrefreshable 401: clear tokens and eject.
        await _store.clear();
        _onAuthLost();
      }
      handler.resolve(retried);
    } catch (e) {
      // Defense in depth: the retried-401 eject above assumes _retryDio returns
      // the 401 as a Response (validateStatus:(_)=>true, as dio_client wires it).
      // If a retry Dio were ever configured to THROW on 4xx instead, a retried
      // 401 would land here — still tear the session down so the guarantee holds
      // regardless of the retry Dio's validateStatus.
      if (e is DioException && e.response?.statusCode == 401) {
        await _store.clear();
        _onAuthLost();
      }
      handler.next(response);
    }
  }

  /// Ensures exactly one [_doRefresh] runs per refresh cycle, even when
  /// many requests 401 concurrently. Captures the in-flight future in a
  /// local before awaiting it, and only the caller that created it clears
  /// the guard afterward — this avoids the race the brief calls out where
  /// a second waiter could see `_inFlight` reset to null mid-await and
  /// kick off a duplicate refresh.
  Future<bool> _refreshOnce() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }
    final future = _doRefresh();
    _inFlight = future;
    // Whoever started this refresh clears the guard once it settles, so
    // the NEXT distinct 401 (a later, separate cycle) can trigger a fresh
    // refresh rather than reusing a stale completed future forever.
    future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<bool> _doRefresh() async {
    final refreshToken = await _store.readRefresh();
    if (refreshToken == null) {
      await _store.clear();
      return false;
    }
    final result = await _refresh(refreshToken);
    if (result is Ok<RefreshResponse>) {
      await _store.save(access: result.value.accessToken, refresh: result.value.refreshToken);
      return true;
    }
    await _store.clear();
    return false;
  }

  Future<Response> _retry(RequestOptions o) async {
    final access = await _store.readAccess();
    final headers = Map<String, dynamic>.from(o.headers)..['Authorization'] = 'Bearer $access';
    return _retryDio.request<dynamic>(
      o.path,
      data: o.data,
      queryParameters: o.queryParameters,
      options: Options(method: o.method, headers: headers),
    );
  }
}
