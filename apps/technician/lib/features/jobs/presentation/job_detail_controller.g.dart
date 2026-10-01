// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(JobDetail)
final jobDetailProvider = JobDetailFamily._();

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
final class JobDetailProvider
    extends $AsyncNotifierProvider<JobDetail, TechnicianJobDto> {
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
  JobDetailProvider._({
    required JobDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'jobDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$jobDetailHash();

  @override
  String toString() {
    return r'jobDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  JobDetail create() => JobDetail();

  @override
  bool operator ==(Object other) {
    return other is JobDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$jobDetailHash() => r'58a87a7648fb2297602d7316f64720c953e2c133';

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

final class JobDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          JobDetail,
          AsyncValue<TechnicianJobDto>,
          TechnicianJobDto,
          FutureOr<TechnicianJobDto>,
          String
        > {
  JobDetailFamily._()
    : super(
        retry: null,
        name: r'jobDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

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

  JobDetailProvider call(String bookingId) =>
      JobDetailProvider._(argument: bookingId, from: this);

  @override
  String toString() => r'jobDetailProvider';
}

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

abstract class _$JobDetail extends $AsyncNotifier<TechnicianJobDto> {
  late final _$args = ref.$arg as String;
  String get bookingId => _$args;

  FutureOr<TechnicianJobDto> build(String bookingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<TechnicianJobDto>, TechnicianJobDto>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<TechnicianJobDto>, TechnicianJobDto>,
              AsyncValue<TechnicianJobDto>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
