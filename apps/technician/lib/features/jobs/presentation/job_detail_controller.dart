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
@riverpod
class JobDetail extends _$JobDetail {
  Timer? _timer;
  late String _bookingId;

  @override
  Future<TechnicianJobDto> build(String bookingId) async {
    _bookingId = bookingId;
    ref.onDispose(() => _timer?.cancel());
    final dto = await _fetchOrThrow(bookingId);
    _arm(dto);
    return dto;
  }

  Future<TechnicianJobDto> _fetchOrThrow(String bookingId) async {
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    return switch (r) {
      Ok(value: final jobs) => jobs.firstWhere(
          (j) => j.id == bookingId,
          orElse: () => throw Exception('Job not found'),
        ),
      Failure(message: final m) => throw Exception(m),
    };
  }

  void _arm(TechnicianJobDto dto) {
    _timer?.cancel();
    if (isTerminalJob(dto)) return;
    _timer = Timer.periodic(jobPollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    if (!ref.mounted) return;
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final jobs):
        TechnicianJobDto? dto;
        for (final j in jobs) {
          if (j.id == _bookingId) {
            dto = j;
            break;
          }
        }
        if (dto == null) {
          // keep-last-good: job momentarily absent from mine(), retry next tick.
          break;
        }
        state = AsyncData(dto);
        _arm(dto); // cancels itself if now terminal
      case Failure():
        // keep-last-good: leave state as-is, retry next tick.
        break;
    }
  }

  /// Forced immediate reload (e.g. after a gate succeeds or on app resume).
  /// Keeps last-good on failure/not-found; never flashes AsyncLoading.
  Future<void> refetch() async {
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final jobs):
        TechnicianJobDto? dto;
        for (final j in jobs) {
          if (j.id == _bookingId) {
            dto = j;
            break;
          }
        }
        if (dto == null) break;
        state = AsyncData(dto);
        _arm(dto);
      case Failure():
        break;
    }
  }
}
