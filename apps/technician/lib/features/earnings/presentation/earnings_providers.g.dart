// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'earnings_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(earningsSummary)
final earningsSummaryProvider = EarningsSummaryProvider._();

final class EarningsSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<EarningsSummaryDto>,
          EarningsSummaryDto,
          FutureOr<EarningsSummaryDto>
        >
    with
        $FutureModifier<EarningsSummaryDto>,
        $FutureProvider<EarningsSummaryDto> {
  EarningsSummaryProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutoRetry,
        name: r'earningsSummaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$earningsSummaryHash();

  @$internal
  @override
  $FutureProviderElement<EarningsSummaryDto> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<EarningsSummaryDto> create(Ref ref) {
    return earningsSummary(ref);
  }
}

String _$earningsSummaryHash() => r'e65d6d226f011c9254e16573f53d96c9bd6495df';

/// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
/// dropped, so a late "Load more" can never splice stale rows into a fresh list.

@ProviderFor(LedgerController)
final ledgerControllerProvider = LedgerControllerProvider._();

/// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
/// dropped, so a late "Load more" can never splice stale rows into a fresh list.
final class LedgerControllerProvider
    extends $AsyncNotifierProvider<LedgerController, LedgerState> {
  /// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
  /// dropped, so a late "Load more" can never splice stale rows into a fresh list.
  LedgerControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: noAutoRetry,
        name: r'ledgerControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerControllerHash();

  @$internal
  @override
  LedgerController create() => LedgerController();
}

String _$ledgerControllerHash() => r'827618693c561ab629fdf3f44940800626c0c305';

/// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
/// dropped, so a late "Load more" can never splice stale rows into a fresh list.

abstract class _$LedgerController extends $AsyncNotifier<LedgerState> {
  FutureOr<LedgerState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<LedgerState>, LedgerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<LedgerState>, LedgerState>,
              AsyncValue<LedgerState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
