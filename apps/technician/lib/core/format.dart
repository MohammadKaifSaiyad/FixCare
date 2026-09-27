/// ₹ from integer paise, no trailing .00 when whole rupees.
String rupees(int paise) {
  final r = paise / 100;
  return r == r.roundToDouble() ? '₹${r.toInt()}' : '₹${r.toStringAsFixed(2)}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The fixed booking windows, keyed by their local start hour (mirrors the
/// customer app's `SlotWindow` in apps/customer/.../booking/presentation/slot.dart).
const _slotWindowLabels = {
  9: 'Morning · 9–12',
  12: 'Afternoon · 12–3',
  15: 'Evening · 3–6',
};

String _fullDateLabel(DateTime d) => '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

/// 12-hour clock time, e.g. "2:00 pm" (minutes always shown, no leading zero on the hour).
String _timeLabel(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final period = d.hour < 12 ? 'am' : 'pm';
  return '$hour12:$minute $period';
}

/// Formats a scheduledSlot ISO (UTC) string for display in local time (IST on
/// a technician's phone), e.g. "Wed, 10 Sep · Morning · 9–12" when the hour
/// matches one of the fixed booking windows (9/12/15), else just the actual
/// time, e.g. "Wed, 10 Sep · 2:00 pm". Ported from the customer app's
/// booking_wizard_screen.dart so both apps show the same slot the same way.
String formatScheduledSlot(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  // Only exactly-on-the-hour bookings land on a fixed window; anything else
  // (e.g. a 9:30 slot) shows its actual time rather than a misleading window
  // label (finding 9).
  final suffix = dt.minute == 0 ? (_slotWindowLabels[dt.hour] ?? _timeLabel(dt)) : _timeLabel(dt);
  return '${_fullDateLabel(dt)} · $suffix';
}
