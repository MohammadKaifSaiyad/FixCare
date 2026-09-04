import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/network/auth_interceptor.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';
import 'package:fixcare_customer/features/auth/data/auth_dtos.dart';

/// Hand-rolled adapter: avoids http_mock_adapter's flaky header-matching
/// (see task-4-brief.md NOTE). Tracks the "current" valid access token and
/// replies 401 to any request whose Authorization header doesn't match it,
/// 200 otherwise. The AuthInterceptor's `refresh` callback is a plain
/// Dart function (not routed through this adapter), so refresh count is
/// asserted via that callback's own counter, not via request logging here.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.currentToken);

  String currentToken;
  final List<String> requestLog = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestLog.add('${options.method} ${options.path}');

    final auth = options.headers['Authorization'] as String?;
    if (auth == 'Bearer $currentToken') {
      return ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 401, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageBacking = <String, String>{};

  setUp(() {
    secureStorageBacking.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write':
            secureStorageBacking[call.arguments['key']] = call.arguments['value'];
            return null;
          case 'read':
            return secureStorageBacking[call.arguments['key']];
          case 'delete':
            secureStorageBacking.remove(call.arguments['key']);
            return null;
          case 'deleteAll':
            secureStorageBacking.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(secureStorageBacking);
          case 'containsKey':
            return secureStorageBacking.containsKey(call.arguments['key']);
        }
        return null;
      },
    );
  });

  test('N concurrent 401s trigger exactly ONE refresh, all retried succeed', () async {
    final store = TokenStore();
    await store.save(access: 'old', refresh: 'r1');

    // Server only accepts 'new' — every request with the stored 'old' token
    // 401s until refresh runs, which is exactly what should trigger it.
    final stub = _StubAdapter('new');
    final dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.httpClientAdapter = stub;

    int refreshCalls = 0;
    Future<Result<RefreshResponse>> refresh(String r) async {
      refreshCalls++;
      // Simulate real refresh latency so concurrent 401s genuinely race
      // while _inFlight is set.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      stub.currentToken = 'new';
      await store.save(access: 'new', refresh: 'r2');
      return const Ok(RefreshResponse(accessToken: 'new', refreshToken: 'r2'));
    }

    dio.interceptors.add(AuthInterceptor(store, refresh, () {}, dio));

    final results = await Future.wait([
      dio.get<Map<String, dynamic>>('/me/a'),
      dio.get<Map<String, dynamic>>('/me/b'),
      dio.get<Map<String, dynamic>>('/me/c'),
    ]);

    expect(refreshCalls, 1, reason: 'single-flight: only one refresh for N concurrent 401s');
    expect(results.every((r) => r.statusCode == 200), isTrue, reason: 'all retried requests succeed');
    expect(await store.readAccess(), 'new');
  });

  test('refresh failure → onAuthLost called, 401 surfaced', () async {
    final store = TokenStore();
    await store.save(access: 'old', refresh: 'r1');

    // Server never accepts 'old' — the request 401s and refresh (which
    // fails below) never gets a chance to make it valid.
    final stub = _StubAdapter('never-matches');
    final dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.httpClientAdapter = stub;

    bool onAuthLostCalled = false;
    Future<Result<RefreshResponse>> refresh(String r) async {
      return const Failure(FailureKind.unauthorized, 'refresh token invalid');
    }

    dio.interceptors.add(AuthInterceptor(
      store,
      refresh,
      () => onAuthLostCalled = true,
      dio,
    ));

    final response = await dio.get<Map<String, dynamic>>('/me/a');

    expect(response.statusCode, 401);
    expect(onAuthLostCalled, isTrue);
    expect(await store.readAccess(), isNull);
    expect(await store.readRefresh(), isNull);
  });

  test('requests to /auth/* are not given a Bearer header and do not trigger refresh on 401', () async {
    final store = TokenStore();
    await store.save(access: 'old', refresh: 'r1');

    final stub = _StubAdapter('old');
    final dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.httpClientAdapter = stub;

    int refreshCalls = 0;
    Future<Result<RefreshResponse>> refresh(String r) async {
      refreshCalls++;
      return const Ok(RefreshResponse(accessToken: 'new', refreshToken: 'r2'));
    }

    dio.interceptors.add(AuthInterceptor(store, refresh, () {}, dio));

    // onRequest skips attaching a Bearer header for any /auth/* path, so this
    // 401s regardless of currentToken; onResponse must also skip refreshing
    // for /auth/* paths so this doesn't loop.
    final response = await dio.get<Map<String, dynamic>>('/auth/whoami');

    expect(response.statusCode, 401);
    expect(refreshCalls, 0);
    expect(stub.requestLog.where((l) => l.contains('/auth/whoami')).length, 1);
  });
}
