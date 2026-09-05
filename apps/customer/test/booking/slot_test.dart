import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/features/booking/presentation/slot.dart';

void main() {
  test('morning window maps to 09:00 local and returns a future ISO', () {
    final now = DateTime(2026, 9, 8, 8, 0); // 8am, before the 9am morning slot today
    final iso = slotToIso(DateTime(2026, 9, 8), SlotWindow.morning, now: now);
    expect(iso, isNotNull);
    final dt = DateTime.parse(iso!);
    expect(dt.isAfter(now), isTrue);
    // 9am local on the 8th
    expect(DateTime(2026, 9, 8, 9, 0).toUtc().toIso8601String(), iso);
  });

  test('a window whose start hour has already passed today returns null', () {
    final now = DateTime(2026, 9, 8, 13, 0); // 1pm — morning (9) already gone
    expect(slotToIso(DateTime(2026, 9, 8), SlotWindow.morning, now: now), isNull);
  });

  test('afternoon (12) / evening (15) start hours', () {
    expect(SlotWindow.afternoon.startHour, 12);
    expect(SlotWindow.evening.startHour, 15);
  });

  test('a future day is always valid regardless of window', () {
    final now = DateTime(2026, 9, 8, 23, 0);
    expect(slotToIso(DateTime(2026, 9, 9), SlotWindow.morning, now: now), isNotNull);
  });
}
