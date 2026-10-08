import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';

/// Request-payout button + the latest request's status. The amount is always the backend's net figure.
class PayoutSection extends ConsumerStatefulWidget {
  const PayoutSection({super.key, required this.summary});
  final EarningsSummaryDto summary;

  @override
  ConsumerState<PayoutSection> createState() => _PayoutSectionState();
}

class _PayoutSectionState extends ConsumerState<PayoutSection> {
  bool _busy = false;

  Future<void> _request() async {
    final s = widget.summary;
    final cash = s.cashDebtPaise > 0 ? ' Your ${rupees(s.cashDebtPaise)} cash is settled first.' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request payout'),
        content: Text('Request ${rupees(s.netPayoutPaise)}? FixCare transfers it and confirms here.$cash'),
        actions: [
          TextButton(key: const Key('cancelPayoutBtn'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('confirmPayoutBtn'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(earningsRepositoryProvider).requestPayout();
      if (!mounted) return;
      if (r case Failure(:final message)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      ref.invalidate(earningsSummaryProvider); // either way: show the server's current state
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st, library: 'fixcare earnings', context: ErrorDescription('requesting a payout')));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final latest = s.latestPayoutRequest;
    final open = latest?.status == 'REQUESTED';
    final eligible = !open && s.netPayoutPaise >= s.payoutMinPaise;
    final String? status;
    if (latest == null) {
      status = null;
    } else {
      status = switch (latest.status) {
        'REQUESTED' => '${rupees(latest.amountPaise)} requested on ${formatShortDate(latest.requestedAt)} — FixCare will transfer it soon',
        'PAID' => switch (latest.reviewedAt) {
            final at? => '${rupees(latest.paidPaise ?? latest.amountPaise)} paid on ${formatShortDate(at)}',
            null => null,
          },
        'REJECTED' => 'Not paid: ${latest.reviewNote ?? ''}',
        _ => null,
      };
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(status, key: const Key('payoutStatusText'), style: const TextStyle(fontSize: 14, color: FixCareColors.textSecondary, height: 1.4)),
          ),
        if (!open) ...[
          FilledButton(
            key: const Key('requestPayoutBtn'),
            onPressed: eligible && !_busy ? _request : null,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Request payout of ${rupees(s.netPayoutPaise)}'),
          ),
          if (!eligible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Payouts start at ${rupees(s.payoutMinPaise)}', key: const Key('payoutMinText'), style: const TextStyle(color: FixCareColors.textMuted)),
            ),
        ],
      ],
    );
  }
}
