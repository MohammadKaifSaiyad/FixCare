import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The PUT-to-R2 seam. Production performs the presigned PUT (or, in local dev,
/// the dev mark-uploaded hook — see [makePhotoPut]); tests inject a fake so the
/// upload queue is exercised without a network. Throws on failure.
typedef PutFn = Future<void> Function({
  required String url,
  required String key,
  required List<int> bytes,
});

/// A failed evidence upload (the R2 PUT or the local-dev mark-uploaded hook).
///
/// Deliberately carries ONLY the HTTP status (null for a transport failure):
/// never the signed url (it embeds a live credential), the object key, the
/// bytes, or the underlying DioException (whose requestOptions hold the url).
/// Safe to surface or log.
class PhotoUploadException implements Exception {
  const PhotoUploadException([this.statusCode]);

  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? 'PhotoUploadException(transport)' : 'PhotoUploadException(status: $statusCode)';
}

/// The Dio used for the presigned PUT to R2. A BARE client: no baseUrl and NO
/// interceptors, so it can never attach the app's bearer token. This is
/// load-bearing — sending the JWT to R2 both leaks it to a third party and
/// makes R2/S3 reject the request (a presigned request may carry only one auth
/// mechanism), which would block every photo gate. Never route the PUT through
/// the app's authenticated `dioProvider`.
final photoUploadDioProvider = Provider<Dio>((ref) => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 15),
      // Status is checked explicitly in [makePhotoPut] (throws unless 2xx).
      validateStatus: (_) => true,
    )));

/// Production PUT seam.
///
/// - Real presigned R2 url -> PUT the bytes through [uploadDio] (bare, no
///   Authorization), Content-Type image/jpeg + the exact Content-Length (both
///   are signed into the url, so they must match).
/// - Local-dev fake (host `dev-r2.local`) -> there is no object store locally,
///   so tell the backend the object "exists" via the dev-only, authenticated
///   `POST /dev/photos/mark-uploaded {key}` through [apiDio] (ADR-0007). The
///   backend never registers that route in production.
///
/// Throws [PhotoUploadException] unless the response is 2xx — both clients are
/// configured never to throw on status, so without this a rejected upload would
/// silently proceed to confirm.
PutFn makePhotoPut({required Dio apiDio, required Dio uploadDio}) => ({
      required String url,
      required String key,
      required List<int> bytes,
    }) async {
      final Response<dynamic> res;
      try {
        if (Uri.tryParse(url)?.host == 'dev-r2.local') {
          res = await apiDio.post<dynamic>('/dev/photos/mark-uploaded', data: {'key': key});
        } else {
          res = await uploadDio.put<dynamic>(
            url,
            data: Stream<List<int>>.fromIterable([bytes]),
            options: Options(
              headers: {'Content-Length': bytes.length},
              contentType: 'image/jpeg',
            ),
          );
        }
      } on DioException {
        // Re-thrown WITHOUT the DioException: its requestOptions carry the
        // signed url.
        throw const PhotoUploadException();
      }
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) throw PhotoUploadException(status);
    };
