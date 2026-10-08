import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/earnings_repository.dart';

part 'earnings_providers.g.dart';

/// A definitive load failure carrying the backend's message verbatim (shown with a Retry button).
class EarningsLoadException implements Exception {
  const EarningsLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Money screens never auto-retry — the UI offers Retry (Riverpod 3 retries a throwing build by default).
Duration? noAutoRetry(int retryCount, Object error) => null;

@Riverpod(retry: noAutoRetry)
Future<EarningsSummaryDto> earningsSummary(Ref ref) async {
  final r = await ref.read(earningsRepositoryProvider).summary();
  return switch (r) {
    Ok(value: final v) => v,
    Failure(message: final m) => throw EarningsLoadException(m),
  };
}

class LedgerState {
  const LedgerState({required this.entries, this.nextCursor, this.loadingMore = false, this.loadMoreError});
  final List<LedgerEntryDto> entries;
  final String? nextCursor;
  final bool loadingMore;
  final String? loadMoreError;

  LedgerState copyWith({List<LedgerEntryDto>? entries, String? nextCursor, bool clearCursor = false, bool? loadingMore, String? loadMoreError, bool clearError = false}) =>
      LedgerState(
        entries: entries ?? this.entries,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

/// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
/// dropped, so a late "Load more" can never splice stale rows into a fresh list.
@Riverpod(retry: noAutoRetry)
class LedgerController extends _$LedgerController {
  int _generation = 0;

  @override
  Future<LedgerState> build() async {
    final gen = ++_generation;
    final r = await ref.read(earningsRepositoryProvider).ledger();
    if (gen != _generation) {
      final existing = state.hasError ? null : state.value;
      if (existing != null) return existing;
    }
    return switch (r) {
      Ok(value: final p) => LedgerState(entries: p.entries, nextCursor: p.nextCursor),
      Failure(message: final m) => throw EarningsLoadException(m),
    };
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    final r = await ref.read(earningsRepositoryProvider).ledger();
    if (!ref.mounted || gen != _generation) return;
    state = switch (r) {
      Ok(value: final p) => AsyncData(LedgerState(entries: p.entries, nextCursor: p.nextCursor)),
      Failure(message: final m) => AsyncError(EarningsLoadException(m), StackTrace.current),
    };
  }

  Future<void> loadMore() async {
    final current = state.hasError ? null : state.value;
    if (current == null || current.loadingMore || current.nextCursor == null) return;
    final gen = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    final r = await ref.read(earningsRepositoryProvider).ledger(before: current.nextCursor);
    if (!ref.mounted || gen != _generation) return; // a refresh replaced the list meanwhile
    final now = state.hasError ? null : state.value;
    if (now == null) return;
    state = AsyncData(switch (r) {
      Ok(value: final p) => now.copyWith(entries: [...now.entries, ...p.entries], nextCursor: p.nextCursor, clearCursor: p.nextCursor == null, loadingMore: false),
      Failure(message: final m) => now.copyWith(loadingMore: false, loadMoreError: m),
    });
  }
}
