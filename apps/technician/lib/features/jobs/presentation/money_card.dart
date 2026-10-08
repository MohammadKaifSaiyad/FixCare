import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../earnings/presentation/earnings_providers.dart';

/// Top of jobs home: what FixCare owes them, cash they hold, and whether new jobs are paused. Tap → /earnings.
/// A failed load never blocks the job lists — it shows a one-line Retry.
class MoneyCard extends ConsumerWidget {
  const MoneyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(earningsSummaryProvider);
    // Error first (a manual AsyncError keeps the previous value — never show stale numbers over a failure),
    // then any value, even while reloading (no blank flash); the spacer only before the first load.
    if (async.hasError) {
      final e = async.error;
      return Row(
        key: const Key('moneyCardError'),
        children: [
          Expanded(
            child: Text(
              'Couldn\'t load earnings: $e',
              style: const TextStyle(color: FixCareColors.textMuted),
            ),
          ),
          TextButton(
            key: const Key('moneyCardRetryBtn'),
            onPressed: () => ref.invalidate(earningsSummaryProvider),
            child: const Text('Retry'),
          ),
        ],
      );
    }
    final s = async.value;
    if (s == null) return const SizedBox(height: 56);
    return InkWell(
      key: const Key('moneyCard'),
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      onTap: () async {
        await context.push('/earnings');
        if (!context.mounted) return;
        ref.invalidate(
          earningsSummaryProvider,
        ); // back from Earnings → fresh numbers
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixCareColors.surface,
          border: Border.all(color: FixCareColors.border),
          borderRadius: BorderRadius.circular(FixCareRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Owed to you ${rupees(s.owedPaise)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            if (s.pendingPaise > 0)
              Text(
                '${rupees(s.pendingPaise)} pending',
                style: const TextStyle(color: FixCareColors.textSecondary),
              ),
            if (s.cashDebtPaise > 0)
              Text('Cash to hand over ${rupees(s.cashDebtPaise)}'),
            if (s.acceptBlocked)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'New jobs are paused until your cash is settled (${rupees(s.cashDebtPaise)} of ${rupees(s.cashDebtLimitPaise)} limit)',
                  style: const TextStyle(
                    color: FixCareColors.errorText,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
