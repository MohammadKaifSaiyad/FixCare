import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'booking_wizard_controller.freezed.dart';
part 'booking_wizard_controller.g.dart';

@freezed
abstract class BookingWizardState with _$BookingWizardState {
  const factory BookingWizardState({required String serviceId, String? addressId, String? scheduledSlot}) =
      _BookingWizardState;
}

@riverpod
class BookingWizard extends _$BookingWizard {
  @override
  BookingWizardState build(String serviceId) => BookingWizardState(serviceId: serviceId);

  void setAddress(String id) => state = state.copyWith(addressId: id);
  void setSlot(String iso) => state = state.copyWith(scheduledSlot: iso);

  // Explicit clear: `copyWith(scheduledSlot: null)` on a freezed class with a
  // nullable field is a no-op (freezed treats a null argument as "don't
  // change this field"), so we must rebuild state directly to actually null it.
  void clearSlot() => state = BookingWizardState(
        serviceId: state.serviceId,
        addressId: state.addressId,
        scheduledSlot: null,
      );
}
