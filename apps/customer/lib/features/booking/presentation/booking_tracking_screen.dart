import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../home/presentation/home_screen.dart' show rupees;
import '../data/booking_repository.dart';
import 'booking_address_label.dart';
import 'booking_tracking_controller.dart';
import 'booking_wizard_screen.dart' show formatScheduledSlot;
import 'pay_view.dart';
import 'razorpay_checkout.dart';
import 'tracking_phase.dart';

/// The live booking tracking screen (`/booking/:id`). Watches the polling
/// controller (Task 4) for the booking's current snapshot and renders:
///  - a milestone timeline derived from [phaseFor],
///  - an info card (service / time / address / visit fee / technician),
///  - a phase-specific gate card that drives the three customer gates
///    (arrival code, diagnosis approve/decline, completion OTP),
///  - a Cancel button, only while the booking is still cancellable.
///
/// The controller owns the 5s poll timer; this screen holds an
/// [AppLifecycleListener] so a foreground-resume forces an immediate refetch.
class BookingTrackingScreen extends ConsumerStatefulWidget {
  const BookingTrackingScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends ConsumerState<BookingTrackingScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    if (!mounted) return;
    ref.read(bookingTrackingProvider(widget.bookingId).notifier).refetch();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refetch() =>
      ref.read(bookingTrackingProvider(widget.bookingId).notifier).refetch();

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final result = await ref.read(bookingRepositoryProvider).cancel(widget.bookingId);
    if (!mounted) return;
    switch (result) {
      case Ok():
        context.go('/home');
      case Failure(message: final m):
        setState(() => _cancelling = false);
        _snack(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(bookingTrackingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: const Text('Booking status')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ErrorRetry(
            onRetry: () => ref.invalidate(bookingTrackingProvider(widget.bookingId)),
          ),
          data: (booking) => _Tracking(
            booking: booking,
            cancelling: _cancelling,
            onCancel: _cancel,
            onRefetch: _refetch,
            onSnack: _snack,
          ),
        ),
      ),
    );
  }
}

class _Tracking extends ConsumerWidget {
  const _Tracking({
    required this.booking,
    required this.cancelling,
    required this.onCancel,
    required this.onRefetch,
    required this.onSnack,
  });
  final BookingDto booking;
  final bool cancelling;
  final VoidCallback onCancel;
  final Future<void> Function() onRefetch;
  final void Function(String message) onSnack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(bookingAddressLabelProvider(booking.address.id));
    final addressLabel = label.maybeWhen(data: (l) => l, orElse: () => booking.address.id);
    final tech = booking.technician;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          booking.bookingNumber,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: FixCareColors.textPrimary),
        ),
        const SizedBox(height: 10),
        _PhaseBadge(phase: phaseFor(booking)),
        const SizedBox(height: 20),
        _Timeline(phase: phaseFor(booking), paid: payViewFor(booking) == PayView.paid),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FixCareColors.surface,
            borderRadius: BorderRadius.circular(FixCareRadii.card),
            border: Border.all(color: FixCareColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Row(label: 'Service', value: booking.service.name),
              _Row(label: 'Time', value: formatScheduledSlot(booking.scheduledSlot)),
              _Row(label: 'Address', value: addressLabel),
              _Row(label: 'Visit fee', value: rupees(booking.visitFeePaise)),
              if (tech != null) ...[
                const Divider(height: 24, color: FixCareColors.border),
                _Row(label: 'Technician', value: tech.name),
                _Row(label: 'Phone', value: tech.maskedPhone),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _GateCard(booking: booking, onRefetch: onRefetch, onSnack: onSnack),
        if (isCancellable(booking)) ...[
          const SizedBox(height: 24),
          OutlinedButton(
            key: const Key('cancelBookingBtn'),
            onPressed: cancelling ? null : onCancel,
            child: cancelling
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Cancel booking'),
          ),
        ],
      ],
    );
  }
}

/// Selects the gate/summary widget for the current phase.
class _GateCard extends StatelessWidget {
  const _GateCard({required this.booking, required this.onRefetch, required this.onSnack});
  final BookingDto booking;
  final Future<void> Function() onRefetch;
  final void Function(String message) onSnack;

  @override
  Widget build(BuildContext context) {
    switch (gateFor(booking)) {
      case TrackingGate.arrival:
        return _ArrivalCard(bookingId: booking.id, onRefetch: onRefetch);
      case TrackingGate.decision:
        return _DiagnosisCard(booking: booking, onRefetch: onRefetch, onSnack: onSnack);
      case TrackingGate.completion:
        return _CompletionCard(bookingId: booking.id, onSnack: onSnack);
      case TrackingGate.none:
        return _PhaseSummary(booking: booking, onRefetch: onRefetch, onSnack: onSnack);
    }
  }
}

// ── Arrival gate ────────────────────────────────────────────────────────────

class _ArrivalCard extends ConsumerStatefulWidget {
  const _ArrivalCard({required this.bookingId, required this.onRefetch});
  final String bookingId;
  final Future<void> Function() onRefetch;

  @override
  ConsumerState<_ArrivalCard> createState() => _ArrivalCardState();
}

class _ArrivalCardState extends ConsumerState<_ArrivalCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final code = _controller.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your technician.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref.read(bookingRepositoryProvider).confirmArrival(widget.bookingId, code);
    if (!mounted) return;
    switch (result) {
      case Ok():
        await widget.onRefetch();
        if (mounted) setState(() => _busy = false);
      case Failure(message: final m):
        setState(() {
          _busy = false;
          _error = m;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Confirm your technician arrived',
      children: [
        const Text(
          'Enter the 6-digit code your technician shows you.',
          style: TextStyle(fontSize: 13.5, color: FixCareColors.textMuted, height: 1.4),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('arrivalCodeField'),
          controller: _controller,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '123456', counterText: ''),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 13, color: FixCareColors.errorText)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('confirmArrivalBtn'),
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm arrival'),
        ),
      ],
    );
  }
}

// ── Diagnosis / decision gate ───────────────────────────────────────────────

class _DiagnosisCard extends ConsumerStatefulWidget {
  const _DiagnosisCard({required this.booking, required this.onRefetch, required this.onSnack});
  final BookingDto booking;
  final Future<void> Function() onRefetch;
  final void Function(String message) onSnack;

  @override
  ConsumerState<_DiagnosisCard> createState() => _DiagnosisCardState();
}

class _DiagnosisCardState extends ConsumerState<_DiagnosisCard> {
  bool _busy = false;

  Future<void> _approve() async {
    setState(() => _busy = true);
    final result = await ref.read(bookingRepositoryProvider).approve(widget.booking.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        await widget.onRefetch();
        if (mounted) setState(() => _busy = false);
      case Failure(message: final m):
        setState(() => _busy = false);
        widget.onSnack(m);
    }
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline this repair?'),
        content: Text(
          "You'll still owe the ${rupees(widget.booking.visitFeePaise)} visit fee. Decline this repair?",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep repair')),
          TextButton(
            key: const Key('declineConfirmBtn'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(bookingRepositoryProvider).decline(widget.booking.id);
    if (!mounted) return;
    switch (result) {
      case Ok():
        await widget.onRefetch();
        if (mounted) setState(() => _busy = false);
      case Failure(message: final m):
        setState(() => _busy = false);
        widget.onSnack(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    return _CardShell(
      title: 'Approve the repair',
      children: [
        if (b.diagnosis != null)
          Text(
            b.diagnosis!.issueName,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary),
          ),
        if (b.parts.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final p in b.parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${p.name} × ${p.qty}',
                        style: const TextStyle(fontSize: 13.5, color: FixCareColors.textSecondary)),
                  ),
                  Text(rupees(p.ceilingPricePaise),
                      style: const TextStyle(fontSize: 13.5, color: FixCareColors.textSecondary)),
                ],
              ),
            ),
        ],
        const Divider(height: 24, color: FixCareColors.border),
        Row(
          children: [
            const Expanded(
              child: Text('Total payable',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
            ),
            Text(
              rupees(b.estimate.totalPayablePaise),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: FixCareColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('approveRepairBtn'),
          onPressed: _busy ? null : _approve,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Approve repair'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('declineRepairBtn'),
          onPressed: _busy ? null : _decline,
          child: const Text('Decline'),
        ),
      ],
    );
  }
}

// ── Completion gate ─────────────────────────────────────────────────────────

class _CompletionCard extends ConsumerStatefulWidget {
  const _CompletionCard({required this.bookingId, required this.onSnack});
  final String bookingId;
  final void Function(String message) onSnack;

  @override
  ConsumerState<_CompletionCard> createState() => _CompletionCardState();
}

class _CompletionCardState extends ConsumerState<_CompletionCard> {
  bool _busy = false;
  bool _sent = false;
  String? _devOtp;

  Future<void> _request() async {
    setState(() => _busy = true);
    final result = await ref.read(bookingRepositoryProvider).requestCompletionOtp(widget.bookingId);
    if (!mounted) return;
    switch (result) {
      case Ok(value: final dto):
        setState(() {
          _busy = false;
          _sent = true;
          _devOtp = dto.devOtp;
        });
      case Failure(message: final m):
        setState(() => _busy = false);
        widget.onSnack(m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      title: 'Confirm the work is done',
      children: [
        if (!_sent)
          const Text(
            'Once you confirm, we text you a 6-digit code to hand to your technician.',
            style: TextStyle(fontSize: 13.5, color: FixCareColors.textMuted, height: 1.4),
          )
        else ...[
          const Text(
            'We texted a 6-digit code to your phone — read it to your technician.',
            style: TextStyle(fontSize: 13.5, color: FixCareColors.textSecondary, height: 1.4),
          ),
          if (!kReleaseMode && _devOtp != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('devCompletionOtp'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: FixCareColors.devHintFill,
                borderRadius: BorderRadius.circular(FixCareRadii.field),
                border: Border.all(color: FixCareColors.devHintBorder),
              ),
              child: Text(
                _devOtp!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                  color: FixCareColors.devHintText,
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('confirmCompletionBtn'),
          onPressed: _busy ? null : _request,
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_sent ? 'Resend code' : 'Confirm work is done'),
        ),
      ],
    );
  }
}

// ── Non-gate summaries (payment / dispute / terminal) ───────────────────────

class _PhaseSummary extends StatelessWidget {
  const _PhaseSummary({required this.booking, required this.onRefetch, required this.onSnack});
  final BookingDto booking;
  final Future<void> Function() onRefetch;
  final void Function(String message) onSnack;

  @override
  Widget build(BuildContext context) {
    // Payment drives the pay card for any payable/paid booking — this also
    // covers a DECLINED_BY_CUSTOMER booking that still owes the visit fee (or
    // has already paid it). `none` falls through to the terminal/dispute copy.
    if (payViewFor(booking) != PayView.none) {
      return _PayCard(booking: booking, onRefetch: onRefetch, onSnack: onSnack);
    }

    final phase = phaseFor(booking);
    final dispute = booking.dispute;
    if (phase == TrackingPhase.disputed && dispute != null) {
      return _CardShell(
        title: 'Dispute open',
        children: [
          _Row(label: 'Status', value: dispute.status),
          if (dispute.outcome != null) _Row(label: 'Outcome', value: dispute.outcome!),
          if (dispute.refundPaise != null) _Row(label: 'Refund', value: rupees(dispute.refundPaise!)),
        ],
      );
    }
    if (phase == TrackingPhase.completed ||
        phase == TrackingPhase.cancelled ||
        phase == TrackingPhase.declined) {
      return _CardShell(
        title: switch (phase) {
          TrackingPhase.completed => 'All done',
          TrackingPhase.cancelled => 'Booking cancelled',
          _ => 'Repair declined',
        },
        children: [
          Text(
            switch (phase) {
              TrackingPhase.completed => 'This booking is complete. Thank you.',
              TrackingPhase.cancelled => 'This booking was cancelled.',
              _ => 'This repair was declined.',
            },
            style: const TextStyle(fontSize: 13.5, color: FixCareColors.textMuted, height: 1.4),
          ),
        ],
      );
    }
    // Payment phase with no pay-view (e.g. PAYMENT_RECEIVED whose summary lags —
    // payment null or a non-captured attempt): render a neutral, DTO-derived
    // status card, never a blank box. Do NOT claim "paid" — only a CAPTURED
    // payment reads as paid (the `payViewFor == paid` branch above).
    if (phase == TrackingPhase.payment) {
      return const _CardShell(
        title: 'Payment received',
        children: [
          Text(
            'We have your payment and are finishing up. This can take a moment.',
            style: TextStyle(fontSize: 13.5, color: FixCareColors.textMuted, height: 1.4),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

// ── Payment card (Slice 5) ──────────────────────────────────────────────────

/// Drives the customer's payment: pick UPI (Razorpay, keyId-gated) or cash
/// (OTP handed to the technician). A successful checkout is NOT "paid" — the
/// poll confirms via webhook (Golden Rules 1-3). The customer only reads the
/// cash OTP aloud; there is no OTP submit here.
class _PayCard extends ConsumerStatefulWidget {
  const _PayCard({required this.booking, required this.onRefetch, required this.onSnack});
  final BookingDto booking;
  final Future<void> Function() onRefetch;
  final void Function(String message) onSnack;

  @override
  ConsumerState<_PayCard> createState() => _PayCardState();
}

class _PayCardState extends ConsumerState<_PayCard> {
  bool _busy = false;
  String? _cashDevOtp;

  Future<void> _payUpi() async {
    setState(() => _busy = true);
    final r = await ref.read(bookingRepositoryProvider).initiatePayment(widget.booking.id);
    if (!mounted) return;
    switch (r) {
      case Failure(message: final m):
        setState(() => _busy = false);
        widget.onSnack(m);
      case Ok(value: final init):
        if (init.keyId == null) {
          // UPI unavailable server-side — never open the plugin; steer to cash.
          setState(() => _busy = false);
          widget.onSnack("UPI isn't available right now — please pay by cash.");
          return;
        }
        final outcome = await ref.read(razorpayCheckoutProvider).open(
              keyId: init.keyId!,
              orderId: init.orderId,
              amountPaise: init.amountPaise,
              name: 'FixCare',
              description: widget.booking.service.name,
            );
        if (!mounted) return;
        switch (outcome) {
          case CheckoutSuccess():
            // Success ≠ paid. Keep the buttons disabled ACROSS the refetch so a
            // second tap can't start a second order for an already-paid booking
            // (the refetch may keep-last-good, or the backend may not yet show
            // payment=CREATED). Only clear _busy once the refetch resolves.
            await widget.onRefetch();
            if (mounted) setState(() => _busy = false);
          case CheckoutFailed(message: final m):
            // Real failure — re-enable so the customer can retry.
            setState(() => _busy = false);
            widget.onSnack(m);
          case CheckoutDismissed():
            // Benign cancel — re-enable, stay quiet (no snack).
            setState(() => _busy = false);
        }
    }
  }

  Future<void> _payCash() async {
    setState(() => _busy = true);
    final r = await ref.read(bookingRepositoryProvider).initiateCashPayment(widget.booking.id);
    if (!mounted) return;
    switch (r) {
      case Failure(message: final m):
        setState(() => _busy = false);
        widget.onSnack(m);
      case Ok(value: final init):
        setState(() {
          _busy = false;
          _cashDevOtp = init.devOtp;
        });
        // Refetch so the DTO's payment becomes CREATED/CASH → cashPending.
        await widget.onRefetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    switch (payViewFor(b)) {
      case PayView.choose:
        final failed = b.payment?.status == 'FAILED';
        return _CardShell(
          title: 'Payment',
          children: [
            if (failed) ...[
              const Text(
                "Last payment didn't go through — try again.",
                style: TextStyle(fontSize: 13.5, color: FixCareColors.errorText, height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                const Expanded(
                  child: Text('Amount payable',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
                ),
                Text(
                  rupees(payableAmountPaise(b)),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: FixCareColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('payUpiBtn'),
              onPressed: _busy ? null : _payUpi,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Pay by UPI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('payCashBtn'),
              onPressed: _busy ? null : _payCash,
              child: const Text('Pay cash'),
            ),
          ],
        );
      case PayView.upiPending:
        return _CardShell(
          title: 'Payment',
          children: [
            Row(
              children: [
                const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Confirming your payment…',
                    style: const TextStyle(
                        fontSize: 13.5, color: FixCareColors.textSecondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        );
      case PayView.cashPending:
        return _CardShell(
          title: 'Pay cash',
          children: [
            const Text(
              'Read this 6-digit code to your technician.',
              style: TextStyle(fontSize: 13.5, color: FixCareColors.textSecondary, height: 1.4),
            ),
            if (!kReleaseMode && _cashDevOtp != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('devCashOtp'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: FixCareColors.devHintFill,
                  borderRadius: BorderRadius.circular(FixCareRadii.field),
                  border: Border.all(color: FixCareColors.devHintBorder),
                ),
                child: Text(
                  _cashDevOtp!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w700,
                    color: FixCareColors.devHintText,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Waiting for your technician to confirm…',
              style: TextStyle(fontSize: 13, color: FixCareColors.textMuted, height: 1.4),
            ),
          ],
        );
      case PayView.paid:
        final p = b.payment;
        return _CardShell(
          title: 'Paid',
          children: [
            Text(
              p == null ? '✓ Paid' : '✓ ${p.method} · ${rupees(p.amountPaise)}',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.success),
            ),
          ],
        );
      case PayView.none:
        return const SizedBox.shrink();
    }
  }
}

// ── Shared building blocks ──────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  const _CardShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.card),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: FixCareColors.textPrimary)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _PhaseBadge extends StatelessWidget {
  const _PhaseBadge({required this.phase});
  final TrackingPhase phase;

  static const _labels = <TrackingPhase, String>{
    TrackingPhase.finding: 'Finding you a technician…',
    TrackingPhase.assigned: 'Technician assigned',
    TrackingPhase.enRoute: 'Technician on the way',
    TrackingPhase.arrived: 'Technician has arrived',
    TrackingPhase.diagnosis: 'Diagnosis ready',
    TrackingPhase.repairing: 'Repair in progress',
    TrackingPhase.confirmCompletion: 'Confirm the work is done',
    TrackingPhase.payment: 'Payment',
    TrackingPhase.disputed: 'Dispute open',
    TrackingPhase.completed: 'Completed',
    TrackingPhase.cancelled: 'Cancelled',
    TrackingPhase.declined: 'Repair declined',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: FixCareColors.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _labels[phase] ?? '',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: FixCareColors.primary),
      ),
    );
  }
}

/// A compact milestone timeline. The current phase maps to one of the ordered
/// milestones; everything up to and including it reads as "done/active".
class _Timeline extends StatelessWidget {
  const _Timeline({required this.phase, this.paid = false});
  final TrackingPhase phase;

  /// Whether payment is actually captured (`payViewFor == paid`). The payment
  /// phase alone does NOT mean paid — an unpaid payable booking sits in the
  /// payment phase while the pay card still asks the customer to pay, so "Paid"
  /// must stay un-highlighted until capture.
  final bool paid;

  static const _milestones = ['Booked', 'Assigned', 'Arrived', 'Diagnosis', 'Repair', 'Done', 'Paid'];

  static const _paidIndex = 6; // 'Paid'
  static const _doneIndex = 5; // 'Done' — the step before 'Paid'

  /// The index of the currently-active milestone for a phase.
  int get _activeIndex => switch (phase) {
        TrackingPhase.finding => 0,
        TrackingPhase.assigned || TrackingPhase.enRoute => 1,
        TrackingPhase.arrived => 2,
        TrackingPhase.diagnosis => 3,
        TrackingPhase.repairing => 4,
        TrackingPhase.confirmCompletion => 5,
        // Payment due but not yet captured stops at 'Done'; only a CAPTURED
        // payment lights 'Paid'. A CLOSED booking is fully paid.
        TrackingPhase.payment => paid ? _paidIndex : _doneIndex,
        TrackingPhase.completed => _paidIndex,
        // Off-path terminal/dispute states: don't highlight a milestone.
        TrackingPhase.disputed || TrackingPhase.cancelled || TrackingPhase.declined => -1,
      };

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Row(
      children: [
        for (var i = 0; i < _milestones.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active >= 0 && i <= active ? FixCareColors.primary : FixCareColors.border,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _milestones[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: i == active ? FontWeight.w700 : FontWeight.w500,
                    color: active >= 0 && i <= active
                        ? FixCareColors.textPrimary
                        : FixCareColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13, color: FixCareColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 32, color: FixCareColors.errorBorder),
          const SizedBox(height: 10),
          const Text('Something went wrong.',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
