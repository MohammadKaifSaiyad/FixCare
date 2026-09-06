import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../address/data/address_repository.dart';

/// Joins a booking's `address.id` (the backend BookingDto carries only the id)
/// to a human label from the customer's own address list. Falls back to the
/// raw id when the address isn't found (deleted) or the list can't be fetched —
/// never throws, so the tracking screen always has something to show.
final bookingAddressLabelProvider = FutureProvider.family<String, String>((ref, addressId) async {
  final r = await ref.read(addressRepositoryProvider).list();
  return switch (r) {
    Ok(value: final list) => _labelFor(list, addressId),
    Failure() => addressId,
  };
});

String _labelFor(List<AddressDto> list, String addressId) {
  for (final a in list) {
    if (a.id == addressId) return '${a.label} · ${a.line1}, ${a.pincode}';
  }
  return addressId;
}
