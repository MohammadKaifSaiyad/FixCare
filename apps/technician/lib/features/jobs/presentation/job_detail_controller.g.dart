// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_detail_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
/// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
/// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
/// nothing on screen (so no rebuild/diff would ever tell it).

@ProviderFor(JobFetchOkSeq)
final jobFetchOkSeqProvider = JobFetchOkSeqFamily._();

/// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
/// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
/// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
/// nothing on screen (so no rebuild/diff would ever tell it).
final class JobFetchOkSeqProvider
    extends $NotifierProvider<JobFetchOkSeq, int> {
  /// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
  /// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
  /// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
  /// nothing on screen (so no rebuild/diff would ever tell it).
  JobFetchOkSeqProvider._({
    required JobFetchOkSeqFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'jobFetchOkSeqProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$jobFetchOkSeqHash();

  @override
  String toString() {
    return r'jobFetchOkSeqProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  JobFetchOkSeq create() => JobFetchOkSeq();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is JobFetchOkSeqProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$jobFetchOkSeqHash() => r'0e156b533ffa0b4403b3f0045d858106bd95d84f';

/// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
/// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
/// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
/// nothing on screen (so no rebuild/diff would ever tell it).

final class JobFetchOkSeqFamily extends $Family
    with $ClassFamilyOverride<JobFetchOkSeq, int, int, int, String> {
  JobFetchOkSeqFamily._()
    : super(
        retry: null,
        name: r'jobFetchOkSeqProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
  /// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
  /// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
  /// nothing on screen (so no rebuild/diff would ever tell it).

  JobFetchOkSeqProvider call(String bookingId) =>
      JobFetchOkSeqProvider._(argument: bookingId, from: this);

  @override
  String toString() => r'jobFetchOkSeqProvider';
}

/// The request seq of the latest SUCCESSFUL single-job fetch for a booking (applied, or unchanged and
/// skipped) — written by [JobDetail], 0 until one lands. Lets a widget that marked the cart "unconfirmed"
/// after a failed refetch clear that mark the moment any LATER fetch succeeds, even one that changed
/// nothing on screen (so no rebuild/diff would ever tell it).

abstract class _$JobFetchOkSeq extends $Notifier<int> {
  late final _$args = ref.$arg as String;
  String get bookingId => _$args;

  int build(String bookingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.

@ProviderFor(JobDetail)
final jobDetailProvider = JobDetailFamily._();

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.
final class JobDetailProvider
    extends $AsyncNotifierProvider<JobDetail, TechnicianJobDetailDto> {
  /// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
  /// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
  /// the technician acting — and reads the job's real parts cart.
  ///
  /// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
  /// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
  /// applied only if newer than the last one applied — a late response never regresses the card.
  /// [pause]/[resume] stop and restart the chain while the app is backgrounded.
  JobDetailProvider._({
    required JobDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: _retryUnlessVanished,
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

String _$jobDetailHash() => r'249d88a99230b854586ec97454b843cbda7fd733';

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.

final class JobDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          JobDetail,
          AsyncValue<TechnicianJobDetailDto>,
          TechnicianJobDetailDto,
          FutureOr<TechnicianJobDetailDto>,
          String
        > {
  JobDetailFamily._()
    : super(
        retry: _retryUnlessVanished,
        name: r'jobDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
  /// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
  /// the technician acting — and reads the job's real parts cart.
  ///
  /// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
  /// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
  /// applied only if newer than the last one applied — a late response never regresses the card.
  /// [pause]/[resume] stop and restart the chain while the app is backgrounded.

  JobDetailProvider call(String bookingId) =>
      JobDetailProvider._(argument: bookingId, from: this);

  @override
  String toString() => r'jobDetailProvider';
}

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.

abstract class _$JobDetail extends $AsyncNotifier<TechnicianJobDetailDto> {
  late final _$args = ref.$arg as String;
  String get bookingId => _$args;

  FutureOr<TechnicianJobDetailDto> build(String bookingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<TechnicianJobDetailDto>, TechnicianJobDetailDto>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<TechnicianJobDetailDto>,
                TechnicianJobDetailDto
              >,
              AsyncValue<TechnicianJobDetailDto>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
