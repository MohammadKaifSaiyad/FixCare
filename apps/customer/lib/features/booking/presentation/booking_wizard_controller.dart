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
}
