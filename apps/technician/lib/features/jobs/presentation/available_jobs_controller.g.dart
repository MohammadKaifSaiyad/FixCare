// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'available_jobs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AvailableJobsController)
final availableJobsControllerProvider = AvailableJobsControllerProvider._();

final class AvailableJobsControllerProvider
    extends
        $AsyncNotifierProvider<
          AvailableJobsController,
          List<TechnicianJobDto>
        > {
  AvailableJobsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableJobsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableJobsControllerHash();

  @$internal
  @override
  AvailableJobsController create() => AvailableJobsController();
}

String _$availableJobsControllerHash() =>
    r'3307dfa506d12cef687c36fc043dcb71a7aed9a9';

abstract class _$AvailableJobsController
    extends $AsyncNotifier<List<TechnicianJobDto>> {
  FutureOr<List<TechnicianJobDto>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<List<TechnicianJobDto>>, List<TechnicianJobDto>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<TechnicianJobDto>>,
                List<TechnicianJobDto>
              >,
              AsyncValue<List<TechnicianJobDto>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
