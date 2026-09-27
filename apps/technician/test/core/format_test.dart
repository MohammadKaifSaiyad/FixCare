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
}
