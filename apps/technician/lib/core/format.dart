/// ₹ from integer paise, no trailing .00 when whole rupees.
String rupees(int paise) {
  final r = paise / 100;
  return r == r.roundToDouble() ? '₹${r.toInt()}' : '₹${r.toStringAsFixed(2)}';
}
