import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';
import 'job_action.dart';

part 'job_detail_controller.g.dart';

const jobPollInterval = Duration(seconds: 5);

/// Loads and adaptively polls a single job for the job-detail screen.
///
/// There is no single-job GET on the technician API — jobs are only ever
/// listed via `mine()`. This controller re-fetches the full list on every
/// poll tick and finds the job by id within it, so it can observe
/// customer-side state transitions (e.g. arrival confirmation, completion
/// confirmation, cash decline) without the technician taking any action.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after
/// the current poll completes, so a slow network never stacks overlapping
/// requests. Every fetch (poll or [refetch]) takes a sequence number and its
/// response is applied only if it is newer than the last one applied — an
/// older response landing late (e.g. a poll issued before an action, arriving
/// after the action's refetch) is dropped instead of regressing the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.
@riverpod
class JobDetail extends _$JobDetail {
  Timer? _timer;
  late String _bookingId;

  // Monotonic across polls AND refetches (and rebuilds of this notifier).
  int _requestSeq = 0;
  int _appliedSeq = 0;
  bool _pollInFlight = false;
  bool _paused = false;

  @override
  Future<TechnicianJobDto> build(String bookingId) async {
    _bookingId = bookingId;
    ref.onDispose(_cancelTimer);
    final seq = ++_requestSeq;
    final dto = await _fetchOrThrow(bookingId);
    if (seq > _appliedSeq) _appliedSeq = seq;
    _rearm(dto);
    return dto;
  }

  Future<TechnicianJobDto> _fetchOrThrow(String bookingId) async {
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    return switch (r) {
      Ok(value: final jobs) => _findJob(jobs, bookingId) ?? (throw Exception('Job not found')),
      Failure(message: final m) => throw Exception(m),
    };
  }

  static TechnicianJobDto? _findJob(List<TechnicianJobDto> jobs, String bookingId) {
    for (final j in jobs) {
      if (j.id == bookingId) return j;
    }
    return null;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Arms the next one-shot tick — unless paused, a poll is still in flight
  /// (it re-arms itself when it completes), or the job is terminal.
  void _rearm(TechnicianJobDto? dto) {
    _cancelTimer();
    if (_paused || _pollInFlight) return;
    if (dto == null || isTerminalJob(dto)) return;
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

  /// One sequenced fetch. keep-last-good: a Failure or a momentarily-absent
  /// job leaves the state as-is (never flashes AsyncLoading/AsyncError).
  Future<void> _fetchAndApply() async {
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    if (!ref.mounted) return;
    if (seq <= _appliedSeq) return; // an older response landing late: drop it
    switch (r) {
      case Ok(value: final jobs):
        final dto = _findJob(jobs, _bookingId);
        if (dto == null) return;
        _appliedSeq = seq;
        state = AsyncData(dto);
      case Failure():
        return;
    }
  }

  /// Forced immediate reload (e.g. after a gate succeeds or on app resume).
  /// Keeps last-good on failure/not-found; never flashes AsyncLoading.
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

  /// App foregrounded: fetch now, then re-arm polling (unless terminal).
  Future<void> resume() {
    _paused = false;
    return refetch();
  }
}
