import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/photo_capture.dart';

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

  @override
  Future<Result<PhotoSignDto>> signPhoto(String id,
      {required String kind, required int contentLengthBytes}) async {
    signCalls.add((id: id, kind: kind, contentLengthBytes: contentLengthBytes));
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
  // true = succeed, false = throw (simulate a network/PUT failure); clamps at last.
  List<bool> outcomes = [true];
  int _seq = 0;

  Future<void> call({required String url, required String key, required List<int> bytes}) async {
    calls.add(_PutCall(url, key, bytes.length));
    final ok = outcomes[_seq < outcomes.length ? _seq : outcomes.length - 1];
    _seq++;
    if (!ok) throw Exception('PUT failed');
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

void main() {
  test('enqueue: sign(bytes,kind) -> PUT -> confirm; slot uploading -> done', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final put = _FakePut();
      final q = _queue(repo, put);

      final states = <PhotoSlotState>[];
      q.addListener(() => states.add(q.stateOf('diagnosis_before')));

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
      expect(q.stateOf('diagnosis_before'), PhotoSlotState.done);
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
      expect(q.stateOf('repair_old_removed'), PhotoSlotState.failedRetry);

      // Backoff elapses -> retry.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(put.calls, hasLength(2));
      expect(repo.confirmCalls, hasLength(1));
      expect(q.stateOf('repair_old_removed'), PhotoSlotState.done);
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
      expect(q.stateOf('repair_new_installed'), PhotoSlotState.failedRetry);

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(repo.confirmCalls, hasLength(2));
      expect(q.stateOf('repair_new_installed'), PhotoSlotState.done);
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
      expect(q.stateOf('diagnosis_after'), PhotoSlotState.done);
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
      expect(q.stateOf('diagnosis_before'), PhotoSlotState.done);
    });
  });

  test('unknown slot reads as PhotoSlotState.none', () {
    final repo = _FakeRepo();
    final q = _queue(repo, _FakePut());
    expect(q.stateOf('never_touched'), PhotoSlotState.none);
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
      readLocation: () async => null,
      compress: (bytes) async => bytes,
    );

    final result = await svc.capture();
    expect(result, isNull);
    expect(seenSource, ImageSource.camera);
    expect(seenSource, isNot(ImageSource.gallery));
  });
}
