import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/booking_repository.dart';
import 'tracking_phase.dart';

part 'booking_tracking_controller.g.dart';

const trackingPollInterval = Duration(seconds: 5);

@riverpod
class BookingTracking extends _$BookingTracking {
  Timer? _timer;
  late String _bookingId;

  @override
  Future<BookingDto> build(String bookingId) async {
    _bookingId = bookingId;
    ref.onDispose(() => _timer?.cancel());
    final dto = await _fetchOrThrow(bookingId);
    _arm(bookingId, dto);
    return dto;
  }

  Future<BookingDto> _fetchOrThrow(String bookingId) async {
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    return switch (r) {
      Ok(value: final dto) => dto,
      Failure(message: final m) => throw Exception(m),
    };
  }

  void _arm(String bookingId, BookingDto dto) {
    _timer?.cancel();
    if (isTerminal(dto)) return;
    _timer = Timer.periodic(trackingPollInterval, (_) => _poll(bookingId));
  }

  Future<void> _poll(String bookingId) async {
    if (!ref.mounted) return;
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final dto):
        state = AsyncData(dto);
        _arm(bookingId, dto); // cancels itself if now terminal
      case Failure():
        // keep-last-good: leave state as-is, retry next tick.
        break;
    }
  }

  /// Forced immediate reload (e.g. after a gate succeeds or on app resume).
  /// Keeps last-good on failure; never flashes AsyncLoading.
  Future<void> refetch() async {
    final bookingId = _bookingId;
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final dto):
        state = AsyncData(dto);
        _arm(bookingId, dto);
      case Failure():
        break;
    }
  }
}
