import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/photo_upload_client.dart';
import '../data/technician_job_repository.dart';
import 'settings_opener.dart';

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

/// Compresses raw image bytes to <500KB (production: [compressToBudget]).
typedef CompressFn = Future<List<int>> Function(List<int> bytes);

/// One JPEG re-encode of [bytes] at [quality]. [minWidth]/[minHeight] null =
/// the plugin's default target size; set = downscale toward that size.
typedef CompressStepFn = Future<List<int>> Function(
  List<int> bytes, {
  required int quality,
  int? minWidth,
  int? minHeight,
});

/// The compression ladder, cheapest-quality-loss first: quality 80/60/45/30 at
/// the plugin's default size, then — only if still over budget — downscale to
/// 1280 @ q60, then 1024 @ q50.
const List<({int quality, int? minWidth, int? minHeight})> _compressLadder = [
  (quality: 80, minWidth: null, minHeight: null),
  (quality: 60, minWidth: null, minHeight: null),
  (quality: 45, minWidth: null, minHeight: null),
  (quality: 30, minWidth: null, minHeight: null),
  (quality: 60, minWidth: 1280, minHeight: 1280),
  (quality: 50, minWidth: 1024, minHeight: 1024),
];

/// Compresses [bytes] to at most [maxBytes], walking [_compressLadder]. Each
/// step re-encodes the ORIGINAL bytes (never a lossy output again). Returns the
/// first result within budget; if none fits, the smallest result produced —
/// so the <500KB budget is met whenever the ladder can meet it at all, and an
/// oversize photo is as small as it can be (the backend's 1MB sign cap then
/// fails it visibly as a terminal slot error, never an endless retry).
Future<List<int>> compressToBudget(
  List<int> bytes, {
  required CompressStepFn compress,
  int maxBytes = kPhotoMaxBytes,
}) async {
  List<int>? smallest;
  for (final step in _compressLadder) {
    final out = await compress(
      bytes,
      quality: step.quality,
      minWidth: step.minWidth,
      minHeight: step.minHeight,
    );
    if (out.length <= maxBytes) return out;
    if (smallest == null || out.length < smallest.length) smallest = out;
  }
  return smallest ?? bytes;
}

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

    // The shutter moment: stamped BEFORE compression and the (up to 20s)
    // location read, so the evidence timestamp is when the photo was taken.
    final capturedAt = DateTime.now().toUtc();

    final raw = await shot.readAsBytes();
    final compressed = await _compress(raw);

    // One-shot geotag at capture time (both-or-neither).
    final pos = await _readLocation();

    return CapturedPhoto(
      bytes: compressed,
      capturedAt: capturedAt.toIso8601String(),
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
  }

  // Native-side downsizing first (maxWidth + imageQuality): a low-end device
  // never has to decode a full-resolution frame in Dart before compressing.
  static Future<XFile?> _defaultPickImage({required ImageSource source}) =>
      ImagePicker().pickImage(source: source, maxWidth: 1920, imageQuality: 85);

  static Future<List<int>> _defaultCompress(List<int> bytes) =>
      compressToBudget(bytes, compress: _pluginCompressStep);

  static Future<List<int>> _pluginCompressStep(
    List<int> bytes, {
    required int quality,
    int? minWidth,
    int? minHeight,
  }) {
    // readAsBytes already returns a Uint8List — don't copy the frame again.
    final input = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (minWidth == null || minHeight == null) {
      return FlutterImageCompress.compressWithList(input, quality: quality, format: CompressFormat.jpeg);
    }
    return FlutterImageCompress.compressWithList(
      input,
      quality: quality,
      minWidth: minWidth,
      minHeight: minHeight,
      format: CompressFormat.jpeg,
    );
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

/// Per-slot upload state the UI observes.
/// - `none`: nothing captured for the slot this session.
/// - `uploading`: an attempt (sign -> PUT -> confirm) is in flight.
/// - `done`: confirmed by the backend.
/// - `failedRetry`: a TRANSIENT failure (network, 5xx, 408/429); a backoff
///   retry is scheduled.
/// - `failed`: a TERMINAL failure (the backend refused it, or retries ran out);
///   nothing more happens until the technician retakes. [PhotoUploadQueue.failureOf]
///   holds the message to show.
enum PhotoSlotState { none, uploading, done, failedRetry, failed }

/// Default backoff between retries. Grows, then clamps at the last entry.
const List<Duration> _defaultBackoff = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
];

/// Consecutive transient failures after which a slot gives up (goes `failed`).
const int kMaxTransientUploadFailures = 6;

/// Terminal message for a PUT the object store rejected (a non-retryable
/// status). Deliberately generic: never the url, key, or response body.
const String kPhotoPutRejectedMessage = "Couldn't upload the photo. Retake to try again.";

/// Terminal message once [kMaxTransientUploadFailures] transient failures in a
/// row have been hit.
const String kPhotoRetriesExhaustedMessage = 'Upload keeps failing. Check your connection, then retake.';

/// In-app retrying upload queue (NOT BullMQ — that's backend-only). Per slot it
/// runs sign -> PUT-to-url -> confirm and tracks state. A failure is classified:
/// TRANSIENT (network, 5xx, 408, 429, anything unexpected) -> `failedRetry` +
/// a backoff retry, capped at [kMaxTransientUploadFailures]; TERMINAL (the
/// backend said no: 401/403/409/422/…, or a rejected PUT) -> `failed` with the
/// message, no more retries until a retake. The UI enqueues and never blocks
/// on the upload; it observes [stateOf]/[failureOf] via ChangeNotifier.
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
  // Consecutive transient failures per slot (reset on every enqueue): picks
  // the backoff step and enforces the cap.
  final Map<String, int> _attempts = {};
  // Terminal failure message per slot (only meaningful while `failed`).
  final Map<String, String> _failures = {};
  // The pending backoff retry per slot — cancellable (a retake or dispose()
  // cancels it), unlike a Future.delayed.
  final Map<String, Timer> _retryTimers = {};
  // Bumped on every enqueue. A scheduled/in-flight attempt carries the
  // generation it was started with and aborts (no state write, no further
  // network call) as soon as it no longer matches — this is what makes a
  // retake (which bumps the generation) win over a stale retry or a stale
  // attempt that is already mid-flight when the retake happens.
  final Map<String, int> _generations = {};
  bool _disposed = false;

  static String _slotKey(String bookingId, String kind) => '$bookingId|$kind';

  /// State of a slot; [PhotoSlotState.none] if nothing has been captured for it.
  PhotoSlotState stateOf(String bookingId, String kind) =>
      _states[_slotKey(bookingId, kind)] ?? PhotoSlotState.none;

  /// The message to show for a `failed` slot (the backend's text verbatim, or
  /// a generic upload message); null for any other state.
  String? failureOf(String bookingId, String kind) {
    final key = _slotKey(bookingId, kind);
    return _states[key] == PhotoSlotState.failed ? _failures[key] : null;
  }

  /// A superseded (retaken) or disposed attempt must stop: no state write, no
  /// further network call.
  bool _stale(String key, int generation) => _disposed || _generations[key] != generation;

  void _set(String key, PhotoSlotState s) {
    if (_disposed) return;
    _states[key] = s;
    notifyListeners();
  }

  /// Capture a slot and start uploading. Returns as soon as the first attempt is
  /// settled (or a retry scheduled) — never blocks the caller beyond that.
  ///
  /// ALWAYS (re)starts the slot, even if it is already `done` or `failed` — a
  /// retake is a re-capture that the backend soft-deletes + replaces; dropping
  /// it here would silently discard the new photo while the slot still reads
  /// "Uploaded". [PhotoSlot] already disables its button while `uploading`, so
  /// there is no double-enqueue risk from the UI.
  Future<void> enqueue({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
  }) async {
    if (_disposed) return;
    final key = _slotKey(bookingId, kind);
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    _attempts[key] = 0;
    _failures.remove(key);
    _retryTimers.remove(key)?.cancel();
    await _attempt(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
  }

  Future<void> _attempt({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
    required int generation,
  }) async {
    final key = _slotKey(bookingId, kind);
    if (_stale(key, generation)) return; // superseded before starting

    _set(key, PhotoSlotState.uploading);
    try {
      // 1. sign — content length is the COMPRESSED byte count.
      final signRes = await _repo.signPhoto(
        bookingId,
        kind: kind,
        contentLengthBytes: photo.bytes.length,
      );
      if (_stale(key, generation)) return; // superseded during sign
      final sign = switch (signRes) {
        Ok(value: final v) => v,
        Failure(kind: final k, message: final m) => throw _UploadStepError(k, m),
      };

      // 2. PUT the bytes to the signed url (dev-hook branch handled in the seam).
      await _put(url: sign.url, key: sign.key, bytes: photo.bytes);
      if (_stale(key, generation)) return; // superseded during PUT

      // 3. confirm — geotag flows through both-or-neither (repo enforces it too).
      final confirmRes = await _repo.confirmPhoto(
        bookingId,
        kind: kind,
        key: sign.key,
        capturedAt: photo.capturedAt,
        geotagLat: photo.lat,
        geotagLng: photo.lng,
      );
      if (_stale(key, generation)) return; // superseded during confirm
      switch (confirmRes) {
        case Ok():
          _set(key, PhotoSlotState.done);
        case Failure(kind: final k, message: final m):
          throw _UploadStepError(k, m);
      }
    } catch (e) {
      if (_stale(key, generation)) return; // superseded on the failure path too
      // Nothing is logged (no PII/credential leak); the slot state + stored
      // message are the surfaced signal.
      final terminal = _terminalMessage(e);
      if (terminal != null) {
        _fail(key, terminal);
        return;
      }
      final failures = (_attempts[key] ?? 0) + 1;
      _attempts[key] = failures;
      if (failures >= kMaxTransientUploadFailures) {
        _fail(key, kPhotoRetriesExhaustedMessage);
        return;
      }
      _set(key, PhotoSlotState.failedRetry);
      _scheduleRetry(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
    }
  }

  void _fail(String key, String message) {
    _failures[key] = message;
    _set(key, PhotoSlotState.failed);
  }

  /// Null = TRANSIENT (retry with backoff). Non-null = TERMINAL, with the
  /// message to show on the slot.
  static String? _terminalMessage(Object error) {
    if (error is _UploadStepError) {
      return switch (error.kind) {
        FailureKind.network || FailureKind.server || FailureKind.rateLimited => null,
        // 401/400 and every other 4xx (403/409/422…): the backend said no —
        // retrying the same request cannot succeed. Its message, verbatim.
        FailureKind.unauthorized || FailureKind.validation || FailureKind.unknown => error.message,
      };
    }
    if (error is PhotoUploadException) {
      final status = error.statusCode;
      if (status == null || status >= 500 || status == 408 || status == 429) return null;
      return kPhotoPutRejectedMessage;
    }
    return null; // anything unexpected: transient (still capped)
  }

  void _scheduleRetry({
    required String bookingId,
    required String kind,
    required CapturedPhoto photo,
    required int generation,
  }) {
    final key = _slotKey(bookingId, kind);
    final n = (_attempts[key] ?? 1) - 1;
    final delay = _backoff[n < _backoff.length ? n : _backoff.length - 1];
    _retryTimers.remove(key)?.cancel();
    _retryTimers[key] = Timer(delay, () {
      _retryTimers.remove(key);
      // Don't retry a slot a retake has since superseded (stale generation),
      // or if this slot is no longer in the failed-retry state.
      if (_stale(key, generation)) return;
      if (_states[key] != PhotoSlotState.failedRetry) return;
      _attempt(bookingId: bookingId, kind: kind, photo: photo, generation: generation);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    _retryTimers.clear();
    super.dispose();
  }
}

/// Internal marker for a failed sign/confirm step so it joins the same
/// catch/classify path as a thrown PUT. Carries the Failure kind (to classify)
/// and the backend message (surfaced verbatim when terminal).
class _UploadStepError implements Exception {
  _UploadStepError(this.kind, this.message);
  final FailureKind kind;
  final String message;
  @override
  String toString() => 'UploadStepError($kind)';
}

/// Exposed as a plain Provider (Riverpod 3 dropped the legacy
/// ChangeNotifierProvider). The queue IS a ChangeNotifier, so the UI observes it
/// with a ListenableBuilder (see [PhotoSlot]) rather than provider re-watching.
final photoUploadQueueProvider = Provider<PhotoUploadQueue>((ref) {
  final queue = PhotoUploadQueue(
    repo: ref.read(technicianJobRepositoryProvider),
    put: makePhotoPut(
      apiDio: ref.read(dioProvider),
      uploadDio: ref.read(photoUploadDioProvider),
    ),
  );
  ref.onDispose(queue.dispose);
  return queue;
});

/// Display label per evidence-photo kind. Photo cards build their slots by
/// iterating `requiredPhotoKinds(state)` and looking the label up here — the
/// SAME list their gate ([photosReady]) checks — so the slots shown and the
/// gate can never disagree.
const Map<String, String> photoSlotLabels = {
  'DIAGNOSIS_OVERVIEW': 'Overview photo',
  'DIAGNOSIS_CLOSEUP': 'Close-up of the fault',
  'REPAIR_OLD_PART': 'Old part removed',
  'REPAIR_NEW_PACKAGING': 'New part packaging',
  'REPAIR_INSTALLED': 'New part installed',
};

/// True iff every kind in [kinds] already has evidence — either uploaded this
/// session (`queue.stateOf(job.id, kind) == done`) or already on the server
/// (`job.photos` — e.g. after an app restart or re-entering the job). A server
/// photo only counts while the queue has nothing newer for that slot (`none`):
/// once a retake is `uploading`/`failedRetry`/`failed`, the technician believes
/// the NEW photo is the evidence, so the gate waits for it. Empty [kinds] is
/// vacuously true. Used by the diagnosis form and the repair-photos gate.
bool photosReady(PhotoUploadQueue queue, TechnicianJobDto job, List<String> kinds) {
  for (final kind in kinds) {
    final queued = queue.stateOf(job.id, kind);
    if (queued == PhotoSlotState.done) continue;
    final onServer = job.photos.any((p) => p.kind == kind);
    if (queued == PhotoSlotState.none && onServer) continue;
    return false;
  }
  return true;
}

/// Inline capture-error copy (the camera never opened, or the shot failed).
const String kCameraAccessDeniedMessage = 'Camera access is off. Allow it in Settings to take repair photos.';
const String kCaptureFailedMessage = "Couldn't take the photo. Try again.";

/// A single evidence-photo slot: label + current state + a capture/retake
/// button. On tap it captures (camera-only) then enqueues the upload. It never
/// blocks — the queue drives the state the widget re-reads. A capture that
/// fails (camera permission denied, no camera, compression error) is shown
/// inline — never swallowed.
class PhotoSlot extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<PhotoSlot> createState() => _PhotoSlotState();
}

class _PhotoSlotState extends ConsumerState<PhotoSlot> {
  // True while the OS camera is open: the button is disabled, so a second tap
  // can't launch the picker again (image_picker's `already_active`).
  bool _capturing = false;
  String? _captureError;
  bool _captureNeedsSettings = false;

  Future<void> _onTap() async {
    if (_capturing) return;
    // Everything the upload needs is read BEFORE the camera opens: if this
    // card is swapped or unmounted while the OS camera is up, `ref` is gone
    // but the photo still reaches the queue for the slot that was tapped.
    final camera = ref.read(cameraServiceProvider);
    final queue = ref.read(photoUploadQueueProvider);
    final bookingId = widget.bookingId;
    final kind = widget.kind;
    setState(() {
      _capturing = true;
      _captureError = null;
      _captureNeedsSettings = false;
    });
    try {
      final photo = await camera.capture();
      if (photo == null) return; // cancelled
      await queue.enqueue(bookingId: bookingId, kind: kind, photo: photo);
    } on PlatformException catch (e) {
      final denied = e.code == 'camera_access_denied';
      _showCaptureError(denied ? kCameraAccessDeniedMessage : kCaptureFailedMessage, needsSettings: denied);
    } catch (_) {
      _showCaptureError(kCaptureFailedMessage, needsSettings: false);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showCaptureError(String message, {required bool needsSettings}) {
    if (!mounted) return;
    setState(() {
      _captureError = message;
      _captureNeedsSettings = needsSettings;
    });
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.read(photoUploadQueueProvider);
    // The queue is a ChangeNotifier; rebuild this slot whenever it notifies.
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final queued = queue.stateOf(widget.bookingId, widget.kind);
        // The live queue state always wins; it only falls back to the
        // server-confirmed state when nothing has happened in this session.
        final displayed = queued != PhotoSlotState.none
            ? queued
            : (widget.serverHasPhoto ? PhotoSlotState.done : PhotoSlotState.none);
        return _buildRow(displayed, queue.failureOf(widget.bookingId, widget.kind));
      },
    );
  }

  Widget _buildRow(PhotoSlotState state, String? failure) {
    final (String status, Color color) = switch (state) {
      PhotoSlotState.none => ('Not captured', FixCareColors.textMuted),
      PhotoSlotState.uploading => ('Uploading…', FixCareColors.primary),
      PhotoSlotState.done => ('Uploaded', FixCareColors.success),
      PhotoSlotState.failedRetry => ('Upload failed — retrying', FixCareColors.errorText),
      PhotoSlotState.failed => (failure ?? kPhotoPutRejectedMessage, FixCareColors.errorText),
    };

    final buttonLabel = state == PhotoSlotState.none ? 'Capture' : 'Retake';
    final captureError = _captureError;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(status, style: TextStyle(color: color, fontSize: 12)),
                  ],
                ),
              ),
              TextButton(
                onPressed: (state == PhotoSlotState.uploading || _capturing) ? null : _onTap,
                child: Text(buttonLabel),
              ),
            ],
          ),
          if (captureError != null) ...[
            const SizedBox(height: 8),
            Text(captureError, style: const TextStyle(color: FixCareColors.errorText, fontSize: 12)),
            if (_captureNeedsSettings)
              TextButton(
                key: Key('openSettings_${widget.kind}'),
                onPressed: () => unawaited(ref.read(settingsOpenerProvider).openAppSettings()),
                child: const Text('Open settings'),
              ),
          ],
        ],
      ),
    );
  }
}
