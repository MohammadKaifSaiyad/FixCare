import 'package:freezed_annotation/freezed_annotation.dart';
part 'booking_dtos.freezed.dart';
part 'booking_dtos.g.dart';

@freezed
abstract class BookingServiceDto with _$BookingServiceDto {
  const factory BookingServiceDto({required String id, required String name}) = _BookingServiceDto;
  factory BookingServiceDto.fromJson(Map<String, dynamic> j) => _$BookingServiceDtoFromJson(j);
}

@freezed
abstract class BookingZoneDto with _$BookingZoneDto {
  const factory BookingZoneDto({required String id, required String name}) = _BookingZoneDto;
  factory BookingZoneDto.fromJson(Map<String, dynamic> j) => _$BookingZoneDtoFromJson(j);
}

@freezed
abstract class BookingAddressRefDto with _$BookingAddressRefDto {
  const factory BookingAddressRefDto({required String id}) = _BookingAddressRefDto;
  factory BookingAddressRefDto.fromJson(Map<String, dynamic> j) => _$BookingAddressRefDtoFromJson(j);
}

@freezed
abstract class TechnicianRefDto with _$TechnicianRefDto {
  const factory TechnicianRefDto({required String name, required String maskedPhone}) = _TechnicianRefDto;
  factory TechnicianRefDto.fromJson(Map<String, dynamic> j) => _$TechnicianRefDtoFromJson(j);
}

@freezed
abstract class DiagnosisDto with _$DiagnosisDto {
  const factory DiagnosisDto({required String issueName}) = _DiagnosisDto;
  factory DiagnosisDto.fromJson(Map<String, dynamic> j) => _$DiagnosisDtoFromJson(j);
}

@freezed
abstract class PartDto with _$PartDto {
  const factory PartDto({
    required String id, required String sku, required String name,
    required int ceilingPricePaise, required int qty,
  }) = _PartDto;
  factory PartDto.fromJson(Map<String, dynamic> j) => _$PartDtoFromJson(j);
}

@freezed
abstract class EstimateDto with _$EstimateDto {
  const factory EstimateDto({
    required int laborPaise, required int partsPaise,
    required int visitFeeCreditPaise, required int totalPayablePaise,
  }) = _EstimateDto;
  factory EstimateDto.fromJson(Map<String, dynamic> j) => _$EstimateDtoFromJson(j);
}

@freezed
abstract class PhotoDto with _$PhotoDto {
  const factory PhotoDto({required String kind, required String capturedAt, required String url}) = _PhotoDto;
  factory PhotoDto.fromJson(Map<String, dynamic> j) => _$PhotoDtoFromJson(j);
}

@freezed
abstract class PaymentSummaryDto with _$PaymentSummaryDto {
  const factory PaymentSummaryDto({required String status, required String method, required int amountPaise}) = _PaymentSummaryDto;
  factory PaymentSummaryDto.fromJson(Map<String, dynamic> j) => _$PaymentSummaryDtoFromJson(j);
}

@freezed
abstract class DisputeSummaryDto with _$DisputeSummaryDto {
  const factory DisputeSummaryDto({required String status, required String outcome, int? refundPaise}) = _DisputeSummaryDto;
  factory DisputeSummaryDto.fromJson(Map<String, dynamic> j) => _$DisputeSummaryDtoFromJson(j);
}

@freezed
abstract class BookingDto with _$BookingDto {
  const factory BookingDto({
    required String id,
    required String bookingNumber,
    required String state,
    required String scheduledSlot,
    required int visitFeePaise,
    required int laborPaise,
    String? laborTier,
    required BookingServiceDto service,
    required BookingZoneDto zone,
    required BookingAddressRefDto address,
    TechnicianRefDto? technician,
    DiagnosisDto? diagnosis,
    @Default(<PartDto>[]) List<PartDto> parts,
    required EstimateDto estimate,
    @Default(<PhotoDto>[]) List<PhotoDto> photos,
    PaymentSummaryDto? payment,
    DisputeSummaryDto? dispute,
  }) = _BookingDto;
  factory BookingDto.fromJson(Map<String, dynamic> j) => _$BookingDtoFromJson(j);
}
