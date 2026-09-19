import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';
import 'my_jobs_controller.dart';

part 'available_jobs_controller.g.dart';

@riverpod
class AvailableJobsController extends _$AvailableJobsController {
  @override
  Future<List<TechnicianJobDto>> build() async {
    final r = await ref.read(technicianJobRepositoryProvider).available();
    return switch (r) {
      Ok(value: final list) => list,
      Failure(message: final m) => throw Exception(m),
    };
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final r = await ref.read(technicianJobRepositoryProvider).available();
      return switch (r) {
        Ok(value: final list) => list,
        Failure(message: final m) => throw Exception(m),
      };
    });
  }

  /// Accepts a job. On success refreshes BOTH lists (this one drops the job
  /// once accepted; my-jobs picks it up) — the UI reads the returned [Result]
  /// only to decide whether to snack the failure message.
  Future<Result<TechnicianJobDto>> accept(String id) async {
    final r = await ref.read(technicianJobRepositoryProvider).accept(id);
    if (r is Ok<TechnicianJobDto>) {
      await refresh();
      await ref.read(myJobsControllerProvider.notifier).refresh();
    }
    return r;
  }
}
