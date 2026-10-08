import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';
import 'payout_section.dart';
import 'statement_section.dart';

class EarningsScreen extends ConsumerStatefulWidget {
  const EarningsScreen({super.key});

  @override
  ConsumerState<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends ConsumerState<EarningsScreen> {
  @override
  void initState() {
    super.initState();
    // One fresh fetch per open: a summary cached from the jobs-home card may be stale. If the provider is still
    // on its first load that load IS the fresh fetch — don't double it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!ref.read(earningsSummaryProvider).isLoading) ref.invalidate(earningsSummaryProvider);
    });
  }

  /// Reloads the summary and the statement; never throws (failures surface in the sections themselves).
  Future<void> _refresh() async {
    await Future.wait([
      ref.read(ledgerControllerProvider.notifier).refresh().then((_) {}, onError: (_) {}),
      ref.refresh(earningsSummaryProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(earningsSummaryProvider);
    return Scaffold(
      key: const Key('earningsScreen'),
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (async.hasError)
                Column(
                  key: const Key('earningsError'),
                  children: [
                    Text('${async.error}', textAlign: TextAlign.center, style: const TextStyle(color: FixCareColors.errorText)),
                    TextButton(key: const Key('earningsRetryBtn'), onPressed: () => ref.invalidate(earningsSummaryProvider), child: const Text('Retry')),
                  ],
                )
              else if (async.value case final s?)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_SummaryBlock(summary: s), const SizedBox(height: 20), PayoutSection(summary: s)],
                )
              else
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: 24),
              StatementSection(key: const Key('statementSlot'), pending: async.hasError ? const [] : (async.value?.pending ?? const [])),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.summary});
  final EarningsSummaryDto summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: FixCareColors.surface, border: Border.all(color: FixCareColors.border), borderRadius: BorderRadius.circular(FixCareRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Owed to you', style: TextStyle(color: FixCareColors.textMuted)),
          Text(rupees(s.owedPaise), key: const Key('owedText'), style: Theme.of(context).textTheme.headlineMedium),
          if (s.pendingPaise > 0) Text('${rupees(s.pendingPaise)} pending', key: const Key('pendingTotalText'), style: const TextStyle(color: FixCareColors.textSecondary)),
          if (s.cashDebtPaise > 0) ...[
            const SizedBox(height: 12),
            Text('Cash to hand over ${rupees(s.cashDebtPaise)}', key: const Key('cashDebtText'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (s.acceptBlocked) ...[
            const SizedBox(height: 8),
            Text(
              'New jobs are paused until your cash is settled (${rupees(s.cashDebtPaise)} of ${rupees(s.cashDebtLimitPaise)} limit)',
              key: const Key('pausedText'),
              style: const TextStyle(color: FixCareColors.errorText, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
