import 'dart:async';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';

part 'job_detail_controller.g.dart';

const jobPollInterval = Duration(seconds: 5);

/// The job is no longer this technician's: the single-job GET answered 404 (gone) or 403 (reassigned).
/// Distinct from a transient fetch failure so the job-detail screen shows this exact copy.
class JobVanishedException implements Exception {
  const JobVanishedException();
  @override
  String toString() => 'This job is no longer assigned to you.';
}

bool _isGone(FailureKind k) => k == FailureKind.notFound || k == FailureKind.forbidden;

/// Riverpod auto-retries a provider whose build threw an [Exception]. A vanished job is a definite answer
/// (404/403), not a glitch — re-asking would only repeat the same request and flicker the error screen —
/// so it is never auto-retried (the screen's Retry button invalidates the provider). Anything else keeps
/// Riverpod's default retry/backoff.
Duration? _retryUnlessVanished(int retryCount, Object error) =>
    error is JobVanishedException ? null : ProviderContainer.defaultRetry(retryCount, error);

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.
@Riverpod(retry: _retryUnlessVanished)
class JobDetail extends _$JobDetail {
  Timer? _timer;
  late String _bookingId;

  // Monotonic across polls AND refetches (and rebuilds of this notifier).
  int _requestSeq = 0;
  int _appliedSeq = 0;
  bool _pollInFlight = false;
  bool _paused = false;
  bool _vanished = false;

  @override
  Future<TechnicianJobDetailDto> build(String bookingId) async {
    _bookingId = bookingId;
    _vanished = false;
    ref.onDispose(_cancelTimer);
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).job(bookingId);
    final detail = switch (r) {
      Ok(value: final v) => v,
      Failure(kind: final k) when _isGone(k) => throw const JobVanishedException(),
      Failure(message: final m) => throw Exception(m),
    };
    if (seq > _appliedSeq) _appliedSeq = seq;
    _rearm(detail);
    return detail;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Arms the next one-shot tick — unless paused, a poll is still in flight (it re-arms itself when it
  /// completes), the job vanished, or the job is terminal.
  void _rearm(TechnicianJobDetailDto? detail) {
    _cancelTimer();
    if (_paused || _pollInFlight || _vanished) return;
    if (detail == null || isTerminalJob(detail.job)) return;
    _timer = Timer(jobPollInterval, _poll);
  }

  Future<void> _poll() async {
    _timer = null;
    if (!ref.mounted || _pollInFlight) return;
    _pollInFlight = true;
    try {
      await _fetchAndApply();
    } finally {
      _pollInFlight = false;
    }
    if (!ref.mounted) return;
    _rearm(state.value);
  }

  /// One sequenced fetch. keep-last-good on a transient Failure (never flashes AsyncLoading/AsyncError);
  /// 404/403 → the job is gone → AsyncError(JobVanishedException) and polling stops. A response that
  /// differs only in photo URLs (the app never shows them) is applied silently (no listener notify).
  Future<void> _fetchAndApply() async {
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).job(_bookingId);
    if (!ref.mounted) return;
    if (seq <= _appliedSeq) return; // an older response landing late: drop it
    switch (r) {
      case Ok(value: final detail):
        _appliedSeq = seq;
        _vanished = false;
        final current = state.value;
        if (current != null && _sameIgnoringPhotoUrls(current, detail)) return;
        state = AsyncData(detail);
      case Failure(kind: final k) when _isGone(k):
        _appliedSeq = seq;
        _vanished = true;
        _cancelTimer();
        state = AsyncError(const JobVanishedException(), StackTrace.current);
      case Failure():
        return; // transient (network/5xx/…): keep last good, retry next tick
    }
  }

  /// Forced immediate reload (after an action, or on resume). Never flashes AsyncLoading.
  Future<void> refetch() async {
    await _fetchAndApply();
    if (!ref.mounted) return;
    _rearm(state.value);
  }

  /// App backgrounded: stop polling (no data/battery burn off-screen).
  void pause() {
    _paused = true;
    _cancelTimer();
  }

  /// App foregrounded: fetch now, then re-arm polling (unless terminal / vanished).
  Future<void> resume() {
    _paused = false;
    return refetch();
  }
}

/// "Unchanged" check for [JobDetail._fetchAndApply]: identical except each photo's `url` — the app only
/// reads a photo's `kind`, never displays its (freshly re-signed) URL. Parts must match exactly.
bool _sameIgnoringPhotoUrls(TechnicianJobDetailDto a, TechnicianJobDetailDto b) {
  final x = a.job;
  final y = b.job;
  if (x.id != y.id ||
      x.bookingNumber != y.bookingNumber ||
      x.state != y.state ||
      x.scheduledSlot != y.scheduledSlot ||
      x.service != y.service ||
      x.zone != y.zone ||
      x.visitFeePaise != y.visitFeePaise ||
      x.laborPaise != y.laborPaise ||
      x.address != y.address ||
      x.customer != y.customer) {
    return false;
  }
  if (!listEquals(a.parts, b.parts)) return false;
  if (x.photos.length != y.photos.length) return false;
  for (var i = 0; i < x.photos.length; i++) {
    if (x.photos[i].kind != y.photos[i].kind || x.photos[i].capturedAt != y.photos[i].capturedAt) return false;
  }
  return true;
}
