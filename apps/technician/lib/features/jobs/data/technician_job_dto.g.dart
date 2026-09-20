// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'technician_job_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_JobServiceDto _$JobServiceDtoFromJson(Map<String, dynamic> json) =>
    _JobServiceDto(
      name: json['name'] as String,
      requiredSkill: json['requiredSkill'] as String,
    );

Map<String, dynamic> _$JobServiceDtoToJson(_JobServiceDto instance) =>
    <String, dynamic>{
      'name': instance.name,
      'requiredSkill': instance.requiredSkill,
    };

_JobZoneDto _$JobZoneDtoFromJson(Map<String, dynamic> json) =>
    _JobZoneDto(name: json['name'] as String);

Map<String, dynamic> _$JobZoneDtoToJson(_JobZoneDto instance) =>
    <String, dynamic>{'name': instance.name};

_JobAddressDto _$JobAddressDtoFromJson(Map<String, dynamic> json) =>
    _JobAddressDto(
      line1: json['line1'] as String,
      line2: json['line2'] as String?,
      landmark: json['landmark'] as String?,
      pincode: json['pincode'] as String,
    );

Map<String, dynamic> _$JobAddressDtoToJson(_JobAddressDto instance) =>
    <String, dynamic>{
      'line1': instance.line1,
      'line2': instance.line2,
      'landmark': instance.landmark,
      'pincode': instance.pincode,
    };

_JobCustomerDto _$JobCustomerDtoFromJson(Map<String, dynamic> json) =>
    _JobCustomerDto(maskedPhone: json['maskedPhone'] as String);

Map<String, dynamic> _$JobCustomerDtoToJson(_JobCustomerDto instance) =>
    <String, dynamic>{'maskedPhone': instance.maskedPhone};

_JobPhotoDto _$JobPhotoDtoFromJson(Map<String, dynamic> json) => _JobPhotoDto(
  kind: json['kind'] as String,
  capturedAt: json['capturedAt'] as String,
  url: json['url'] as String,
);

Map<String, dynamic> _$JobPhotoDtoToJson(_JobPhotoDto instance) =>
    <String, dynamic>{
      'kind': instance.kind,
      'capturedAt': instance.capturedAt,
      'url': instance.url,
    };

_TechnicianJobDto _$TechnicianJobDtoFromJson(Map<String, dynamic> json) =>
    _TechnicianJobDto(
      id: json['id'] as String,
      bookingNumber: json['bookingNumber'] as String,
      state: json['state'] as String,
      scheduledSlot: json['scheduledSlot'] as String,
      service: JobServiceDto.fromJson(json['service'] as Map<String, dynamic>),
      zone: JobZoneDto.fromJson(json['zone'] as Map<String, dynamic>),
      visitFeePaise: (json['visitFeePaise'] as num).toInt(),
      laborPaise: (json['laborPaise'] as num).toInt(),
      address: JobAddressDto.fromJson(json['address'] as Map<String, dynamic>),
      customer: JobCustomerDto.fromJson(
        json['customer'] as Map<String, dynamic>,
      ),
      photos:
          (json['photos'] as List<dynamic>?)
              ?.map((e) => JobPhotoDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <JobPhotoDto>[],
    );

Map<String, dynamic> _$TechnicianJobDtoToJson(_TechnicianJobDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'bookingNumber': instance.bookingNumber,
      'state': instance.state,
      'scheduledSlot': instance.scheduledSlot,
      'service': instance.service,
      'zone': instance.zone,
      'visitFeePaise': instance.visitFeePaise,
      'laborPaise': instance.laborPaise,
      'address': instance.address,
      'customer': instance.customer,
      'photos': instance.photos,
    };

_ArriveResultDto _$ArriveResultDtoFromJson(Map<String, dynamic> json) =>
    _ArriveResultDto(
      arrivalCode: json['arrivalCode'] as String,
      withinGeofence: json['withinGeofence'] as bool?,
    );

Map<String, dynamic> _$ArriveResultDtoToJson(_ArriveResultDto instance) =>
    <String, dynamic>{
      'arrivalCode': instance.arrivalCode,
      'withinGeofence': instance.withinGeofence,
    };

_CashResultDto _$CashResultDtoFromJson(Map<String, dynamic> json) =>
    _CashResultDto(
      id: json['id'] as String,
      state: json['state'] as String,
      cashDebtPaise: (json['cashDebtPaise'] as num).toInt(),
    );

Map<String, dynamic> _$CashResultDtoToJson(_CashResultDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'state': instance.state,
      'cashDebtPaise': instance.cashDebtPaise,
    };

_PhotoSignDto _$PhotoSignDtoFromJson(Map<String, dynamic> json) =>
    _PhotoSignDto(
      url: json['url'] as String,
      key: json['key'] as String,
      expiresAt: json['expiresAt'] as String,
    );

Map<String, dynamic> _$PhotoSignDtoToJson(_PhotoSignDto instance) =>
    <String, dynamic>{
      'url': instance.url,
      'key': instance.key,
      'expiresAt': instance.expiresAt,
    };

_PhotoConfirmDto _$PhotoConfirmDtoFromJson(Map<String, dynamic> json) =>
    _PhotoConfirmDto(
      id: json['id'] as String,
      kind: json['kind'] as String,
      capturedAt: json['capturedAt'] as String,
    );

Map<String, dynamic> _$PhotoConfirmDtoToJson(_PhotoConfirmDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'kind': instance.kind,
      'capturedAt': instance.capturedAt,
    };
