import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/format.dart';

void main() {
  group('formatScheduledSlot', () {
    // Build the ISO string from a LOCAL DateTime (toUtc) rather than a fixed
    // "Z" literal so the expected local hour is right in any test-machine
    // timezone (formatScheduledSlot converts back with .toLocal() — IST on a
    // technician's phone).
    String iso(int hour, [int minute = 0]) => DateTime(2026, 9, 10, hour, minute).toUtc().toIso8601String();

    test('the 9:00 window -> "Thu, 10 Sep · Morning · 9–12"', () {
      expect(formatScheduledSlot(iso(9)), 'Thu, 10 Sep · Morning · 9–12');
    });

    test('the 12:00 and 15:00 windows -> Afternoon / Evening labels', () {
      expect(formatScheduledSlot(iso(12)), 'Thu, 10 Sep · Afternoon · 12–3');
      expect(formatScheduledSlot(iso(15)), 'Thu, 10 Sep · Evening · 3–6');
    });

    test('an hour matching no window -> the actual 12-hour time', () {
      expect(formatScheduledSlot(iso(14)), 'Thu, 10 Sep · 2:00 pm');
      expect(formatScheduledSlot(iso(0, 30)), 'Thu, 10 Sep · 12:30 am');
      expect(formatScheduledSlot(iso(10, 5)), 'Thu, 10 Sep · 10:05 am');
    });

    test('a window hour with a non-zero minute -> the actual time, not the window label', () {
      expect(formatScheduledSlot(iso(9, 30)), 'Thu, 10 Sep · 9:30 am');
      expect(formatScheduledSlot(iso(12, 15)), 'Thu, 10 Sep · 12:15 pm');
      expect(formatScheduledSlot(iso(15, 1)), 'Thu, 10 Sep · 3:01 pm');
    });

    test('a UTC instant is shown in local time, not as the raw ISO string', () {
      final raw = iso(9);
      expect(raw.endsWith('Z'), isTrue);
      expect(formatScheduledSlot(raw), isNot(contains('2026')));
      expect(formatScheduledSlot(raw), isNot(contains('.000')));
    });
  });

  test('rupees: whole rupees drop the .00', () {
    expect(rupees(9900), '₹99');
    expect(rupees(12345), '₹123.45');
  });

  test('formatShortDate / formatShortDateTime render local day + month (+ time)', () {
    final d = DateTime(2026, 10, 5, 14, 0).toUtc().toIso8601String();
    expect(formatShortDate(d), '5 Oct');
    expect(formatShortDateTime(d), '5 Oct, 2:00 pm');
    final midnight = DateTime(2026, 10, 3, 0, 5).toUtc().toIso8601String();
    expect(formatShortDateTime(midnight), '3 Oct, 12:05 am');
  });
}
