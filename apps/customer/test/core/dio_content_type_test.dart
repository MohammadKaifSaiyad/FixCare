import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/network/dio_client.dart';

/// Regression guard: the app's dio client must NOT stamp
/// `content-type: application/json` on a bodyless request (GET/DELETE).
/// It did once (a global BaseOptions.contentType), which made the backend
/// (Fastify) reject DELETE /me/addresses/:id with FST_ERR_CTP_EMPTY_JSON_BODY
/// ("Body cannot be empty when content-type is set to 'application/json'").
/// POST/PATCH with a Map body must still send application/json (dio's default).
class _CapturingAdapter implements HttpClientAdapter {
  String? lastContentType;
  bool? lastHadData;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastContentType = options.headers[Headers.contentTypeHeader]?.toString();
    lastHadData = options.data != null;
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // dioProvider reads tokenStore; mock the secure-storage channel to null.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  test('bodyless DELETE sends NO application/json content-type; POST with a Map body does', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dio = container.read(dioProvider);
    final stub = _CapturingAdapter();
    dio.httpClientAdapter = stub;

    // DELETE (no body) — must not carry application/json.
    await dio.delete<dynamic>('/me/addresses/a1');
    expect(stub.lastHadData, isFalse);
    expect(stub.lastContentType, isNot(contains('application/json')),
        reason: 'a bodyless DELETE must not declare a json content-type');

    // POST with a Map body — dio's default sets application/json.
    await dio.post<dynamic>('/me/bookings', data: {'x': 1});
    expect(stub.lastContentType, contains('application/json'),
        reason: 'a POST carrying a Map body should send application/json');
  });
}
