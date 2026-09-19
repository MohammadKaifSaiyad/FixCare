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
