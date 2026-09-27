import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/network/auth_interceptor.dart';
import 'package:fixcare_technician/core/network/dio_client.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/storage/token_store.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';

/// Real-transport tests for the photo PUT seam. Every other photo test injects
/// a fake `PutFn`, which is exactly how the JWT-to-R2 leak went unnoticed
/// (mocked-transport false confidence). Here the REAL dio pipeline runs —
/// including the REAL [AuthInterceptor] on the API dio — and only the socket
/// is stubbed, so the recorded [RequestOptions] are what would hit the wire.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.status = 200});

  /// Status every response returns.
  int status;

  /// When true, the "socket" fails instead of responding (connection error).
  bool fail = false;

  final List<RequestOptions> requests = [];
  final List<List<int>> bodies = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = requestStream == null ? const <Uint8List>[] : await requestStream.toList();
    bodies.add([for (final c in chunks) ...c]);
    if (fail) throw const SocketException('connection refused');
    return ResponseBody.fromString('', status);
  }
}

const _accessToken = 'access-tok-123';
const _r2Url = 'https://acct.r2.cloudflarestorage.com/fixcare/jobs/b1/REPAIR_OLD_PART-abc.jpg'
    '?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Signature=deadbeef';
const _devUrl = 'https://dev-r2.local/upload/jobs%2Fb1%2FREPAIR_OLD_PART-abc.jpg';
const _key = 'jobs/b1/REPAIR_OLD_PART-abc.jpg';
final _bytes = List<int>.generate(1234, (i) => i % 256);

/// The authenticated API dio, built the way dioProvider builds it: a baseUrl,
/// validateStatus-never-throws, and the REAL AuthInterceptor reading a real
/// TokenStore (backed by the mocked secure-storage channel).
Dio _apiDio(_RecordingAdapter adapter, TokenStore store) {
  final dio = Dio(BaseOptions(baseUrl: 'http://api.test', validateStatus: (_) => true))
    ..httpClientAdapter = adapter;
  dio.interceptors.add(AuthInterceptor(
    store,
    (_) async => const Failure(FailureKind.unauthorized, 'no refresh in this test'),
    () {},
    dio,
  ));
  return dio;
}

/// A bare upload dio, configured like photoUploadDioProvider (no baseUrl, no
/// interceptors), with the stub socket.
Dio _uploadDio(_RecordingAdapter adapter) =>
    Dio(BaseOptions(validateStatus: (_) => true))..httpClientAdapter = adapter;

bool _hasAuthHeader(RequestOptions o) =>
    o.headers.keys.any((k) => k.toLowerCase() == 'authorization');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secureStorageBacking = <String, String>{};
  late TokenStore store;

  setUp(() async {
    secureStorageBacking.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
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
    store = TokenStore();
    await store.save(access: _accessToken, refresh: 'refresh-tok');
  });

  group('makePhotoPut — real R2 presigned URL', () {
    test('PUTs the exact bytes to the exact url via the bare dio: NO Authorization, image/jpeg, Content-Length',
        () async {
      final apiStub = _RecordingAdapter();
      final uploadStub = _RecordingAdapter();
      final put = makePhotoPut(apiDio: _apiDio(apiStub, store), uploadDio: _uploadDio(uploadStub));

      await put(url: _r2Url, key: _key, bytes: _bytes);

      expect(apiStub.requests, isEmpty, reason: 'the R2 PUT must never go through the authenticated API dio');
      expect(uploadStub.requests, hasLength(1));
      final req = uploadStub.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.toString(), _r2Url);
      expect(_hasAuthHeader(req), isFalse, reason: 'the JWT must never be sent to R2');
      expect(req.contentType, 'image/jpeg');
      expect('${req.headers['content-length']}', '${_bytes.length}');
      expect(uploadStub.bodies.single, _bytes);
    });

    test('R2 403 -> throws (never proceeds to confirm on a rejected upload)', () async {
      final uploadStub = _RecordingAdapter(status: 403);
      final put = makePhotoPut(apiDio: _apiDio(_RecordingAdapter(), store), uploadDio: _uploadDio(uploadStub));

      await expectLater(
        put(url: _r2Url, key: _key, bytes: _bytes),
        throwsA(isA<PhotoUploadException>()),
      );
    });

    test('a non-2xx error carries no signed url or key in its text', () async {
      final put = makePhotoPut(
        apiDio: _apiDio(_RecordingAdapter(), store),
        uploadDio: _uploadDio(_RecordingAdapter(status: 500)),
      );

      Object? caught;
      try {
        await put(url: _r2Url, key: _key, bytes: _bytes);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PhotoUploadException>());
      final text = caught.toString();
      expect(text, isNot(contains('r2.cloudflarestorage.com')));
      expect(text, isNot(contains('X-Amz')));
      expect(text, isNot(contains(_key)));
    });

    test('a connection error -> PhotoUploadException with no url/key (the DioException is not propagated)',
        () async {
      final uploadStub = _RecordingAdapter()..fail = true;
      final put = makePhotoPut(apiDio: _apiDio(_RecordingAdapter(), store), uploadDio: _uploadDio(uploadStub));

      Object? caught;
      try {
        await put(url: _r2Url, key: _key, bytes: _bytes);
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<PhotoUploadException>());
      expect(caught, isNot(isA<DioException>()));
      final text = caught.toString();
      expect(text, isNot(contains('r2.cloudflarestorage.com')));
      expect(text, isNot(contains(_key)));
    });
  });

  group('makePhotoPut — local-dev fake (dev-r2.local)', () {
    test('POSTs {key} to /dev/photos/mark-uploaded through the API dio WITH the bearer; nothing to uploadDio',
        () async {
      final apiStub = _RecordingAdapter(status: 204);
      final uploadStub = _RecordingAdapter();
      final put = makePhotoPut(apiDio: _apiDio(apiStub, store), uploadDio: _uploadDio(uploadStub));

      await put(url: _devUrl, key: _key, bytes: _bytes);

      expect(uploadStub.requests, isEmpty);
      expect(apiStub.requests, hasLength(1));
      final req = apiStub.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/dev/photos/mark-uploaded');
      expect(req.data, {'key': _key});
      expect(req.headers['Authorization'], 'Bearer $_accessToken');
    });

    test('dev hook 404 (route absent) -> throws', () async {
      final put = makePhotoPut(
        apiDio: _apiDio(_RecordingAdapter(status: 404), store),
        uploadDio: _uploadDio(_RecordingAdapter()),
      );

      await expectLater(
        put(url: _devUrl, key: _key, bytes: _bytes),
        throwsA(isA<PhotoUploadException>()),
      );
    });

    test('a look-alike url that is not the dev-r2.local HOST takes the real PUT path', () async {
      final apiStub = _RecordingAdapter(status: 204);
      final uploadStub = _RecordingAdapter();
      final put = makePhotoPut(apiDio: _apiDio(apiStub, store), uploadDio: _uploadDio(uploadStub));

      await put(url: 'https://acct.r2.cloudflarestorage.com/dev-r2.local/x.jpg', key: _key, bytes: _bytes);

      expect(apiStub.requests, isEmpty);
      expect(uploadStub.requests.single.method, 'PUT');
    });
  });

  group('providers', () {
    test('photoUploadDioProvider is a bare Dio: no baseUrl, no AuthInterceptor', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(photoUploadDioProvider);

      expect(dio.options.baseUrl, isEmpty);
      expect(dio.interceptors.whereType<AuthInterceptor>(), isEmpty);
      expect(dio, isNot(same(container.read(dioProvider))));
    });

    test('photoUploadQueueProvider sends the R2 PUT through photoUploadDioProvider, not dioProvider', () async {
      final apiStub = _RecordingAdapter();
      final uploadStub = _RecordingAdapter();
      final container = ProviderContainer(overrides: [
        dioProvider.overrideWithValue(_apiDio(apiStub, store)),
        photoUploadDioProvider.overrideWithValue(_uploadDio(uploadStub)),
        technicianJobRepositoryProvider.overrideWithValue(_SignConfirmRepo()),
      ]);
      addTearDown(container.dispose);

      final queue = container.read(photoUploadQueueProvider);
      await queue.enqueue(
        bookingId: 'b1',
        kind: 'REPAIR_OLD_PART',
        photo: CapturedPhoto(bytes: _bytes, capturedAt: '2026-09-20T09:30:00.000Z'),
      );

      expect(apiStub.requests, isEmpty);
      expect(uploadStub.requests, hasLength(1));
      expect(_hasAuthHeader(uploadStub.requests.single), isFalse);
      expect(queue.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.done);
    });
  });
}

/// Sign returns a real-looking R2 url; confirm succeeds. No dio involved.
class _SignConfirmRepo extends TechnicianJobRepository {
  _SignConfirmRepo() : super(Dio());

  @override
  Future<Result<PhotoSignDto>> signPhoto(String id, {required String kind, required int contentLengthBytes}) async =>
      const Ok(PhotoSignDto(url: _r2Url, key: _key, expiresAt: '2026-09-21T09:30:00.000Z'));

  @override
  Future<Result<PhotoConfirmDto>> confirmPhoto(String id,
          {required String kind,
          required String key,
          required String capturedAt,
          double? geotagLat,
          double? geotagLng}) async =>
      Ok(PhotoConfirmDto(id: 'p1', kind: kind, capturedAt: capturedAt));
}
