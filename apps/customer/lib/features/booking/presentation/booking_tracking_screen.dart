import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../home/presentation/home_screen.dart' show rupees;
import '../data/booking_repository.dart';
import 'booking_wizard_screen.dart' show formatScheduledSlot;

/// Human label for a booking `state`. Slice 3 stub: DISPATCHED/CREATED both
/// read as "finding a technician" (no live matching UI yet — Slice 4). Any
/// other state falls back to a title-cased rendering of the raw value so we
/// never show a blank badge for a state this stub doesn't yet know about.
String _stateLabel(String state) => switch (state) {
      'CREATED' || 'DISPATCHED' => 'Finding you a technician…',
      'ARRIVED' => 'Technician has arrived',
      'IN_PROGRESS' => 'Repair in progress',
      'COMPLETED' => 'Completed',
      'CANCELLED' => 'Cancelled',
      _ => state,
    };

/// The booking tracking STUB screen (`/booking/:id`) — the landing page right
/// after a booking is created. Renders the booking's current snapshot +
/// offers Cancel. Full state-driven live tracking (technician location,
/// handshake progress) is Slice 4; this screen only proves the booking was
/// created and lets the customer back out of it.
class BookingTrackingScreen extends ConsumerStatefulWidget {
  const BookingTrackingScreen({super.key, required this.bookingId});
  final String bookingId;

  @override
  ConsumerState<BookingTrackingScreen> createState() => _BookingTrackingScreenState();
}

class _BookingTrackingScreenState extends ConsumerState<BookingTrackingScreen> {
  late Future<Result<BookingDto>> _future = _load();
  bool _cancelling = false;

  Future<Result<BookingDto>> _load() => ref.read(bookingRepositoryProvider).get(widget.bookingId);

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final result = await ref.read(bookingRepositoryProvider).cancel(widget.bookingId);
    if (!mounted) return;
    switch (result) {
      case Ok():
        context.go('/home');
      case Failure(message: final m):
        setState(() => _cancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Booking status')),
      body: SafeArea(
        child: FutureBuilder<Result<BookingDto>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data!;
            return switch (result) {
              Failure() => _ErrorRetry(onRetry: () => setState(() => _future = _load())),
              Ok(value: final booking) => _Tracking(
                  booking: booking,
                  cancelling: _cancelling,
                  onCancel: _cancel,
                ),
            };
          },
        ),
      ),
    );
  }
}

class _Tracking extends StatelessWidget {
  const _Tracking({required this.booking, required this.cancelling, required this.onCancel});
  final BookingDto booking;
  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(booking.bookingNumber,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: FixCareColors.textPrimary)),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: FixCareColors.primaryTint,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(_stateLabel(booking.state),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
        ),
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
              _Row(label: 'Address', value: booking.address.id),
              _Row(label: 'Visit fee', value: rupees(booking.visitFeePaise)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FixCareColors.devHintFill,
            borderRadius: BorderRadius.circular(FixCareRadii.card),
            border: Border.all(color: FixCareColors.devHintBorder),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: FixCareColors.devHintText),
              SizedBox(width: 8),
              Expanded(
                child: Text('Live tracking coming soon',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: FixCareColors.devHintText)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('cancelBookingBtn'),
          onPressed: cancelling ? null : onCancel,
          child: cancelling
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cancel booking'),
        ),
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
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
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
