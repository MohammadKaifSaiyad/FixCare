import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';

String _suffix(LedgerEntryDto e) {
  final b = e.bookingNumber;
  final s = e.serviceName;
  return [if (b != null) ' · $b', if (s != null) ' · $s'].join();
}

String _bookingSuffix(LedgerEntryDto e) {
  final b = e.bookingNumber;
  return b != null ? ' · $b' : '';
}

/// What the row is.
String ledgerRowLabel(LedgerEntryDto e) => switch (e.type) {
      'EARNING_CREDIT' => 'Earned${_suffix(e)}',
      'COMMISSION' => 'FixCare fee (20%)${_bookingSuffix(e)}',
      'CASH_COLLECTED' => 'Cash collected${_bookingSuffix(e)}',
      'CASH_DEBT_OFFSET' => 'Cash settled from earnings',
      'PAYOUT' => 'Paid to you',
      'DEBT_REPAYMENT' => 'Cash handed over',
      'DISPUTE_REVERSAL' => 'Customer refunded after a dispute${_bookingSuffix(e)}',
      _ => 'Other',
    };

/// Which running total the row moves ("Owed" = what FixCare owes them; "Cash" = cash they hold for FixCare).
String ledgerRowEffect(LedgerEntryDto e) {
  final amt = rupees(e.amountPaise);
  return switch (e.type) {
    'EARNING_CREDIT' => 'Owed +$amt',
    'CASH_COLLECTED' => 'Cash to hand over +$amt',
    'CASH_DEBT_OFFSET' => 'Owed −$amt · Cash −$amt',
    'PAYOUT' => 'Owed −$amt',
    'DEBT_REPAYMENT' => 'Cash −$amt',
    _ => 'Info · $amt', // COMMISSION, DISPUTE_REVERSAL, and any future type
  };
}

String _pendingSubtitle(PendingReleaseDto p) {
  if (p.onHold) return 'On hold — under dispute';
  final at = p.releasesAt;
  return at == null ? 'Releases soon' : 'Releases ${formatShortDateTime(at)}';
}

class StatementSection extends ConsumerWidget {
  const StatementSection({super.key, required this.pending});
  final List<PendingReleaseDto> pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          const Text('Pending', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final p in pending)
            ListTile(
              key: Key('pending_${p.bookingId}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${p.bookingNumber} · ${p.serviceName}'),
              subtitle: Text(_pendingSubtitle(p)),
              trailing: Text(rupees(p.amountPaise)),
            ),
          const SizedBox(height: 16),
        ],
        const Text('History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _history(ref, ledger),
      ],
    );
  }

  Widget _history(WidgetRef ref, AsyncValue<LedgerState> ledger) {
    // Error first: a manual AsyncError keeps the previous value (possibly stuck at loadingMore: true).
    if (ledger.hasError) {
      return Column(
        key: const Key('ledgerError'),
        children: [
          Text('${ledger.error}', textAlign: TextAlign.center, style: const TextStyle(color: FixCareColors.errorText)),
          TextButton(key: const Key('ledgerRetryBtn'), onPressed: () => ref.read(ledgerControllerProvider.notifier).refresh(), child: const Text('Retry')),
        ],
      );
    }
    final s = ledger.value;
    if (s == null) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
    if (s.entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No money movements yet', key: Key('ledgerEmpty'), style: TextStyle(color: FixCareColors.textMuted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in s.entries)
          ListTile(
            key: Key('ledgerRow_${e.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(ledgerRowLabel(e)),
            subtitle: Text('${ledgerRowEffect(e)} · ${formatShortDate(e.createdAt)}'),
          ),
        if (s.loadMoreError case final err?) Text(err, style: const TextStyle(color: FixCareColors.errorText)),
        if (s.nextCursor != null)
          TextButton(
            key: const Key('loadMoreBtn'),
            onPressed: s.loadingMore ? null : () => ref.read(ledgerControllerProvider.notifier).loadMore(),
            child: s.loadingMore ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
          ),
      ],
    );
  }
}
