import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/technician_job_repository.dart';

// Re-export so callers (and the camera-only guard test) reference ImageSource
// through this file, keeping the plugin dependency contained here.
export 'package:image_picker/image_picker.dart' show ImageSource;

/// Target for the pre-upload compression: evidence photos must be <500KB before
/// upload (low-end devices, Indian data costs). See camera-evidence-capture skill.
const int kPhotoMaxBytes = 500 * 1024;

/// A live-captured evidence photo: the compressed bytes plus the geotag +
/// timestamp read AT capture time (they flow into confirmPhoto so the object is
/// verifiable against the job's arrival GPS). lat/lng are both-or-neither.
@immutable
class CapturedPhoto {
  const CapturedPhoto({
    required this.bytes,
    required this.capturedAt,
    this.lat,
    this.lng,
  });

  final List<int> bytes;

  /// ISO-8601 UTC instant the photo was captured.
  final String capturedAt;

  /// Capture-time geotag. Both present or both null (a partial fix is dropped).
  final double? lat;
  final double? lng;

  bool get hasGeotag => lat != null && lng != null;
}

/// Camera-only capture seam. There is intentionally NO gallery/file-picker
/// entry point on this interface — a gallery import is a documented fraud vector
/// (ADR-0007, fraud-defenses). Only capture() exists.
abstract class CameraService {
  Future<CapturedPhoto?> capture();
}

// --- Injectable seams for the concrete service (device-only in production,
// faked in the camera-only guard test) -------------------------------------

/// Picks a single image. In production this is `ImagePicker().pickImage`.
typedef PickImageFn = Future<XFile?> Function({required ImageSource source});

/// Reads a one-shot geotag at capture time; null if unavailable/denied.
typedef ReadLocationFn = Future<Position?> Function();

/// Compresses raw image bytes to <500KB.
typedef CompressFn = Future<List<int>> Function(List<int> bytes);

/// The real, on-device camera service.
///
/// CAMERA-ONLY: [capture] passes `ImageSource.camera` and NOTHING else — there
/// is no branch, flag, or overload that could pass `ImageSource.gallery`. The
/// picker/location/compress calls are injected so this logic is unit-testable
/// without a real camera (the camera-only guard test drives exactly this path).
class ImagePickerCameraService implements CameraService {
  ImagePickerCameraService({
    PickImageFn? pickImage,
    ReadLocationFn? readLocation,
    CompressFn? compress,
  })  : _pickImage = pickImage ?? _defaultPickImage,
        _readLocation = readLocation ?? _defaultReadLocation,
        _compress = compress ?? _defaultCompress;

  final PickImageFn _pickImage;
  final ReadLocationFn _readLocation;
  final CompressFn _compress;

  @override
  Future<CapturedPhoto?> capture() async {
    // The ONLY source ever passed. Gallery is unreachable by construction.
    final XFile? shot = await _pickImage(source: ImageSource.camera);
    if (shot == null) return null; // user cancelled

    final raw = await shot.readAsBytes();
    final compressed = await _compress(raw);

    // One-shot geotag at capture time (both-or-neither).
    final pos = await _readLocation();

    return CapturedPhoto(
      bytes: compressed,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
  }

  static Future<XFile?> _defaultPickImage({required ImageSource source}) =>
      ImagePicker().pickImage(source: source);

  static Future<List<int>> _defaultCompress(List<int> bytes) async {
    // Progressive quality drop until under the cap (or floor at q=30).
    for (final quality in const [80, 60, 45, 30]) {
      final out = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(bytes),
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (out.length <= kPhotoMaxBytes || quality == 30) return out;
    }
    return bytes;
  }

  static Future<Position?> _defaultReadLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      // Time-boxed: on weak/no GPS fix, getCurrentPosition would otherwise
      // hang indefinitely. A TimeoutException is caught below same as any
      // other location failure -> null (an un-geotagged photo; the backend
      // allows a both-or-neither-null geotag).
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // Location is best-effort — never block capture on a location failure.
      return null;
    }
  }
}

final cameraServiceProvider = Provider<CameraService>((ref) => ImagePickerCameraService());

/// Per-slot upload state the UI observes. `none` = nothing captured for the slot.
enum PhotoSlotState { none, uploading, done, failedRetry }

/// The PUT-to-R2 seam. Production performs the presigned PUT (or, in local dev,
/// the dev mark-uploaded hook — see [_defaultPut]); tests inject a fake so the
/// queue is exercised without a network. Throws on failure.
typedef PutFn = Future<void> Function({
  required String url,
  required String key,
  required List<int> bytes,
});

/// Default backoff between retries. Grows, then clamps at the last entry.
const List<Duration> _defaultBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

/// In-app retrying upload queue (NOT BullMQ — that's backend-only). Per slot it
/// runs sign -> PUT-to-url -> confirm, tracks state (none/uploading/done/
/// failedRetry), and on failure retries with backoff. The UI enqueues and never
/// blocks on the upload; it observes [stateOf] via ChangeNotifier.
///
/// No PII in logs: this class logs nothing (no bytes, no coordinates).
class PhotoUploadQueue extends ChangeNotifier {
  PhotoUploadQueue({
    required this._repo,
    required this._put,
    this._backoff = _defaultBackoff,
  });

  final TechnicianJobRepository _repo;
  final PutFn _put;
  final List<Duration> _backoff;

  // Every internal map is keyed by a composite slot key ("$bookingId|$kind"),
  // never by kind alone — kind-only keys leak state across jobs (job A's
  // DIAGNOSIS_OVERVIEW would read as done on job B's slot of the same kind).
  final Map<String, PhotoSlotState> _states = {};
  // Live attempt count per slot, so a retry uses the next backoff step.
  final Map<String, int> _attempts = {};
  // Bumped on every enqueue. A scheduled/in-flight attempt carries the
  // generation it was started with and aborts (no state write, no further
  // network call) as soon as it no longer matches — this is what makes a
  // retake (which bumps the generation) win over a stale retry or a stale
  // attempt that is already mid-flight when the retake happens.
  final Map<String, int> _generations = {};

  static String _slotKey(String bookingId, String kind) => '$bookingId|$kind';

  /// State of a slot; [PhotoSlotState.none] if nothing has been captured for it.
  PhotoSlotState stateOf(String bookingId, String kind) =>
      _states[_slotKey(bookingId, kind)] ?? PhotoSlotState.none;

  void _set(String key, PhotoSlotState s) {
    _states[key] = s;
    notifyListeners();
  }

  /// Capture a slot and start uploading. Returns as soon as the first attempt is
  /// underway (or scheduled) — never blocks the caller on the network.
  ///
  /// ALWAYS (re)starts the slot, even if it is already `done` — a retake is a
  /// re-capture that the backend soft-deletes + replaces; dropping it here
  /// would silently discard the new photo while the slot still reads
  /// "Uploaded". [PhotoSlot] already disables its button while `uploading`, so
  /// there is no double-enqueue risk from the UI.
  Future<void> enqueue({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
  }) async {
    final key = _slotKey(bookingId, kind);
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _attempts[key] = 0;
    await _attempt(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
  }

  Future<void> _attempt({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
    required int generation,
  }) async {
    final key = _slotKey(bookingId, kind);
    if (_generations[key] != generation) return; // superseded before starting

    _set(key, PhotoSlotState.uploading);
    try {
      // 1. sign — content length is the COMPRESSED byte count.
      final signRes = await _repo.signPhoto(
        bookingId,
        kind: kind,
        contentLengthBytes: photo.bytes.length,
      );
      if (_generations[key] != generation) return; // superseded during sign
      final sign = switch (signRes) {
        Ok(value: final v) => v,
        Failure(message: final m) => throw _UploadStepError(m),
      };

      // 2. PUT the bytes to the signed url (dev-hook branch handled in the seam).
      await _put(url: sign.url, key: sign.key, bytes: photo.bytes);
      if (_generations[key] != generation) return; // superseded during PUT

      // 3. confirm — geotag flows through both-or-neither (repo enforces it too).
      final confirmRes = await _repo.confirmPhoto(
        bookingId,
        kind: kind,
        key: sign.key,
        capturedAt: photo.capturedAt,
        geotagLat: photo.lat,
        geotagLng: photo.lng,
      );
      if (_generations[key] != generation) return; // superseded during confirm
      switch (confirmRes) {
        case Ok():
          _set(key, PhotoSlotState.done);
        case Failure(message: final m):
          throw _UploadStepError(m);
      }
    } catch (_) {
      if (_generations[key] != generation) return; // superseded on the failure path too
      // Any step failed: mark for retry and schedule the next attempt with
      // backoff. Deliberately swallow the error detail here (no PII/leak); the
      // slot state is the surfaced signal.
      _set(key, PhotoSlotState.failedRetry);
      _scheduleRetry(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
    }
  }

  void _scheduleRetry({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
    required int generation,
  }) {
    final key = _slotKey(bookingId, kind);
    final n = _attempts[key] ?? 0;
    _attempts[key] = n + 1;
    final delay = _backoff[n < _backoff.length ? n : _backoff.length - 1];
    Future<void>.delayed(delay, () {
      // Don't retry a slot a retake has since superseded (stale generation),
      // or if this slot is no longer in the failed state (e.g. a fresh
      // enqueue already took over via a different code path).
      if (_generations[key] != generation) return;
      if (_states[key] != PhotoSlotState.failedRetry) return;
      _attempt(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
    });
  }
}

/// Internal marker for a failed sign/confirm step so it joins the same
/// catch/retry path as a thrown PUT.
class _UploadStepError implements Exception {
  _UploadStepError(this.message);
  final String message;
  @override
  String toString() => 'UploadStepError';
}

/// Production PUT seam. Real presigned PUT to R2, EXCEPT when the signed url is a
/// local-dev fake (`dev-r2.local`): then it calls the dev-only backend hook
/// `POST /dev/photos/mark-uploaded {key}` so confirm's HEAD-verify passes in
/// local testing (ADR-0007). Production runs the real PUT untouched.
PutFn _defaultPut(Dio dio) => ({
      required String url,
      required String key,
      required List<int> bytes,
    }) async {
      if (url.contains('dev-r2.local')) {
        // Dev affordance: no real object store locally — tell the backend the
        // object "exists". (404s until Task 8 lands the route; that's a Task-8
        // live-testing concern, the branch is wired here.)
        await dio.post('/dev/photos/mark-uploaded', data: {'key': key});
        return;
      }
      await dio.put(
        url,
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: {'Content-Length': bytes.length},
          contentType: 'image/jpeg',
        ),
      );
    };

/// Exposed as a plain Provider (Riverpod 3 dropped the legacy
/// ChangeNotifierProvider). The queue IS a ChangeNotifier, so the UI observes it
/// with a ListenableBuilder (see [PhotoSlot]) rather than provider re-watching.
final photoUploadQueueProvider = Provider<PhotoUploadQueue>((ref) {
  final queue = PhotoUploadQueue(
    repo: ref.read(technicianJobRepositoryProvider),
    put: _defaultPut(ref.read(dioProvider)),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// True iff every kind in [kinds] already has evidence — either uploaded this
/// session (`queue.stateOf(job.id, kind) == done`) or already on the server
/// (`job.photos` — e.g. after an app restart or re-entering the job). Empty
/// [kinds] is vacuously true. Used by the diagnosis form (Task 7b) and the
/// repair-photos gate (Task 8) to decide whether a step can proceed.
bool photosReady(PhotoUploadQueue queue, TechnicianJobDto job, List<String> kinds) {
  for (final kind in kinds) {
    final queuedDone = queue.stateOf(job.id, kind) == PhotoSlotState.done;
    final onServer = job.photos.any((p) => p.kind == kind);
    if (!queuedDone && !onServer) return false;
  }
  return true;
}

/// A single evidence-photo slot: label + current state + a capture/retake
/// button. On tap it captures (camera-only) then enqueues the upload. It never
/// blocks — the queue drives the state the widget re-reads.
class PhotoSlot extends ConsumerWidget {
  const PhotoSlot({
    super.key,
    required this.bookingId,
    required this.kind,
    required this.label,
    this.serverHasPhoto = false,
  });

  final String bookingId;
  final String kind;
  final String label;

  /// True if the server already has an active photo for this slot (e.g. on
  /// app restart or re-entering the job) — shown as `done` unless the queue
  /// has a more current (live-captured) state for the same slot.
  final bool serverHasPhoto;

  Future<void> _onTap(WidgetRef ref) async {
    final photo = await ref.read(cameraServiceProvider).capture();
    if (photo == null) return; // cancelled
    await ref
        .read(photoUploadQueueProvider)
        .enqueue(bookingId: bookingId, kind: kind, photo: photo);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.read(photoUploadQueueProvider);
    // The queue is a ChangeNotifier; rebuild this slot whenever it notifies.
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final queued = queue.stateOf(bookingId, kind);
        // The live queue state always wins; it only falls back to the
        // server-confirmed state when nothing has happened in this session.
        final displayed =
            queued != PhotoSlotState.none ? queued : (serverHasPhoto ? PhotoSlotState.done : PhotoSlotState.none);
        return _buildRow(context, ref, displayed);
      },
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, PhotoSlotState state) {
    final (String status, Color color) = switch (state) {
      PhotoSlotState.none => ('Not captured', FixCareColors.textMuted),
      PhotoSlotState.uploading => ('Uploading…', FixCareColors.primary),
      PhotoSlotState.done => ('Uploaded', FixCareColors.success),
      PhotoSlotState.failedRetry => ('Upload failed — retrying', FixCareColors.errorText),
    };

    final buttonLabel = state == PhotoSlotState.none ? 'Capture' : 'Retake';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Row(
        children: [
          Icon(
            state == PhotoSlotState.done ? Icons.check_circle : Icons.photo_camera_outlined,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(status, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: state == PhotoSlotState.uploading ? null : () => _onTap(ref),
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
