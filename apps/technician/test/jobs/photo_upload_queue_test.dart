import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/core/theme.dart';
import 'package:fixcare_technician/features/jobs/data/photo_upload_client.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/location_service.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';
import 'package:fixcare_technician/features/jobs/presentation/settings_opener.dart';

/// Records a single PUT/dev-hook invocation the queue made.
class _PutCall {
  _PutCall(this.url, this.key, this.bytes);
  final String url;
  final String key;
  final int bytes;
}

/// A fake repo that records sign/confirm calls and returns scripted outcomes.
/// sign is always Ok (with a settable url); confirm's outcome is a settable
/// queue of Results so a test can fail-then-succeed.
class _FakeRepo extends TechnicianJobRepository {
  _FakeRepo({this.signUrl = 'https://r2.example.com/upload'}) : super(Dio());

  String signUrl;

  // Recorded sign calls.
  final List<({String id, String kind, int contentLengthBytes})> signCalls = [];
  // Recorded confirm calls (raw body so tests assert geotag both-or-neither).
  final List<Map<String, dynamic>> confirmCalls = [];

  int _signSeq = 0;

  /// When set, every sign call returns this Failure instead of a signed url.
  Failure<PhotoSignDto>? signFailure;

  @override
  Future<Result<PhotoSignDto>> signPhoto(String id,
      {required String kind, required int contentLengthBytes}) async {
    signCalls.add((id: id, kind: kind, contentLengthBytes: contentLengthBytes));
    final failure = signFailure;
    if (failure != null) return failure;
    final key = 'key-$kind-${_signSeq++}';
    return Ok(PhotoSignDto(url: signUrl, key: key, expiresAt: '2026-09-20T10:00:00.000Z'));
  }

  // Outcomes dispensed to successive confirmPhoto calls; clamps at the last.
  List<Result<PhotoConfirmDto>> confirmOutcomes = [
    const Ok(PhotoConfirmDto(id: 'p1', kind: 'x', capturedAt: 'x')),
  ];
  int _confirmSeq = 0;

  @override
  Future<Result<PhotoConfirmDto>> confirmPhoto(String id,
      {required String kind,
      required String key,
      required String capturedAt,
      double? geotagLat,
      double? geotagLng}) async {
    final body = <String, dynamic>{'id': id, 'kind': kind, 'key': key, 'capturedAt': capturedAt};
    if (geotagLat != null && geotagLng != null) {
      body['geotagLat'] = geotagLat;
      body['geotagLng'] = geotagLng;
    }
    confirmCalls.add(body);
    final r = confirmOutcomes[
        _confirmSeq < confirmOutcomes.length ? _confirmSeq : confirmOutcomes.length - 1];
    _confirmSeq++;
    return r;
  }
}

/// A fake PUT seam. Records each call and dispenses success/throw per invocation.
class _FakePut {
  final List<_PutCall> calls = [];
  // true = succeed, false = throw [error] (simulate a PUT failure); clamps at last.
  List<bool> outcomes = [true];
  // What a failing PUT throws. Default: an unexpected (unclassified) error.
  Object error = Exception('PUT failed');
  int _seq = 0;

  Future<void> call({required String url, required String key, required List<int> bytes}) async {
    calls.add(_PutCall(url, key, bytes.length));
    final ok = outcomes[_seq < outcomes.length ? _seq : outcomes.length - 1];
    _seq++;
    if (!ok) throw error;
  }
}

CapturedPhoto _photo({double? lat, double? lng, int size = 42}) => CapturedPhoto(
      bytes: List<int>.filled(size, 7),
      capturedAt: '2026-09-20T09:30:00.000Z',
      lat: lat,
      lng: lng,
    );

PhotoUploadQueue _queue(_FakeRepo repo, _FakePut put) => PhotoUploadQueue(
      repo: repo,
      put: put.call,
      // Small deterministic backoff schedule for fake_async.
      backoff: const [Duration(seconds: 2), Duration(seconds: 4)],
    );

Map<String, dynamic> _jobJson({String id = 'b1', List<Map<String, dynamic>> photos = const []}) => {
      'id': id,
      'bookingNumber': 'FC-1',
      'state': 'DISPATCHED',
      'scheduledSlot': '2026-09-20T09:00:00.000Z',
      'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
      'zone': {'name': 'Padra'},
      'visitFeePaise': 9900,
      'laborPaise': 20000,
      'address': {'line1': 'A/27 Umiya Nagar', 'line2': 'Padra', 'landmark': 'HP Gas', 'pincode': '391440'},
      'customer': {'maskedPhone': '••••••8384'},
      'photos': photos,
    };

TechnicianJobDto _jobDto({String id = 'b1', List<Map<String, dynamic>> photos = const []}) =>
    TechnicianJobDto.fromJson(_jobJson(id: id, photos: photos));

void main() {
  test('enqueue: sign(bytes,kind) -> PUT -> confirm; slot uploading -> done', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut();
      final q = _queue(repo, put);

      final states = <PhotoSlotState>[];
      q.addListener(() => states.add(q.stateOf('b1', 'diagnosis_before')));

      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(lat: 22.3, lng: 73.2, size: 100));
      async.flushMicrotasks();

      // sign called once with the (compressed) byte length + kind.
      expect(repo.signCalls, hasLength(1));
      expect(repo.signCalls.single.id, 'b1');
      expect(repo.signCalls.single.kind, 'diagnosis_before');
      expect(repo.signCalls.single.contentLengthBytes, 100);

      // PUT called with the signed url + key + same bytes.
      expect(put.calls, hasLength(1));
      expect(put.calls.single.url, 'https://r2.example.com/upload');
      expect(put.calls.single.bytes, 100);

      // confirm called with kind/key/capturedAt + geotag (both present).
      expect(repo.confirmCalls, hasLength(1));
      final body = repo.confirmCalls.single;
      expect(body['kind'], 'diagnosis_before');
      expect(body['key'], put.calls.single.key);
      expect(body['capturedAt'], '2026-09-20T09:30:00.000Z');
      expect(body['geotagLat'], 22.3);
      expect(body['geotagLng'], 73.2);

      // Slot ended done, and passed through uploading first.
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
      expect(states, contains(PhotoSlotState.uploading));
      expect(states.last, PhotoSlotState.done);
    });
  });

  test('a failing PUT -> failedRetry, then a retry (backoff) succeeds -> done', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut()..outcomes = [false, true]; // first PUT throws, retry succeeds
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'repair_old_removed', photo: _photo(lat: 1, lng: 2));
      async.flushMicrotasks();

      // First attempt failed -> failedRetry, no confirm yet.
      expect(put.calls, hasLength(1));
      expect(repo.confirmCalls, isEmpty);
      expect(q.stateOf('b1', 'repair_old_removed'), PhotoSlotState.failedRetry);

      // Backoff elapses -> retry.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(put.calls, hasLength(2));
      expect(repo.confirmCalls, hasLength(1));
      expect(q.stateOf('b1', 'repair_old_removed'), PhotoSlotState.done);
    });
  });

  test('a failing confirm also retries and eventually succeeds -> done', () {
    fakeAsync((async) {
      final repo = _FakeRepo()
        ..confirmOutcomes = [
          const Failure(FailureKind.network, 'blip'),
          const Ok(PhotoConfirmDto(id: 'p1', kind: 'x', capturedAt: 'x')),
        ];
      final put = _FakePut()..outcomes = [true, true];
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'repair_new_installed', photo: _photo(lat: 1, lng: 2));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'repair_new_installed'), PhotoSlotState.failedRetry);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(repo.confirmCalls, hasLength(2));
      expect(q.stateOf('b1', 'repair_new_installed'), PhotoSlotState.done);
    });
  });

  test('a photo with no lat/lng -> confirm omits geotag keys entirely', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut();
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'diagnosis_after', photo: _photo()); // no lat/lng
      async.flushMicrotasks();

      expect(repo.confirmCalls, hasLength(1));
      final body = repo.confirmCalls.single;
      expect(body.containsKey('geotagLat'), isFalse);
      expect(body.containsKey('geotagLng'), isFalse);
      expect(q.stateOf('b1', 'diagnosis_after'), PhotoSlotState.done);
    });
  });

  test('dev-r2.local url -> calls the dev mark-uploaded hook instead of a real PUT', () {
    fakeAsync((async) {
      final repo = _FakeRepo(signUrl: 'https://dev-r2.local/bucket/obj');
      // Route both real-PUT and dev-hook through the same seam; the queue decides
      // which path, so the test asserts the seam saw the dev url.
      final put = _FakePut();
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(lat: 1, lng: 2));
      async.flushMicrotasks();

      // The dev branch still flows through the injected seam; url is the dev one.
      expect(put.calls, hasLength(1));
      expect(put.calls.single.url, contains('dev-r2.local'));
      expect(repo.confirmCalls, hasLength(1));
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
    });
  });

  test('unknown slot reads as PhotoSlotState.none', () {
    final repo = _FakeRepo();
    final q = _queue(repo, _FakePut());
    expect(q.stateOf('b1', 'never_touched'), PhotoSlotState.none);
  });

  group('hasGeotagOf', () {
    test('true after a geotagged capture; false after a non-geotagged one', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());

        q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(lat: 22.3, lng: 73.2));
        async.flushMicrotasks();
        expect(q.hasGeotagOf('b1', 'diagnosis_before'), isTrue);

        q.enqueue(bookingId: 'b1', kind: 'diagnosis_after', photo: _photo()); // no lat/lng
        async.flushMicrotasks();
        expect(q.hasGeotagOf('b1', 'diagnosis_after'), isFalse);
      });
    });

    test('null for a slot nothing has been enqueued for this session', () {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());
      expect(q.hasGeotagOf('b1', 'never_touched'), isNull);
    });

    test('recorded even when the upload later fails (geotag is read at enqueue time)', () {
      fakeAsync((async) {
        final repo = _FakeRepo()..confirmOutcomes = [const Failure(FailureKind.unknown, 'no')];
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo()); // no lat/lng
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);
        expect(q.hasGeotagOf('b1', 'REPAIR_OLD_PART'), isFalse);
      });
    });
  });

  test('the concrete ImagePickerCameraService is camera-only (never gallery)', () async {
    // Guard the fraud-critical invariant: the real service must only ever ask the
    // picker for ImageSource.camera. We inject a fake picker seam and assert the
    // source it receives — a gallery source would fail this test.
    ImageSource? seenSource;
    final svc = ImagePickerCameraService(
      pickImage: ({required ImageSource source}) async {
        seenSource = source;
        return null; // user cancelled — we only care about the source it asked for
      },
      // location + compress are never reached when pick returns null.
      location: _NoFixLocation(),
      compress: (bytes) async => bytes,
    );

    final result = await svc.capture();
    expect(result, isNull);
    expect(seenSource, ImageSource.camera);
    expect(seenSource, isNot(ImageSource.gallery));
  });

  test('cross-job isolation: the same kind for a different bookingId reads none', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut();
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo());
      async.flushMicrotasks();

      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
      expect(q.stateOf('b2', 'diagnosis_before'), PhotoSlotState.none);
    });
  });

  test('retake after done re-enqueues: a second sign+confirm with the new photo', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut();
      final q = _queue(repo, put);

      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(size: 10));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
      expect(repo.signCalls, hasLength(1));
      expect(repo.confirmCalls, hasLength(1));

      // Retake with a different photo — must NOT be dropped even though the
      // slot is already `done`.
      q.enqueue(
        bookingId: 'b1',
        kind: 'diagnosis_before',
        photo: CapturedPhoto(
          bytes: List<int>.filled(20, 9),
          capturedAt: '2026-09-20T09:45:00.000Z',
        ),
      );
      async.flushMicrotasks();

      expect(repo.signCalls, hasLength(2));
      expect(repo.confirmCalls, hasLength(2));
      expect(repo.signCalls.last.contentLengthBytes, 20);
      expect(repo.confirmCalls.last['capturedAt'], '2026-09-20T09:45:00.000Z');
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
    });
  });

  test('stale retry guard: a retake supersedes a still-pending backoff retry for the old capture', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      // capture #1's PUT fails, capture #2's PUT fails, capture #2's retry PUT succeeds.
      final put = _FakePut()..outcomes = [false, false, true];
      final q = _queue(repo, put); // backoff [2s, 4s]

      // Capture #1 fails immediately -> failedRetry, retry scheduled ~2s out.
      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(size: 10));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.failedRetry);
      expect(put.calls, hasLength(1));

      // 1s later (before capture #1's retry fires), retake with capture #2,
      // which also fails -> its own retry scheduled ~2s out from now.
      async.elapse(const Duration(seconds: 1));
      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(size: 20));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.failedRetry);
      expect(put.calls, hasLength(2));

      // Advance past BOTH scheduled backoffs.
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      // Capture #1's stale retry did nothing; only capture #2's bytes ever
      // reappear, and its retry succeeded.
      expect(put.calls.map((c) => c.bytes).toList(), [10, 20, 20]);
      expect(repo.confirmCalls, hasLength(1));
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
    });
  });

  test('mid-flight stale attempt (awaiting PUT) does not overwrite a newer retake', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final putGate1 = Completer<void>();
      final calls = <String>[];
      Future<void> gatedPut({required String url, required String key, required List<int> bytes}) async {
        calls.add(key);
        if (key == 'key-diagnosis_before-0') {
          // Gate ONLY capture #1's PUT so it stays mid-flight.
          await putGate1.future;
        }
      }
      final q = PhotoUploadQueue(repo: repo, put: gatedPut, backoff: const [Duration(seconds: 2)]);

      // Capture #1: reaches PUT and blocks there (mid-flight).
      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(size: 10));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.uploading);
      expect(calls, ['key-diagnosis_before-0']);

      // Retake while capture #1 is still mid-flight: runs sign -> PUT (resolves
      // immediately) -> confirm -> done.
      q.enqueue(bookingId: 'b1', kind: 'diagnosis_before', photo: _photo(size: 20));
      async.flushMicrotasks();
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
      expect(repo.confirmCalls, hasLength(1));
      expect(repo.confirmCalls.single['key'], 'key-diagnosis_before-1');

      // Now let capture #1's PUT resolve. It must detect it is stale and do
      // nothing — no confirm call, no state overwrite.
      putGate1.complete();
      async.flushMicrotasks();

      expect(repo.confirmCalls, hasLength(1));
      expect(q.stateOf('b1', 'diagnosis_before'), PhotoSlotState.done);
    });
  });

  group('failure classification (terminal vs transient)', () {
    const windowMsg = 'Photos can only be confirmed during their capture window — the booking has moved on';

    test('confirm 409 -> failed with the backend message verbatim; no further sign calls', () {
      fakeAsync((async) {
        final repo = _FakeRepo()..confirmOutcomes = [const Failure(FailureKind.unknown, windowMsg)];
        final put = _FakePut();
        final q = _queue(repo, put);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();

        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);
        expect(q.failureOf('b1', 'REPAIR_OLD_PART'), windowMsg);

        async.elapse(const Duration(minutes: 5));
        expect(repo.signCalls, hasLength(1), reason: 'a terminal failure is never retried');
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('sign Failure(network) [as mapped from a 408] -> failedRetry, not failed', () {
      fakeAsync((async) {
        final repo = _FakeRepo()..signFailure = const Failure(FailureKind.network, 'Request timed out');
        final put = _FakePut();
        final q = _queue(repo, put);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();

        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failedRetry);
        expect(q.failureOf('b1', 'REPAIR_OLD_PART'), isNull, reason: 'transient failures carry no message');
        expect(put.calls, isEmpty, reason: 'sign failed before any PUT attempt');

        q.dispose();
      });
    });

    for (final kind in const [FailureKind.unauthorized, FailureKind.forbidden, FailureKind.notFound, FailureKind.validation, FailureKind.unknown]) {
      test('sign Failure($kind) -> failed with the message, PUT never attempted', () {
        fakeAsync((async) {
          final repo = _FakeRepo()..signFailure = Failure(kind, 'sign said no ($kind)');
          final put = _FakePut();
          final q = _queue(repo, put);

          q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));

          expect(q.stateOf('b1', 'DIAGNOSIS_OVERVIEW'), PhotoSlotState.failed);
          expect(q.failureOf('b1', 'DIAGNOSIS_OVERVIEW'), 'sign said no ($kind)');
          expect(repo.signCalls, hasLength(1));
          expect(put.calls, isEmpty);
        });
      });
    }

    for (final kind in const [FailureKind.network, FailureKind.server, FailureKind.rateLimited]) {
      test('confirm Failure($kind) -> failedRetry (no message), then the retry succeeds -> done', () {
        fakeAsync((async) {
          final repo = _FakeRepo()
            ..confirmOutcomes = [
              Failure(kind, 'transient'),
              const Ok(PhotoConfirmDto(id: 'p1', kind: 'x', capturedAt: 'x')),
            ];
          final q = _queue(repo, _FakePut());

          q.enqueue(bookingId: 'b1', kind: 'REPAIR_INSTALLED', photo: _photo());
          async.flushMicrotasks();
          expect(q.stateOf('b1', 'REPAIR_INSTALLED'), PhotoSlotState.failedRetry);
          expect(q.failureOf('b1', 'REPAIR_INSTALLED'), isNull);

          async.elapse(const Duration(seconds: 2));
          expect(repo.signCalls, hasLength(2));
          expect(q.stateOf('b1', 'REPAIR_INSTALLED'), PhotoSlotState.done);
        });
      });
    }

    test('6 consecutive transient failures -> failed with the connection message; retries stop', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final put = _FakePut()
          ..outcomes = [false]
          ..error = const PhotoUploadException(); // transport failure, every time
        final q = _queue(repo, put);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 10));

        expect(put.calls, hasLength(6));
        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);
        expect(q.failureOf('b1', 'REPAIR_OLD_PART'), 'Upload keeps failing. Check your connection, then retake.');
        expect(async.pendingTimers, isEmpty);
      });
    });

    for (final status in const [400, 403, 404, 413]) {
      test('PUT $status -> failed with the generic retake message (no url/key/status)', () {
        fakeAsync((async) {
          final repo = _FakeRepo();
          final put = _FakePut()
            ..outcomes = [false]
            ..error = PhotoUploadException(status);
          final q = _queue(repo, put);

          q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
          async.flushMicrotasks();
          async.elapse(const Duration(minutes: 5));

          expect(put.calls, hasLength(1));
          expect(repo.confirmCalls, isEmpty);
          expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);
          expect(q.failureOf('b1', 'REPAIR_OLD_PART'), "Couldn't upload the photo. Retake to try again.");
        });
      });
    }

    for (final status in const [null, 500, 503, 408, 429]) {
      test('PUT ${status ?? 'transport error'} -> failedRetry, then retried', () {
        fakeAsync((async) {
          final repo = _FakeRepo();
          final put = _FakePut()
            ..outcomes = [false, true]
            ..error = PhotoUploadException(status);
          final q = _queue(repo, put);

          q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
          async.flushMicrotasks();
          expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failedRetry);

          async.elapse(const Duration(seconds: 2));
          expect(put.calls, hasLength(2));
          expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.done);
        });
      });
    }

    test('retake from failed restarts the slot (and clears the message)', () {
      fakeAsync((async) {
        final repo = _FakeRepo()
          ..confirmOutcomes = [
            const Failure(FailureKind.unknown, windowMsg),
            const Ok(PhotoConfirmDto(id: 'p1', kind: 'x', capturedAt: 'x')),
          ];
        final q = _queue(repo, _FakePut());

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo(size: 50));
        async.flushMicrotasks();

        expect(repo.signCalls, hasLength(2));
        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.done);
        expect(q.failureOf('b1', 'REPAIR_OLD_PART'), isNull);
      });
    });

    test('a retake cancels the pending retry timer of the old capture', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final put = _FakePut()..outcomes = [false, true];
        final q = _queue(repo, put);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo(size: 10));
        async.flushMicrotasks();
        expect(async.pendingTimers, hasLength(1));

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo(size: 20));
        async.flushMicrotasks();

        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.done);
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('dispose() cancels a pending retry: no further calls, no notify', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final put = _FakePut()..outcomes = [false, true];
        final q = _queue(repo, put);
        var notifications = 0;
        q.addListener(() => notifications++);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failedRetry);
        final notifiedBefore = notifications;

        q.dispose();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(minutes: 5));

        expect(put.calls, hasLength(1));
        expect(repo.signCalls, hasLength(1));
        expect(notifications, notifiedBefore);
      });
    });

    test('dispose() mid-flight: the in-flight attempt stops without notifying', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final gate = Completer<void>();
        final q = PhotoUploadQueue(
          repo: repo,
          put: ({required url, required key, required bytes}) => gate.future,
        );
        var notifications = 0;
        q.addListener(() => notifications++);

        q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
        async.flushMicrotasks();
        final notifiedBefore = notifications;

        q.dispose();
        gate.complete();
        async.flushMicrotasks();

        expect(repo.confirmCalls, isEmpty);
        expect(notifications, notifiedBefore);
      });
    });
  });

  group('photosReady', () {
    test('all requested kinds done in the queue -> true', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());
        async.flushMicrotasks();

        final job = _jobDto();
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']), isTrue);
      });
    });

    test('one kind only on the server + the other done in queue -> true', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());
        async.flushMicrotasks();

        final job = _jobDto(photos: [
          {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
        ]);
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']), isTrue);
      });
    });

    test('one kind missing everywhere -> false', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_CLOSEUP', photo: _photo());
        async.flushMicrotasks();

        final job = _jobDto();
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']), isFalse);
      });
    });

    test('queue done for a DIFFERENT booking id does not count -> false', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b2', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        async.flushMicrotasks();

        final job = _jobDto(id: 'b1');
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW']), isFalse);
      });
    });

    test('empty kinds list -> true', () {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());
      final job = _jobDto();
      expect(photosReady(q, job, const []), isTrue);
    });

    final serverOverview = [
      {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T10:00:00.000Z', 'url': 'https://x'},
    ];

    test('server photo + a retake still UPLOADING -> false (the old photo does not count)', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final gate = Completer<void>();
        final q = PhotoUploadQueue(repo: repo, put: ({required url, required key, required bytes}) => gate.future);
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'DIAGNOSIS_OVERVIEW'), PhotoSlotState.uploading);

        expect(photosReady(q, _jobDto(photos: serverOverview), const ['DIAGNOSIS_OVERVIEW']), isFalse);
        gate.complete();
        async.flushMicrotasks();
      });
    });

    test('server photo + a retake in FAILED_RETRY -> false', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut()..outcomes = [false]);
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'DIAGNOSIS_OVERVIEW'), PhotoSlotState.failedRetry);

        expect(photosReady(q, _jobDto(photos: serverOverview), const ['DIAGNOSIS_OVERVIEW']), isFalse);
        q.dispose();
      });
    });

    test('server photo + a retake that FAILED -> false', () {
      fakeAsync((async) {
        final repo = _FakeRepo()..confirmOutcomes = [const Failure(FailureKind.unknown, 'no')];
        final q = _queue(repo, _FakePut());
        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'DIAGNOSIS_OVERVIEW'), PhotoSlotState.failed);

        expect(photosReady(q, _jobDto(photos: serverOverview), const ['DIAGNOSIS_OVERVIEW']), isFalse);
      });
    });

    test('server photo + queue none -> true; server photo + queue done -> true', () {
      fakeAsync((async) {
        final repo = _FakeRepo();
        final q = _queue(repo, _FakePut());
        final job = _jobDto(photos: serverOverview);
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW']), isTrue);

        q.enqueue(bookingId: 'b1', kind: 'DIAGNOSIS_OVERVIEW', photo: _photo());
        async.flushMicrotasks();
        expect(q.stateOf('b1', 'DIAGNOSIS_OVERVIEW'), PhotoSlotState.done);
        expect(photosReady(q, job, const ['DIAGNOSIS_OVERVIEW']), isTrue);
      });
    });
  });

  group('PhotoSlot widget', () {
    testWidgets('serverHasPhoto: true with an empty queue shows Uploaded + Retake', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoUploadQueueProvider.overrideWithValue(q)],
          child: const MaterialApp(
            home: Scaffold(
              body: PhotoSlot(
                bookingId: 'b1',
                kind: 'diagnosis_before',
                label: 'Overview',
                serverHasPhoto: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
    });

    testWidgets('serverHasPhoto: false with an empty queue shows Not captured + Capture', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoUploadQueueProvider.overrideWithValue(q)],
          child: const MaterialApp(
            home: Scaffold(
              body: PhotoSlot(
                bookingId: 'b1',
                kind: 'diagnosis_before',
                label: 'Overview',
              ),
            ),
          ),
        ),
      );

      expect(find.text('Not captured'), findsOneWidget);
      expect(find.text('Capture'), findsOneWidget);
    });

    testWidgets('a done slot with no geotag shows "Uploaded · no location" + the precise-location hint',
        (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());
      await q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo()); // no lat/lng

      await _pumpSlot(tester, queue: q, camera: _FakeCamera());

      expect(find.text('Uploaded · no location'), findsOneWidget);
      expect(find.text('Turn on precise location so future photos are location-tagged.'), findsOneWidget);
    });

    testWidgets('a done slot WITH a geotag shows plain "Uploaded", no hint', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());
      await q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo(lat: 1, lng: 2));

      await _pumpSlot(tester, queue: q, camera: _FakeCamera());

      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.text('Uploaded · no location'), findsNothing);
      expect(find.text('Turn on precise location so future photos are location-tagged.'), findsNothing);
    });

    testWidgets('a server-only photo (no queue entry) shows plain "Uploaded", no hint', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [photoUploadQueueProvider.overrideWithValue(q)],
          child: const MaterialApp(
            home: Scaffold(
              body: PhotoSlot(
                bookingId: 'b1',
                kind: 'diagnosis_before',
                label: 'Overview',
                serverHasPhoto: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Uploaded'), findsOneWidget);
      expect(find.text('Turn on precise location so future photos are location-tagged.'), findsNothing);
    });

    testWidgets('a FAILED slot shows the stored message in errorText + Retake', (tester) async {
      const msg = 'Photos can only be confirmed during their capture window — the booking has moved on';
      final repo = _FakeRepo()..confirmOutcomes = [const Failure(FailureKind.unknown, msg)];
      final q = _queue(repo, _FakePut());
      await q.enqueue(bookingId: 'b1', kind: 'REPAIR_OLD_PART', photo: _photo());
      expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.failed);

      await _pumpSlot(tester, queue: q, camera: _FakeCamera());

      expect(find.text(msg), findsOneWidget);
      expect(tester.widget<Text>(find.text(msg)).style?.color, FixCareColors.errorText);
      expect(find.text('Retake'), findsOneWidget);
    });
  });

  group('PhotoSlot capture', () {
    testWidgets('Capture enqueues the photo for the right (bookingId, kind) and ends Uploaded', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());
      final camera = _FakeCamera(photo: _photo(lat: 1, lng: 2, size: 77));

      await _pumpSlot(tester, queue: q, camera: camera);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(camera.calls, 1);
      expect(repo.signCalls, hasLength(1));
      expect(repo.signCalls.single.id, 'b1');
      expect(repo.signCalls.single.kind, 'REPAIR_OLD_PART');
      expect(repo.signCalls.single.contentLengthBytes, 77);
      expect(q.stateOf('b1', 'REPAIR_OLD_PART'), PhotoSlotState.done);
      expect(find.text('Uploaded'), findsOneWidget);
    });

    testWidgets('a cancelled capture enqueues nothing', (tester) async {
      final repo = _FakeRepo();
      final q = _queue(repo, _FakePut());

      await _pumpSlot(tester, queue: q, camera: _FakeCamera());
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(repo.signCalls, isEmpty);
      expect(find.text('Not captured'), findsOneWidget);
    });

    testWidgets('camera_access_denied -> inline message + open-settings button that opens app settings',
        (tester) async {
      final opener = _FakeSettingsOpener();
      final camera = _FakeCamera(error: PlatformException(code: 'camera_access_denied'));

      await _pumpSlot(tester, queue: _queue(_FakeRepo(), _FakePut()), camera: camera, opener: opener);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(find.text('Camera access is off. Allow it in Settings to take repair photos.'), findsOneWidget);
      final openSettings = find.byKey(const Key('openSettings_REPAIR_OLD_PART'));
      expect(openSettings, findsOneWidget);

      await tester.tap(openSettings);
      await tester.pump();
      expect(opener.appSettingsCalls, 1);
      expect(opener.locationSettingsCalls, 0);
    });

    testWidgets('any other capture error -> "Couldn\'t take the photo. Try again." (no settings button)',
        (tester) async {
      final camera = _FakeCamera(error: PlatformException(code: 'no_available_camera'));

      await _pumpSlot(tester, queue: _queue(_FakeRepo(), _FakePut()), camera: camera);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't take the photo. Try again."), findsOneWidget);
      expect(find.byKey(const Key('openSettings_REPAIR_OLD_PART')), findsNothing);
      // The button is usable again after the failure.
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Capture')).onPressed, isNotNull);
    });

    testWidgets('a non-platform throw (e.g. compression) also shows the retry message', (tester) async {
      final camera = _FakeCamera(error: StateError('compress blew up'));

      await _pumpSlot(tester, queue: _queue(_FakeRepo(), _FakePut()), camera: camera);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't take the photo. Try again."), findsOneWidget);
    });

    testWidgets('the button is disabled while the camera is open (no double launch)', (tester) async {
      final gate = Completer<CapturedPhoto?>();
      final camera = _FakeCamera(gate: gate);

      await _pumpSlot(tester, queue: _queue(_FakeRepo(), _FakePut()), camera: camera);
      await tester.tap(find.text('Capture'));
      await tester.pump();

      final button = find.widgetWithText(TextButton, 'Capture');
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await tester.tap(button);
      await tester.pump();
      expect(camera.calls, 1);

      gate.complete(null); // user cancelled
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    });

    testWidgets('a successful capture after an error clears the error line', (tester) async {
      final camera = _FakeCamera(error: PlatformException(code: 'no_available_camera'));
      final q = _queue(_FakeRepo(), _FakePut());

      await _pumpSlot(tester, queue: q, camera: camera);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't take the photo. Try again."), findsOneWidget);

      camera
        ..error = null
        ..photo = _photo(lat: 1, lng: 2);
      await tester.tap(find.text('Capture'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't take the photo. Try again."), findsNothing);
      expect(find.text('Uploaded'), findsOneWidget);
    });
  });
}

class _NoFixLocation implements LocationService {
  @override
  Future<LocationResult> current() async => const LocationProblem(LocationProblemKind.unavailable);
}

/// A fake camera: returns [photo] (null = user cancelled), throws [error], or —
/// with [gate] — stays "open" until the test completes it.
class _FakeCamera implements CameraService {
  _FakeCamera({this.photo, this.error, this.gate});

  CapturedPhoto? photo;
  Object? error;
  final Completer<CapturedPhoto?>? gate;
  int calls = 0;

  @override
  Future<CapturedPhoto?> capture() async {
    calls++;
    final g = gate;
    if (g != null) return g.future;
    final e = error;
    if (e != null) throw e;
    return photo;
  }
}

class _FakeSettingsOpener implements SettingsOpener {
  int appSettingsCalls = 0;
  int locationSettingsCalls = 0;

  @override
  Future<bool> openAppSettings() async {
    appSettingsCalls++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsCalls++;
    return true;
  }
}

Future<void> _pumpSlot(
  WidgetTester tester, {
  required PhotoUploadQueue queue,
  required CameraService camera,
  SettingsOpener? opener,
}) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoUploadQueueProvider.overrideWithValue(queue),
          cameraServiceProvider.overrideWithValue(camera),
          settingsOpenerProvider.overrideWithValue(opener ?? _FakeSettingsOpener()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PhotoSlot(bookingId: 'b1', kind: 'REPAIR_OLD_PART', label: 'Old part removed'),
          ),
        ),
      ),
    );
