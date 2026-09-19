import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/technician_job_repository.dart';

part 'my_jobs_controller.g.dart';

@riverpod
class MyJobsController extends _$MyJobsController {
  @override
  Future<List<TechnicianJobDto>> build() async {
    final r = await ref.read(technicianJobRepositoryProvider).mine();
    return switch (r) {
      Ok(value: final list) => list,
      Failure(message: final m) => throw Exception(m),
    };
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final r = await ref.read(technicianJobRepositoryProvider).mine();
      return switch (r) {
        Ok(value: final list) => list,
        Failure(message: final m) => throw Exception(m),
      };
    });
  }
}
