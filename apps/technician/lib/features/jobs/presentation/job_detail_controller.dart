import 'dart:async';
import 'package:flutter/foundation.dart' show ErrorDescription, FlutterError, FlutterErrorDetails, listEquals;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';

part 'job_detail_controller.g.dart';

const jobPollInterval = Duration(seconds: 5);

/// Reports an unexpected throw that the jobs feature converted into a fallback (keep-last-good, a generic
/// message) — never swallowed silently (CLAUDE.md). Exception + stack ONLY: no response bodies, ids, phone,
/// address or codes. [doing] is a fixed description of the operation.
void reportJobsError(Object e, StackTrace st, String doing) => FlutterError.reportError(FlutterErrorDetails(
      exception: e,
      stack: st,
      library: 'fixcare jobs',
      context: ErrorDescription(doing),
    ));

/// The job is no longer this technician's: the single-job GET answered `JOB_NOT_FOUND` (gone) or
/// `JOB_NOT_ASSIGNED` (reassigned). Distinct from a transient fetch failure so the job-detail screen shows
/// this exact copy.
class JobVanishedException implements Exception {
  const JobVanishedException();
  @override
  String toString() => 'This job is no longer assigned to you.';
}

/// Any OTHER 403 from the single-job GET — e.g. "Verified technician required" (the technician was
/// suspended). Not a vanish: the job may still be theirs, so the screen shows the backend's message verbatim.
class JobAccessException implements Exception {
  const JobAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The backend's stable codes for "this job is gone / not yours" (technician-jobs.service.ts).
const _jobNotFoundCode = 'JOB_NOT_FOUND';
const _jobNotAssignedCode = 'JOB_NOT_ASSIGNED';

/// A definitive answer from the single-job GET (stop polling, show it), or null for a transient failure
/// (network/5xx/…: keep the last good job and try again next tick). A vanish is EXACTLY a job code — never
/// a message match — so a 404 without one (e.g. route-not-found from a backend that predates
/// `GET /technician/jobs/:id`) is not mistaken for "no longer assigned".
Exception? _definitiveError(Failure<Object?> f) {
  if (f.code == _jobNotFoundCode || f.code == _jobNotAssignedCode) return const JobVanishedException();
  if (f.kind == FailureKind.forbidden) return JobAccessException(f.message);
  return null;
}

/// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
/// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
/// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
/// nothing on screen (so no rebuild/diff would ever tell it).
@riverpod
class JobFetchOkSeq extends _$JobFetchOkSeq {
  @override
  int build(String bookingId) => 0;

  void set(int seq) {
    if (seq > state) state = seq;
  }
}

/// Riverpod auto-retries a provider whose build threw an [Exception]. A vanished job or a refused access is
/// a definite answer (404/403), not a glitch — re-asking would only repeat the same request and flicker the
/// error screen — so it is never auto-retried (the screen's Retry button invalidates the provider). Anything
/// else keeps Riverpod's default retry/backoff.
Duration? _retryUnlessVanished(int retryCount, Object error) => error is JobVanishedException || error is JobAccessException
    ? null
    : ProviderContainer.defaultRetry(retryCount, error);

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
  // The seq of the newest fetch that came back Ok (applied or unchanged) — a superseded refetch is a success.
  int _okSeq = 0;
  int _lastIssuedSeq = 0;
  bool _pollInFlight = false;
  bool _paused = false;
  // A definitive answer (vanished, or access refused) stops polling until a successful fetch.
  bool _stopped = false;

  @override
  Future<TechnicianJobDetailDto> build(String bookingId) async {
    _bookingId = bookingId;
    _stopped = false;
    ref.onDispose(_cancelTimer);
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).job(bookingId);
    if (seq <= _appliedSeq) {
      // A refetch (e.g. resume() during the first load) already applied a NEWER response: keep its outcome
      // instead of regressing to this older one.
      final newer = state;
      if (newer.hasError) Error.throwWithStackTrace(newer.error!, newer.stackTrace ?? StackTrace.current);
      if (newer.value case final v?) {
        _rearm(v);
        return v;
      }
    }
    final detail = switch (r) {
      Ok(value: final v) => v,
      Failure(message: final m) => throw _definitiveError(r) ?? Exception(m),
    };
    if (seq > _appliedSeq) _appliedSeq = seq;
    _markOk(seq);
    _rearm(detail);
    return detail;
  }

  /// The seq the latest [refetch] went out with — fixed when it is issued (a poll never moves it). A caller
  /// that must know "has anything newer than my refetch succeeded?" compares [jobFetchOkSeqProvider] to it.
  int get lastIssuedSeq => _lastIssuedSeq;

  void _markOk(int seq) {
    if (seq > _okSeq) _okSeq = seq;
    if (ref.mounted) ref.read(jobFetchOkSeqProvider(_bookingId).notifier).set(seq);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Arms the next one-shot tick — unless paused, a poll is still in flight (it re-arms itself when it
  /// completes), the job vanished / access was refused, or the job is terminal.
  void _rearm(TechnicianJobDetailDto? detail) {
    _cancelTimer();
    if (_paused || _pollInFlight || _stopped) return;
    if (detail == null || isTerminalJob(detail.job)) return;
    _timer = Timer(jobPollInterval, _poll);
  }

  Future<void> _poll() async {
    _timer = null;
    if (!ref.mounted || _pollInFlight) return;
    _pollInFlight = true;
    try {
      await _fetchAndApply(++_requestSeq);
    } finally {
      _pollInFlight = false;
    }
    if (!ref.mounted) return;
    _rearm(state.value);
  }

  /// One sequenced fetch. keep-last-good on a transient Failure (never flashes AsyncLoading/AsyncError);
  /// 404 / 403-not-assigned → AsyncError(JobVanishedException), any other 403 →
  /// AsyncError(JobAccessException), and polling stops. A response that differs only in photo URLs (the
  /// app never shows them) is applied silently (no listener notify).
  ///
  /// Returns true iff the screen now shows a job at least as fresh as this request: this fetch returned the
  /// job (applied, or unchanged), OR its own outcome was dropped/failed but a NEWER request already came
  /// back Ok (superseded — not a failure). False on a Failure/throw/stale drop with nothing newer succeeded.
  Future<bool> _fetchAndApply(int seq) async {
    bool supersededByNewerOk() => _okSeq > seq;
    final Result<TechnicianJobDetailDto> r;
    try {
      r = await ref.read(technicianJobRepositoryProvider).job(_bookingId);
    } catch (e, st) {
      // Unexpected (the repository wraps every known failure): transient — keep last good; the poll
      // chain must not die on it. Reported, never swallowed (exception + stack only — no response data).
      reportJobsError(e, st, 'while fetching the job for the job-detail screen');
      return ref.mounted && supersededByNewerOk();
    }
    if (!ref.mounted) return false;
    if (seq <= _appliedSeq) return supersededByNewerOk(); // an older response landing late: drop it
    switch (r) {
      case Ok(value: final detail):
        _appliedSeq = seq;
        _stopped = false;
        _markOk(seq);
        // An AsyncError (a vanish) keeps the previous good value, so `state.value` is non-null there too:
        // never take the "unchanged → no notify" shortcut while errored, or the stale error would linger.
        final current = state.hasError ? null : state.value;
        if (current != null && _sameIgnoringPhotoUrls(current, detail)) return true;
        state = AsyncData(detail);
        return true;
      case Failure():
        final definitive = _definitiveError(r);
        // transient (network/5xx/…): keep last good, retry next tick
        if (definitive == null) return supersededByNewerOk();
        _appliedSeq = seq;
        _stopped = true;
        _cancelTimer();
        state = AsyncError(definitive, StackTrace.current);
        return false;
    }
  }

  /// Forced immediate reload (after an action, or on resume). Never flashes AsyncLoading. Returns whether
  /// the screen shows the server's state as of this request (see [_fetchAndApply]) — callers that must know
  /// the cart on screen is the server's act on false. Its seq is [lastIssuedSeq] from the moment it is called.
  Future<bool> refetch() async {
    final seq = _lastIssuedSeq = ++_requestSeq;
    final ok = await _fetchAndApply(seq);
    if (ref.mounted) _rearm(state.value);
    return ok;
  }

  /// App backgrounded: stop polling (no data/battery burn off-screen).
  void pause() {
    _paused = true;
    _cancelTimer();
  }

  /// App foregrounded: fetch now, then re-arm polling (unless terminal / stopped).
  Future<bool> resume() {
    _paused = false;
    return refetch();
  }
}

/// "Unchanged" check for [JobDetail._fetchAndApply]: identical except each photo's `url` — the app only
/// reads a photo's `kind`, never displays its (freshly re-signed) URL. Every other job field is compared via
/// the DTO's own equality (so a field added later is never silently ignored); parts must match exactly.
bool _sameIgnoringPhotoUrls(TechnicianJobDetailDto a, TechnicianJobDetailDto b) {
  if (a.job.copyWith(photos: const []) != b.job.copyWith(photos: const [])) return false;
  if (!listEquals(a.parts, b.parts)) return false;
  if (a.customerQuote != b.customerQuote) return false;
  List<(String, String)> photoKeys(TechnicianJobDto j) => [for (final p in j.photos) (p.kind, p.capturedAt)];
  return listEquals(photoKeys(a.job), photoKeys(b.job));
}
