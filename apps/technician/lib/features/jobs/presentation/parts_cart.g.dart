// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'parts_cart.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Session-scoped cart state per job (keepAlive: survives leaving and
/// re-opening the job detail screen within the same app session — NOT an app
/// restart; the job DTO carries no parts array to rehydrate from, so a
/// restart losing the in-progress cart is a deferred follow-up). Backend
/// `addPart`/`removePart` are the source of truth; this just mirrors what
/// succeeded there so the UI can render the cart + estimate.

@ProviderFor(JobCart)
final jobCartProvider = JobCartFamily._();

/// Session-scoped cart state per job (keepAlive: survives leaving and
/// re-opening the job detail screen within the same app session — NOT an app
/// restart; the job DTO carries no parts array to rehydrate from, so a
/// restart losing the in-progress cart is a deferred follow-up). Backend
/// `addPart`/`removePart` are the source of truth; this just mirrors what
/// succeeded there so the UI can render the cart + estimate.
final class JobCartProvider extends $NotifierProvider<JobCart, List<CartLine>> {
  /// Session-scoped cart state per job (keepAlive: survives leaving and
  /// re-opening the job detail screen within the same app session — NOT an app
  /// restart; the job DTO carries no parts array to rehydrate from, so a
  /// restart losing the in-progress cart is a deferred follow-up). Backend
  /// `addPart`/`removePart` are the source of truth; this just mirrors what
  /// succeeded there so the UI can render the cart + estimate.
  JobCartProvider._({
    required JobCartFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'jobCartProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$jobCartHash();

  @override
  String toString() {
    return r'jobCartProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  JobCart create() => JobCart();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<CartLine> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<CartLine>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is JobCartProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$jobCartHash() => r'837ac38913693bc0f4c24726436827717a1d55f8';

/// Session-scoped cart state per job (keepAlive: survives leaving and
/// re-opening the job detail screen within the same app session — NOT an app
/// restart; the job DTO carries no parts array to rehydrate from, so a
/// restart losing the in-progress cart is a deferred follow-up). Backend
/// `addPart`/`removePart` are the source of truth; this just mirrors what
/// succeeded there so the UI can render the cart + estimate.

final class JobCartFamily extends $Family
    with
        $ClassFamilyOverride<
          JobCart,
          List<CartLine>,
          List<CartLine>,
          List<CartLine>,
          String
        > {
  JobCartFamily._()
    : super(
        retry: null,
        name: r'jobCartProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Session-scoped cart state per job (keepAlive: survives leaving and
  /// re-opening the job detail screen within the same app session — NOT an app
  /// restart; the job DTO carries no parts array to rehydrate from, so a
  /// restart losing the in-progress cart is a deferred follow-up). Backend
  /// `addPart`/`removePart` are the source of truth; this just mirrors what
  /// succeeded there so the UI can render the cart + estimate.

  JobCartProvider call(String bookingId) =>
      JobCartProvider._(argument: bookingId, from: this);

  @override
  String toString() => r'jobCartProvider';
}

/// Session-scoped cart state per job (keepAlive: survives leaving and
/// re-opening the job detail screen within the same app session — NOT an app
/// restart; the job DTO carries no parts array to rehydrate from, so a
/// restart losing the in-progress cart is a deferred follow-up). Backend
/// `addPart`/`removePart` are the source of truth; this just mirrors what
/// succeeded there so the UI can render the cart + estimate.

abstract class _$JobCart extends $Notifier<List<CartLine>> {
  late final _$args = ref.$arg as String;
  String get bookingId => _$args;

  List<CartLine> build(String bookingId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<List<CartLine>, List<CartLine>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<CartLine>, List<CartLine>>,
              List<CartLine>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
