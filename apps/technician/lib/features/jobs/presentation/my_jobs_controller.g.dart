// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'my_jobs_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MyJobsController)
final myJobsControllerProvider = MyJobsControllerProvider._();

final class MyJobsControllerProvider
    extends $AsyncNotifierProvider<MyJobsController, List<TechnicianJobDto>> {
  MyJobsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myJobsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myJobsControllerHash();

  @$internal
  @override
  MyJobsController create() => MyJobsController();
}

String _$myJobsControllerHash() => r'9a1f31797fc8ff98b441daa3901cac31c5929ba3';

abstract class _$MyJobsController
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
