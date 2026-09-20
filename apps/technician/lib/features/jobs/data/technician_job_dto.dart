import 'package:freezed_annotation/freezed_annotation.dart';
part 'technician_job_dto.freezed.dart';
part 'technician_job_dto.g.dart';

@freezed
abstract class JobServiceDto with _$JobServiceDto {
  const factory JobServiceDto({required String name, required String requiredSkill}) = _JobServiceDto;
  factory JobServiceDto.fromJson(Map<String, dynamic> j) => _$JobServiceDtoFromJson(j);
}

@freezed
abstract class JobZoneDto with _$JobZoneDto {
  const factory JobZoneDto({required String name}) = _JobZoneDto;
  factory JobZoneDto.fromJson(Map<String, dynamic> j) => _$JobZoneDtoFromJson(j);
}

@freezed
abstract class JobAddressDto with _$JobAddressDto {
  const factory JobAddressDto({
    required String line1,
    String? line2,
    String? landmark,
    required String pincode,
  }) = _JobAddressDto;
  factory JobAddressDto.fromJson(Map<String, dynamic> j) => _$JobAddressDtoFromJson(j);
}

// Directional masking: the technician only ever sees the customer's masked
// phone, never their name — mirrors the backend TechnicianJobDto exactly.
@freezed
abstract class JobCustomerDto with _$JobCustomerDto {
  const factory JobCustomerDto({required String maskedPhone}) = _JobCustomerDto;
  factory JobCustomerDto.fromJson(Map<String, dynamic> j) => _$JobCustomerDtoFromJson(j);
}

@freezed
abstract class JobPhotoDto with _$JobPhotoDto {
  const factory JobPhotoDto({required String kind, required String capturedAt, required String url}) =
      _JobPhotoDto;
  factory JobPhotoDto.fromJson(Map<String, dynamic> j) => _$JobPhotoDtoFromJson(j);
}

@freezed
abstract class TechnicianJobDto with _$TechnicianJobDto {
  const factory TechnicianJobDto({
    required String id,
    required String bookingNumber,
    required String state,
    required String scheduledSlot,
    required JobServiceDto service,
    required JobZoneDto zone,
    required int visitFeePaise,
    required int laborPaise,
    required JobAddressDto address,
    required JobCustomerDto customer,
    @Default(<JobPhotoDto>[]) List<JobPhotoDto> photos,
  }) = _TechnicianJobDto;
  factory TechnicianJobDto.fromJson(Map<String, dynamic> j) => _$TechnicianJobDtoFromJson(j);
}

@freezed
abstract class ArriveResultDto with _$ArriveResultDto {
  const factory ArriveResultDto({required String arrivalCode, bool? withinGeofence}) = _ArriveResultDto;
  factory ArriveResultDto.fromJson(Map<String, dynamic> j) => _$ArriveResultDtoFromJson(j);
}

@freezed
abstract class CashResultDto with _$CashResultDto {
  const factory CashResultDto({required String id, required String state, required int cashDebtPaise}) =
      _CashResultDto;
  factory CashResultDto.fromJson(Map<String, dynamic> j) => _$CashResultDtoFromJson(j);
}

@freezed
abstract class PhotoSignDto with _$PhotoSignDto {
  const factory PhotoSignDto({required String url, required String key, required String expiresAt}) =
      _PhotoSignDto;
  factory PhotoSignDto.fromJson(Map<String, dynamic> j) => _$PhotoSignDtoFromJson(j);
}

@freezed
abstract class PhotoConfirmDto with _$PhotoConfirmDto {
  const factory PhotoConfirmDto({required String id, required String kind, required String capturedAt}) =
      _PhotoConfirmDto;
  factory PhotoConfirmDto.fromJson(Map<String, dynamic> j) => _$PhotoConfirmDtoFromJson(j);
}
