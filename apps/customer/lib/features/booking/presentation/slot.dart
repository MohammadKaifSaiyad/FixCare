enum SlotWindow { morning, afternoon, evening }

extension SlotWindowX on SlotWindow {
  int get startHour => switch (this) {
        SlotWindow.morning => 9,
        SlotWindow.afternoon => 12,
        SlotWindow.evening => 15,
      };
  String get label => switch (this) {
        SlotWindow.morning => 'Morning · 9–12',
        SlotWindow.afternoon => 'Afternoon · 12–3',
        SlotWindow.evening => 'Evening · 3–6',
      };
}

/// A UTC ISO 8601 string for [day] at [window]'s start hour in local time, or null if that instant
/// is not strictly in the future (the backend requires scheduledSlot > now).
String? slotToIso(DateTime day, SlotWindow window, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = DateTime(day.year, day.month, day.day, window.startHour);
  if (!local.isAfter(n)) return null;
  return local.toUtc().toIso8601String();
}
